#!/usr/bin/env python3
"""
Fix position numbers in fastp and fastp_plots output filenames by matching on barcode sequences.
This renames JSON, HTML, and PNG files that were generated with incorrect position numbers.
"""

import os
import sys
import pandas as pd
import glob
import re
from pathlib import Path

def fix_fastp_filenames_by_barcode(config_id, results_dir, map_file):
    """Rename fastp and fastp_plots files to correct positions by matching on barcode sequences."""
    
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
        barcode_to_position[barcode] = position
    
    print(f"Loaded {len(barcode_to_position)} barcode->position mappings")
    
    # Find all fastp files: results/fastp/{config_id}/{sample_path}.json|html
    fastp_dir = os.path.join(results_dir, "fastp", config_id)
    fastp_files = []
    if os.path.exists(fastp_dir):
        fastp_files = glob.glob(os.path.join(fastp_dir, "**/*.json"), recursive=True)
        fastp_files.extend(glob.glob(os.path.join(fastp_dir, "**/*.html"), recursive=True))
    
    # Find all fastp_plots files: results/fastp_plots/{config_id}/{sample_path}-*.png
    plots_dir = os.path.join(results_dir, "fastp_plots", config_id)
    plots_files = []
    if os.path.exists(plots_dir):
        plots_files = glob.glob(os.path.join(plots_dir, "**/*.png"), recursive=True)
    
    all_files = fastp_files + plots_files
    
    renamed_count = 0
    already_correct = 0
    errors = []
    
    for file_path in all_files:
        filename = os.path.basename(file_path)
        dir_path = os.path.dirname(file_path)
        
        # Extract barcode and position from filename
        # Fastp files: {project}/{run}-L{lane}-G{group}-{position}-{barcode}.json|html
        # Fastp plots: {project}/{run}-L{lane}-G{group}-{position}-{barcode}-{plot_type}.png
        
        # Try to match the file pattern
        # Pattern: anything ending with -{barcode}-{position}[.json|.html] or -{barcode}-{position}-{plot_type}.png
        
        # For fastp JSON/HTML files
        json_html_match = re.match(r'^(.+?)-L(\d+)-G(\d+)-P(\d+)-([\w-]+)\.(json|html)$', filename)
        
        # For fastp_plots PNG files
        png_match = re.match(r'^(.+?)-L(\d+)-G(\d+)-P(\d+)-([\w-]+)-(mean_phred|base_comp)\.png$', filename)
        
        if json_html_match:
            run, lane, group, old_pos, barcode, ext = json_html_match.groups()
            old_position = f"P{old_pos}"
            
            if barcode not in barcode_to_position:
                errors.append(f"Barcode {barcode} not found in map: {filename}")
                continue
            
            correct_position = barcode_to_position[barcode]
            
            if old_position == correct_position:
                already_correct += 1
                continue
            
            new_filename = f"{run}-L{lane}-G{group}-{correct_position}-{barcode}.{ext}"
            
        elif png_match:
            run, lane, group, old_pos, barcode, plot_type = png_match.groups()
            old_position = f"P{old_pos}"
            
            if barcode not in barcode_to_position:
                errors.append(f"Barcode {barcode} not found in map: {filename}")
                continue
            
            correct_position = barcode_to_position[barcode]
            
            if old_position == correct_position:
                already_correct += 1
                continue
            
            new_filename = f"{run}-L{lane}-G{group}-{correct_position}-{barcode}-{plot_type}.png"
            
        else:
            # Filename doesn't match expected pattern, skip
            continue
        
        new_path = os.path.join(dir_path, new_filename)
        
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
    print(f"Summary for {config_id}:")
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
        print("Usage: python fix_fastp_filenames_by_barcode.py <config_id> <results_dir> <map_file>")
        sys.exit(1)
    
    config_id = sys.argv[1]
    results_dir = sys.argv[2]
    map_file = sys.argv[3]
    
    fix_fastp_filenames_by_barcode(config_id, results_dir, map_file)
