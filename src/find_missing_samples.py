#!/usr/bin/env python3
"""
Find samples that are missing from the compiled read counts file.
Compares samples in renaming_map files vs samples in the count CSV.
"""

import os
import sys
import glob
import pandas as pd
import argparse
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description='Find missing samples in read count file')
    parser.add_argument('--count-file', default='results/xR081_B_Side-count.csv',
                       help='Path to the compiled count CSV file')
    parser.add_argument('--maps-dir', default='results',
                       help='Directory containing renaming_map CSV files')
    parser.add_argument('--output', default=None,
                       help='Output file for missing samples (default: print to stdout)')
    return parser.parse_args()


def read_renaming_maps(maps_dir):
    """Read all renaming_map CSV files and extract sample information."""
    expected_samples = []
    
    map_files = glob.glob(f"{maps_dir}/renaming_map_*.csv")
    
    for map_file in sorted(map_files):
        try:
            df = pd.read_csv(map_file)
            
            # Extract config_id from filename
            basename = os.path.basename(map_file)
            config_id = basename.replace('renaming_map_', '').replace('.csv', '')
            
            for _, row in df.iterrows():
                # Extract fields for potential barcode-format name
                run = str(row.get('Run', '')).strip()
                lane = int(row.get('Lane', 0)) if pd.notna(row.get('Lane')) else 0
                group = int(row.get('Group', 0)) if pd.notna(row.get('Group')) else 0
                position = str(row.get('Position', '')).strip()
                index = str(row.get('index', '')).strip()
                index2_raw = row.get('index2')
                index2 = str(index2_raw).strip() if pd.notna(index2_raw) else ''
                short_name = str(row.get('Sample_Name', '')).strip()
                
                # Build barcode-format name if possible
                # Support both dual-index and single-index barcodes
                if run and position and index:
                    if index2:
                        barcode_name = f"{run}-L{lane}-G{group}-{position}-{index}-{index2}"
                    else:
                        # Single-index (e.g., BD samples with empty index2)
                        barcode_name = f"{run}-L{lane}-G{group}-{position}-{index}"
                else:
                    barcode_name = None
                
                sample_info = {
                    'sample_name': short_name,  # Primary name to look for
                    'barcode_name': barcode_name,  # Alternate name (may be in count file instead)
                    'project': str(row.get('Sample_Project', '')),
                    'lane': lane,
                    'group': group,
                    'position': position,
                    'config_id': config_id,
                    'map_file': basename
                }
                expected_samples.append(sample_info)
        except Exception as e:
            print(f"Error reading {map_file}: {e}", file=sys.stderr)
            continue
    
    return expected_samples


def read_count_file(count_file):
    """Read the count CSV and extract sample names."""
    import csv
    samples_with_counts = set()
    
    try:
        with open(count_file, 'r') as f:
            reader = csv.reader(f)
            header = next(reader)  # Skip header
            
            # Header pattern: ,lane,group,sample,counts,lane,group,sample,counts,...
            # After proper CSV parsing: Index 0=empty, 1=lane, 2=group, 3=sample, 4=counts
            # Sample names are at indices: 3, 7, 11, 15, ... (every 4, starting at 3)
            for row in reader:
                for i in range(3, len(row), 4):
                    if i < len(row):
                        sample = row[i].strip()
                        if sample:
                            samples_with_counts.add(sample)
        
    except Exception as e:
        print(f"Error reading count file {count_file}: {e}", file=sys.stderr)
        return set()
    
    return samples_with_counts


def find_missing_samples(expected_samples, samples_with_counts):
    """Compare expected samples with samples that have counts."""
    missing = []
    
    for sample_info in expected_samples:
        sample_name = sample_info['sample_name']
        barcode_name = sample_info['barcode_name']
        
        # Check if either the short name OR the barcode name is in the count file
        found = False
        if sample_name in samples_with_counts:
            found = True
        elif barcode_name and barcode_name in samples_with_counts:
            found = True
        
        if not found:
            missing.append(sample_info)
    
    return missing


def format_output(missing_samples):
    """Format missing samples for output."""
    if not missing_samples:
        return "✓ All samples found in count file!\n"
    
    output = []
    output.append(f"Found {len(missing_samples)} missing samples:\n")
    output.append("=" * 120)
    output.append(f"{'Sample Name':<30} {'Project':<35} {'Lane':<6} {'Group':<6} {'Position':<10} {'Config ID':<30}")
    output.append("=" * 120)
    
    for sample in sorted(missing_samples, key=lambda x: (
        int(x['lane']) if str(x['lane']).isdigit() else 999, 
        int(x['group']) if str(x['group']).isdigit() else 999,
        x['sample_name']
    )):
        output.append(
            f"{sample['sample_name']:<30} "
            f"{sample['project']:<35} "
            f"{str(sample['lane']):<6} "
            f"{str(sample['group']):<6} "
            f"{sample['position']:<10} "
            f"{sample['config_id']:<30}"
        )
    
    output.append("=" * 120)
    output.append(f"\nTotal missing: {len(missing_samples)}")
    
    # Group by lane and group
    by_lane_group = {}
    for sample in missing_samples:
        key = (sample['lane'], sample['group'])
        if key not in by_lane_group:
            by_lane_group[key] = []
        by_lane_group[key].append(sample['sample_name'])
    
    if by_lane_group:
        output.append("\nMissing samples by Lane/Group:")
        for (lane, group), samples in sorted(by_lane_group.items()):
            output.append(f"  Lane {lane}, Group {group}: {len(samples)} samples missing")
            for sample in sorted(samples):
                output.append(f"    - {sample}")
    
    return "\n".join(output)


def main():
    args = parse_args()
    
    print("Reading renaming maps...", file=sys.stderr)
    expected_samples = read_renaming_maps(args.maps_dir)
    print(f"Found {len(expected_samples)} expected samples", file=sys.stderr)
    
    print("Reading count file...", file=sys.stderr)
    samples_with_counts = read_count_file(args.count_file)
    print(f"Found {len(samples_with_counts)} samples with counts", file=sys.stderr)
    
    print("Comparing...", file=sys.stderr)
    missing_samples = find_missing_samples(expected_samples, samples_with_counts)
    
    output_text = format_output(missing_samples)
    
    if args.output:
        with open(args.output, 'w') as f:
            f.write(output_text)
        print(f"\nResults written to {args.output}", file=sys.stderr)
    else:
        print("\n" + output_text)


if __name__ == '__main__':
    main()
