#!/usr/bin/env python3
import gzip
import glob
import os
from collections import Counter
import sys
import csv
import argparse
import subprocess

def count_total_clusters(files_to_process):
    """Count total clusters in input files using zcat and wc for speed."""
    try:
        # Use zcat to pipe gzipped files through wc - much faster than Python
        file_list = ' '.join(f'"{f}"' for f in files_to_process)
        result = subprocess.run(f'pigz -dc {file_list} | awk \'{{c++}} END {{print c}}\'', shell=True, capture_output=True, text=True)
        total_lines = int(result.stdout.strip())
        return total_lines // 4  # Convert lines to clusters (4 lines per FASTQ record)
    except Exception as e:
        print(f"Warning: Could not count total clusters: {e}")
        return None

def get_top_indices(file_pattern, top_n=20, output_file=None, limit=None):
    index_counter = Counter()
    total_reads = 0
    
    files = sorted(glob.glob(file_pattern))
    if not files:
        print(f"No files found matching pattern: {file_pattern}")
        return

    # Identify R1 files to process pairs
    r1_files = [f for f in files if "_R1_" in f]
    
    # If no R1 files found, fall back to processing all files individually
    if not r1_files:
        print("No standard R1 files found. Processing all files individually...")
        files_to_process = files
        paired_mode = False
    else:
        print(f"Found {len(r1_files)} R1 files. Processing as pairs...")
        files_to_process = r1_files
        paired_mode = True
    
    # Count total clusters in input files for accurate percentage
    total_clusters = count_total_clusters(files_to_process[0] if not paired_mode else files_to_process)
    if total_clusters:
        print(f"Total clusters in input files: {total_clusters:,}")
    
    for file_path in files_to_process:
        if paired_mode:
            r2_path = file_path.replace("_R1_", "_R2_")
            if os.path.exists(r2_path):
                print(f"Processing pair: {os.path.basename(file_path)} & {os.path.basename(r2_path)}")
            else:
                print(f"Processing single (R2 not found): {os.path.basename(file_path)}")
        else:
            print(f"Processing: {os.path.basename(file_path)}")

        try:
            with gzip.open(file_path, 'rt') as f:
                for i, line in enumerate(f):
                    if limit and (i // 4) >= limit:
                        print(f"Reached limit of {limit} clusters for this file.")
                        break
                    
                    # FASTQ format: 4 lines per record. Header is the 1st line (index 0, 4, 8...)
                    if i % 4 == 0:
                        # Illumina header format usually ends with index info
                        # Example: @... 1:N:0:ATGC+ATGC
                        # Optimization: rsplit is faster if we look from the end
                        # Optimization: avoid strip() if we know the structure
                        
                        # Find the last colon
                        last_colon_idx = line.rfind(':')
                        if last_colon_idx != -1:
                            # The index sequence is everything after the last colon, but we need to be careful about newlines
                            index_sequence = line[last_colon_idx+1:].rstrip()
                            index_counter[index_sequence] += 1
                            total_reads += 1
                            
                            if total_reads % 1000000 == 0:
                                print(f"Processed {total_reads} clusters...", end='\r')
        except Exception as e:
            print(f"Error reading {file_path}: {e}")
            
    print(f"\nProcessed {total_reads} total clusters.")

    print(f"\nTop {top_n} detected index sequences:")
    print(f"{'Count':<10} {'Type':<10} {'Index Sequence'}")
    print("-" * 40)
    
    for index, count in index_counter.most_common(top_n):
        index_type = "Dual" if "+" in index else "Single"
        print(f"{count:<10} {index_type:<10} {index}")

    if output_file:
        try:
            with open(output_file, 'w', newline='') as f:
                if total_clusters:
                    pct = round((total_reads / total_clusters) * 100)
                    f.write(f"Surveyed {total_reads:,} of {total_clusters:,} clusters ({pct}%)\n")
                else:
                    f.write(f"Surveyed {total_reads:,} clusters\n")

                writer = csv.writer(f)
                writer.writerow(['Count', 'Type', 'Index Sequence'])
                for index, count in index_counter.most_common(top_n):
                    index_type = "Dual" if "+" in index else "Single"
                    writer.writerow([count, index_type, index])
            print(f"\nResults exported to {output_file}")
        except Exception as e:
            print(f"Error writing to {output_file}: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Analyze top index sequences from FASTQ files.")
    parser.add_argument("input_pattern", nargs='?', default="data/FASTQ/Undetermined/Undetermined*L004*fastq.gz", help="Input file pattern (glob)")
    parser.add_argument("--output", "-o", help="Output CSV file path")
    parser.add_argument("--limit", type=int, help="Limit number of reads to process per file")

    args = parser.parse_args()
    
    search_path = args.input_pattern
    output_csv = args.output
    limit = args.limit

    if output_csv is None:
        # Generate default output filename based on input pattern
        base_name = os.path.basename(search_path)
        # Remove common extensions
        for ext in ['.fastq.gz', '.fastq', '.gz']:
            if base_name.endswith(ext):
                base_name = base_name[:-len(ext)]
                break
        
        # Sanitize filename
        clean_name = base_name.replace('*', '_').replace('?', '_')
        output_csv = f"top_indices_{clean_name}.csv"
        
    get_top_indices(search_path, output_file=output_csv, limit=limit)
