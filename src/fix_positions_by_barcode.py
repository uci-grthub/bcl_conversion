#!/usr/bin/env python3
"""
Fix position numbers in renamed FASTQ files by matching on barcode sequences.
This corrects files that were renamed with incorrect position numbers.
"""

import os
import sys
import pandas as pd
import glob
import re

def fix_positions_by_barcode(config_id, output_dir, map_file):
    """Rename files to correct positions by matching on barcode sequences."""
    
    if not os.path.exists(map_file):
        print(f"Map file {map_file} not found.")
        return
    
    try:
        df = pd.read_csv(map_file)
    except Exception as e:
        print(f"Error reading map file: {e}")
        return
    
    # Build barcode -> correct position mapping
    barcode_to_position = {}
    barcode_to_info = {}
    
    for i, row in df.iterrows():
        index1 = str(row['index']).strip()
        if index1.lower() == 'nan': index1 = ""
        
        index2 = str(row['index2']).strip()
        if index2.lower() == 'nan': index2 = ""
        
        if index2:
            barcode = f"{index1}-{index2}"
        else:
            barcode = index1
        
        position = str(row.get('Position', f"P{i+1:03d}")).strip()
        
        try:
            group = str(int(float(row['Group'])))
        except:
            group = str(row['Group']).strip()
            if group.lower() == 'nan': group = "Undetermined"
        
        run = str(row['Run']).strip()
        project = str(row['Sample_Project']).strip()
        
        try:
            lane = int(row['Lane'])
        except:
            lane = 0
        
        barcode_to_position[barcode] = position
        barcode_to_info[barcode] = {
            'position': position,
            'group': group,
            'lane': lane,
            'run': run,
            'project': project
        }
    
    print(f"Loaded {len(barcode_to_position)} barcode->position mappings")
    
    # Find all FASTQ files in output directory
    all_files = glob.glob(f"{output_dir}/**/*.fastq.gz", recursive=True)
    
    renamed_count = 0
    already_correct = 0
    errors = []
    
    for file_path in all_files:
        filename = os.path.basename(file_path)
        
        # Skip Undetermined files
        if filename.startswith('Undetermined'):
            continue
        
        # Parse filename: {run}-L{lane}-G{group}-{position}-{barcode}-{read}.fastq.gz
        # Example: Side-L7-G3-P175-GCCGCAAC-AGACATGA-R1.fastq.gz
        match = re.match(r'^(.+?)-L(\d+)-G(\d+)-P(\d+)-([\w-]+)-([RI][12]).fastq.gz$', filename)
        
        if not match:
            # Try Illumina format: {sample}_S{num}_L{lane}_{read}_001.fastq.gz
            # These don't need fixing
            continue
        
        run, lane, group, old_pos, barcode, read = match.groups()
        old_position = f"P{old_pos}"
        
        # Look up correct position
        if barcode not in barcode_to_position:
            errors.append(f"Barcode {barcode} not found in map: {filename}")
            continue
        
        correct_position = barcode_to_position[barcode]
        
        if old_position == correct_position:
            already_correct += 1
            continue
        
        # Build new filename with correct position
        new_filename = f"{run}-L{lane}-G{group}-{correct_position}-{barcode}-{read}.fastq.gz"
        new_path = os.path.join(os.path.dirname(file_path), new_filename)
        
        if os.path.exists(new_path):
            print(f"Warning: Target already exists, skipping: {new_filename}")
            continue
        
        print(f"Renaming: {filename}")
        print(f"      ->: {new_filename}")
        
        try:
            os.rename(file_path, new_path)
            renamed_count += 1
        except Exception as e:
            errors.append(f"Error renaming {filename}: {e}")
    
    print(f"\n{'='*60}")
    print(f"Summary:")
    print(f"  Files renamed: {renamed_count}")
    print(f"  Already correct: {already_correct}")
    print(f"  Errors: {len(errors)}")
    
    if errors:
        print(f"\nErrors encountered:")
        for err in errors[:10]:  # Show first 10 errors
            print(f"  - {err}")
        if len(errors) > 10:
            print(f"  ... and {len(errors) - 10} more")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python fix_positions_by_barcode.py <config_id> <output_dir> <map_file>")
        sys.exit(1)
    
    config_id = sys.argv[1]
    output_dir = sys.argv[2]
    map_file = sys.argv[3]
    
    fix_positions_by_barcode(config_id, output_dir, map_file)
