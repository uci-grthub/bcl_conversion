#!/usr/bin/env python3
"""
Fix output file positions that are offset due to sample removal from lane1.

When samples are removed from lane1 (e.g., M24_VDJ/GEX reduction from 12 to 10),
the regenerated renaming maps shift all lane2+ global positions down by that offset.
However, output files may have already been renamed using the old map (+offset positions).

This script corrects files in specified lanes by:
1. Analyzing position mismatches between files and renaming maps
2. Detecting the consistent offset
3. Renaming files to correct positions

Usage:
    python3 src/fix_output_files_position_shift_v2.py [--dry-run] [--verbose]

Options:
    --dry-run      Show what would be changed without making changes
    --verbose      Show detailed information about each file
"""

import os
import sys
import glob
import re
import pandas as pd
from pathlib import Path
from typing import Dict, Tuple, List, Optional

def extract_position_number(position_str: str) -> int:
    """Extract numeric position from 'P001', 'P123', etc."""
    match = re.match(r'P(\d+)', position_str)
    return int(match.group(1)) if match else 0

def load_renaming_map(map_file: str) -> Dict[str, Dict]:
    """Load renaming map and create a lookup by barcode."""
    if not os.path.exists(map_file):
        print(f"Warning: Map file not found: {map_file}")
        return {}
    
    try:
        df = pd.read_csv(map_file)
    except Exception as e:
        print(f"Error reading {map_file}: {e}")
        return {}
    
    barcode_map = {}
    for _, row in df.iterrows():
        index1 = str(row.get('index', '')).strip()
        if index1.lower() == 'nan':
            index1 = ''
        
        index2 = str(row.get('index2', '')).strip()
        if index2.lower() == 'nan':
            index2 = ''
        
        barcode = f"{index1}-{index2}" if index2 else index1
        
        barcode_map[barcode] = {
            'position': str(row.get('Position', '')).strip(),
            'sample_id': str(row.get('Sample_ID', '')).strip(),
            'sample_name': str(row.get('Sample_Name', '')).strip(),
            'group': str(row.get('Group', '')).strip(),
            'project': str(row.get('Sample_Project', '')).strip(),
            'lane': int(row.get('Lane', 0)),
        }
    
    return barcode_map

def parse_renamed_filename(filename: str) -> Optional[Tuple[str, int, int, int, str, str]]:
    """Parse renamed FASTQ filename: {run}-L{lane}-G{group}-P{pos}-{barcode}-{read}.fastq.gz"""
    pattern = r'^(.+?)-L(\d+)-G(\d+)-P(\d+)-([\w\-]+)-(R[12I12])\.fastq\.gz$'
    match = re.match(pattern, filename)
    
    if match:
        run, lane, group, pos, barcode, read = match.groups()
        return run, int(lane), int(group), int(pos), barcode, read
    
    return None

def analyze_lane_positions(lane: int, output_base_dir: str, map_file: str) -> Dict:
    """Analyze position mismatches for a lane without making changes."""
    barcode_map = load_renaming_map(map_file)
    if not barcode_map:
        return {}
    
    file_positions = {}  # barcode -> [file_positions]
    
    pattern = os.path.join(output_base_dir, "**/*.fastq.gz")
    all_files = glob.glob(pattern, recursive=True)
    
    for file_path in all_files:
        filename = os.path.basename(file_path)
        
        if filename.startswith('Undetermined'):
            continue
        
        parsed = parse_renamed_filename(filename)
        if not parsed:
            continue
        
        run, file_lane, group, old_pos, barcode, read = parsed
        
        if file_lane != lane:
            continue
        
        if barcode not in file_positions:
            file_positions[barcode] = []
        file_positions[barcode].append(old_pos)
    
    # Compare with map
    analysis = {}
    for barcode, file_pos_list in file_positions.items():
        if barcode not in barcode_map:
            continue
        
        correct_pos = extract_position_number(barcode_map[barcode]['position'])
        
        # Calculate offset
        offsets = [fp - correct_pos for fp in file_pos_list]
        
        if offsets and offsets[0] != 0:  # Only include if there's a mismatch
            analysis[barcode] = {
                'map_position': correct_pos,
                'file_positions': sorted(set(file_pos_list)),
                'offset': offsets[0] if len(set(offsets)) == 1 else max(set(offsets), key=offsets.count),
                'count': len(file_pos_list)
            }
    
    return analysis

def process_lane_output(lane: int, output_base_dir: str, map_file: str, 
                       dry_run: bool = False, verbose: bool = False) -> Tuple[int, Dict]:
    """Process all files in a lane output directory."""
    barcode_map = load_renaming_map(map_file)
    if not barcode_map:
        print(f"Lane {lane}: Could not load renaming map from {map_file}")
        return 0, {}
    
    # Analyze positions first
    analysis = analyze_lane_positions(lane, output_base_dir, map_file)
    
    if not analysis:
        if verbose:
            print(f"Lane {lane}: No position mismatches found")
        return 0, {}
    
    # Print analysis
    print(f"\nLane {lane} Position Analysis:")
    offsets = set(a['offset'] for a in analysis.values())
    if len(offsets) == 1:
        offset = list(offsets)[0]
        print(f"  Detected consistent offset: {offset:+d} (files are {offset:+d} from correct positions)")
        print(f"  Affected barcodes: {len(analysis)}")
    else:
        print(f"  WARNING: Multiple different offsets detected: {offsets}")
        print(f"  Affected barcodes: {len(analysis)}")
    
    if verbose:
        for barcode, info in sorted(analysis.items())[:5]:
            print(f"    {barcode}: map=P{info['map_position']:03d}, files={[f'P{p:03d}' for p in info['file_positions']]}")
        if len(analysis) > 5:
            print(f"    ... and {len(analysis) - 5} more")
    
    renamed_count = 0
    errors = []
    
    # Find all FASTQ files in lane output
    pattern = os.path.join(output_base_dir, "**/*.fastq.gz")
    all_files = glob.glob(pattern, recursive=True)
    
    for file_path in all_files:
        filename = os.path.basename(file_path)
        dir_path = os.path.dirname(file_path)
        
        if filename.startswith('Undetermined'):
            continue
        
        parsed = parse_renamed_filename(filename)
        if not parsed:
            continue
        
        run, file_lane, group, old_pos, barcode, read = parsed
        
        if file_lane != lane:
            continue
        
        if barcode not in analysis:
            continue  # No mismatch for this barcode
        
        correct_info = barcode_map[barcode]
        correct_position = correct_info['position']
        correct_pos_num = extract_position_number(correct_position)
        
        if old_pos == correct_pos_num:
            continue  # Already correct
        
        new_filename = f"{run}-L{file_lane}-G{group}-{correct_position}-{barcode}-{read}.fastq.gz"
        new_path = os.path.join(dir_path, new_filename)
        
        if dry_run:
            print(f"  Would rename: {filename} -> {new_filename}")
        else:
            try:
                if os.path.exists(new_path):
                    os.remove(new_path)
                os.rename(file_path, new_path)
                if verbose:
                    print(f"  Renamed: {filename} -> {new_filename}")
            except Exception as e:
                errors.append(f"  Error renaming {filename}: {e}")
        
        renamed_count += 1
    
    if errors:
        print(f"\nLane {lane} Errors:")
        for error in errors[:10]:
            print(error)
        if len(errors) > 10:
            print(f"  ... and {len(errors) - 10} more errors")
    
    return renamed_count, analysis

def main():
    dry_run = '--dry-run' in sys.argv
    verbose = '--verbose' in sys.argv
    
    # Lanes to fix by default
    lanes_to_fix = [2, 3, 4]
    
    if dry_run:
        print("Running in DRY-RUN mode (no changes will be made)\n")
    else:
        print("Running in LIVE mode (files will be renamed)\n")
    
    base_output_dir = "output"
    
    if not os.path.exists(base_output_dir):
        print(f"Error: Output directory not found: {base_output_dir}")
        sys.exit(1)
    
    total_renamed = 0
    all_analysis = {}
    
    for lane in sorted(lanes_to_fix):
        lane_dir = os.path.join(base_output_dir, f"lane{lane}")
        map_file = f"results/renaming_map_lane{lane}.csv"
        
        if not os.path.exists(lane_dir):
            print(f"Lane {lane}: Output directory not found: {lane_dir}")
            continue
        
        count, analysis = process_lane_output(lane, lane_dir, map_file, dry_run, verbose)
        total_renamed += count
        if analysis:
            all_analysis[lane] = analysis
    
    print(f"\n{'='*60}")
    print(f"Total files processed: {total_renamed}")
    
    if all_analysis:
        print(f"\nSummary by lane:")
        for lane in sorted(all_analysis.keys()):
            print(f"  Lane {lane}: {len(all_analysis[lane])} barcodes with position mismatches")
    
    if dry_run:
        print("Run without --dry-run to apply changes")
    elif total_renamed > 0:
        print("All files have been renamed successfully!")

if __name__ == '__main__':
    main()
