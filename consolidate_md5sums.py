#!/usr/bin/env python3
"""
Consolidate md5sums.txt files from Reports back into output directories.

For each config_id in output/, this script:
1. Extracts the lane number from the config_id
2. Finds all md5sums.txt files in Reports/{project}/lane{N}/
3. Merges them into output/{config_id}/md5sums.txt
"""

import os
import re
import sys
import argparse
from pathlib import Path
from collections import defaultdict

def extract_lane_from_config_id(config_id):
    """Extract lane number from config_id like 'lane1_R1-151_I1-8_I2-8_R2-151'"""
    match = re.match(r'lane(\d+)', config_id)
    if match:
        return int(match.group(1))
    return None

def consolidate_md5sums(dry_run=False):
    """Consolidate md5sums.txt files from Reports to output directories.
    
    Args:
        dry_run: If True, only preview changes without writing files
    """
    
    output_dir = Path('output')
    reports_dir = Path('Reports')
    
    if not output_dir.exists():
        print(f"Output directory {output_dir} does not exist")
        return
    
    if not reports_dir.exists():
        print(f"Reports directory {reports_dir} does not exist")
        return
    
    if dry_run:
        print("[DRY RUN] No files will be written\n")
    
    # Iterate over all config_id directories in output/
    config_dirs = [d for d in output_dir.iterdir() if d.is_dir() and re.match(r'lane\d+', d.name)]
    
    print(f"Found {len(config_dirs)} config directories in output/")
    
    for config_path in sorted(config_dirs):
        config_id = config_path.name
        lane = extract_lane_from_config_id(config_id)
        
        if lane is None:
            print(f"Skipping {config_id}: could not extract lane number")
            continue
        
        print(f"\nProcessing {config_id} (lane {lane})...")
        
        # Find all md5sums.txt files for this lane in Reports and organize by project
        projects_md5s = {}
        
        for project_dir in reports_dir.iterdir():
            if not project_dir.is_dir():
                continue
            
            project_name = project_dir.name
            lane_dir = project_dir / f'lane{lane}'
            md5_file = lane_dir / 'md5sums.txt'
            
            if md5_file.exists():
                print(f"  Found {str(md5_file)}")
                
                try:
                    md5_entries = []
                    with open(md5_file, 'r') as f:
                        for line in f:
                            line = line.strip()
                            if line:
                                md5_entries.append(line)
                    
                    # Sort by filename (second column) for consistency
                    md5_entries.sort(key=lambda x: x.split()[1] if len(x.split()) > 1 else x)
                    projects_md5s[project_name] = md5_entries
                except Exception as e:
                    print(f"    Error reading {md5_file}: {e}")
                    continue
        
        if not projects_md5s:
            print(f"  No md5sums.txt files found for lane {lane}")
            continue
        
        # Write consolidated md5sums.txt for each project
        for project_name, md5_entries in sorted(projects_md5s.items()):
            project_path = config_path / project_name
            output_md5_file = project_path / 'md5sums.txt'
            
            if dry_run:
                print(f"  [DRY RUN] Would write {str(output_md5_file)} ({len(md5_entries)} entries)")
            else:
                try:
                    project_path.mkdir(parents=True, exist_ok=True)
                    with open(output_md5_file, 'w') as f:
                        for entry in md5_entries:
                            f.write(entry + '\n')
                    
                    print(f"  ✓ Wrote {str(output_md5_file)} ({len(md5_entries)} entries)")
                except Exception as e:
                    print(f"  Error writing {output_md5_file}: {e}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Consolidate md5sums.txt files from Reports to output directories')
    parser.add_argument('--dry-run', action='store_true', help='Preview changes without writing files')
    args = parser.parse_args()
    
    consolidate_md5sums(dry_run=args.dry_run)
