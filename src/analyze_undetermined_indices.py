#!/usr/bin/env python3
import glob
import io
import os
from collections import Counter
import sys
import csv
import argparse
import subprocess


def open_fastq(file_path):
    """Open a gzipped FASTQ using pigz (multi-threaded) if available, else gzip."""
    try:
        proc = subprocess.Popen(
            ['pigz', '-dc', file_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=1 << 20,
        )
        return io.TextIOWrapper(proc.stdout, encoding='utf-8', errors='replace'), proc
    except FileNotFoundError:
        import gzip
        return gzip.open(file_path, 'rt'), None


def get_top_indices(file_pattern, top_n=20, output_file=None, limit=None):
    """Single-pass: count all clusters AND collect index sample using pigz."""
    index_counter = Counter()
    total_reads = 0
    total_clusters = 0

    exclude_index_prefixes = globals().get('exclude_index_prefixes', set())

    files = sorted(glob.glob(file_pattern))
    if not files:
        print(f"No files found matching pattern: {file_pattern}")
        return

    r1_files = [f for f in files if "_R1_" in f]

    if not r1_files:
        print("No standard R1 files found. Processing all files individually...")
        files_to_process = files
        paired_mode = False
    else:
        print(f"Found {len(r1_files)} R1 file(s). Single-pass: counting all clusters + sampling first {limit:,} reads...")
        files_to_process = r1_files
        paired_mode = True

    for file_path in files_to_process:
        if paired_mode:
            r2_path = file_path.replace("_R1_", "_R2_")
            label = (f"{os.path.basename(file_path)} & {os.path.basename(r2_path)}"
                     if os.path.exists(r2_path) else os.path.basename(file_path))
            print(f"Processing pair: {label}")
        else:
            print(f"Processing: {os.path.basename(file_path)}")

        proc = None
        try:
            f, proc = open_fastq(file_path)
            sampling_done = False
            for i, line in enumerate(f):
                if i % 4 != 0:
                    continue

                total_clusters += 1

                if sampling_done:
                    # Sampling complete — keep iterating only to count total clusters.
                    # No string parsing needed.
                    if total_clusters % 5000000 == 0:
                        print(f"  Counted {total_clusters:,} clusters so far...", end='\r')
                    continue

                last_colon_idx = line.rfind(':')
                if last_colon_idx != -1:
                    index_sequence = line[last_colon_idx + 1:].rstrip()

                    if not (exclude_index_prefixes and
                            any(index_sequence.startswith(p) for p in exclude_index_prefixes)):
                        index_counter[index_sequence] += 1
                        total_reads += 1

                        if total_reads % 1000000 == 0:
                            print(f"  Sampled {total_reads:,} clusters (total counted: {total_clusters:,})...", end='\r')

                if limit and total_reads >= limit:
                    print(f"\n  Reached sampling limit of {limit:,}. Continuing count-only pass...")
                    sampling_done = True

            f.close()
        except Exception as e:
            print(f"Error reading {file_path}: {e}")
        finally:
            if proc is not None:
                proc.wait()

    print(f"\nTotal clusters in file(s): {total_clusters:,}")
    print(f"Sampled {total_reads:,} clusters.")

    print(f"\nTop {top_n} detected index sequences:")
    print(f"{'Count':<10} {'Type':<10} {'Index Sequence'}")
    print("-" * 40)

    for index, count in index_counter.most_common(top_n):
        index_type = "Dual" if "+" in index else "Single"
        print(f"{count:<10} {index_type:<10} {index}")

    if output_file:
        try:
            with open(output_file, 'w', newline='') as f:
                pct = round((total_reads / total_clusters) * 100) if total_clusters else 0
                f.write(f"Surveyed {total_reads:,} of {total_clusters:,} clusters ({pct}%)\n")

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
    parser.add_argument("--limit", type=int, help="Limit number of reads to sample per file")
    parser.add_argument("--exclude-indexes", help="File with index prefixes to exclude (one per line)")

    args = parser.parse_args()

    search_path = args.input_pattern
    output_csv = args.output
    limit = args.limit
    exclude_indexes_file = args.exclude_indexes

    exclude_index_prefixes = set()
    if exclude_indexes_file:
        try:
            with open(exclude_indexes_file) as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        prefix = line.split(',')[0].strip() if ',' in line else line
                        exclude_index_prefixes.add(prefix)
            print(f"Loaded {len(exclude_index_prefixes)} index prefixes to exclude from {exclude_indexes_file}")
        except Exception as e:
            print(f"Warning: Could not load exclude indexes: {e}")

    globals()['exclude_index_prefixes'] = exclude_index_prefixes

    if output_csv is None:
        base_name = os.path.basename(search_path)
        for ext in ['.fastq.gz', '.fastq', '.gz']:
            if base_name.endswith(ext):
                base_name = base_name[:-len(ext)]
                break
        clean_name = base_name.replace('*', '_').replace('?', '_')
        output_csv = f"top_indices_{clean_name}.csv"

    get_top_indices(search_path, output_file=output_csv, limit=limit)
