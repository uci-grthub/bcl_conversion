#!/usr/bin/env python3
"""
Parse Snakemake benchmark files to extract timing data per rule.
Benchmark files contain actual execution times (not wall clock with queuing delays).
"""
import os
import csv
import glob
from statistics import mean, median
import math


def format_time_hms(seconds):
    """Format seconds into HH:MM:SS format."""
    if not seconds or not math.isfinite(seconds):
        return ""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"


def parse_benchmark_file(path):
    """Parse a single .bench file and return the duration in seconds."""
    with open(path, 'r', encoding='utf8') as fh:
        reader = csv.DictReader(fh, delimiter='\t')
        for row in reader:
            s_str = row.get('s', '').strip()
            if s_str:
                try:
                    return float(s_str)
                except ValueError:
                    pass
    return None


def extract_rule_from_filename(filename):
    """Extract rule name from benchmark filename (e.g., 'bcl_convert_lane1_...' -> 'bcl_convert')."""
    base = os.path.basename(filename)
    if not base.endswith('.bench'):
        return None
    base = base[:-6]  # remove .bench
    # Common rule prefixes
    for rule in ['bcl_convert', 'analyze_undetermined', 'fastp_sample', 'fastp_plots_sample',
                 'fastp_per_config', 'fastp_plots_per_config', 'fastp_plots_lane',
                 'calculate_md5sums', 'project_link', 'verify_project_links', 
                 'report_order_id', 'send_order_email', 'summarize_project_reads',
                 'generate_renaming_map', 'generate_exclude_indexes', 'generate_samplesheets',
                 'rescan_nextcloud', 'consolidate_project_links', 'compile_read_counts',
                 'send_read_counts_email', 'rsync_to_external_drive']:
        if base.startswith(rule):
            return rule
    # Fallback: use everything before first underscore or entire name
    parts = base.split('_')
    return parts[0] if parts else base


def main():
    repo_root = os.getcwd()
    benchmark_dir = os.path.join(repo_root, 'benchmarks')
    
    if not os.path.exists(benchmark_dir):
        print(f"Benchmarks directory not found at {benchmark_dir}")
        return 2

    # Find all .bench files
    bench_files = glob.glob(os.path.join(benchmark_dir, '*.bench'))
    # Exclude reverse complement jobs
    bench_files = [f for f in bench_files if '_rc_' not in os.path.basename(f)]
    if not bench_files:
        print(f"No .bench files found in {benchmark_dir}")
        return 3

    os.makedirs('reports', exist_ok=True)
    entries_csv = os.path.join('reports', 'benchmark_entries.csv')
    agg_csv = os.path.join('reports', 'timings_per_rule.csv')

    rows = []
    durations_by_rule = {}

    # Parse each benchmark file
    for bench_file in bench_files:
        duration = parse_benchmark_file(bench_file)
        rule = extract_rule_from_filename(bench_file)
        
        if duration is not None and rule:
            rows.append({
                'rule': rule,
                'benchmark_file': os.path.basename(bench_file),
                'duration_seconds': f"{duration:.6f}"
            })
            
            if math.isfinite(duration):
                durations_by_rule.setdefault(rule, []).append(duration)

    # Write raw entries
    with open(entries_csv, 'w', newline='', encoding='utf8') as fh:
        writer = csv.DictWriter(fh, fieldnames=['rule', 'benchmark_file', 'duration_seconds'])
        writer.writeheader()
        for r in sorted(rows, key=lambda x: (x['rule'], x['benchmark_file'])):
            writer.writerow(r)

    # Aggregate
    agg_rows = []
    for rule, durs in sorted(durations_by_rule.items()):
        cnt = len(durs)
        total = sum(durs)
        mn = min(durs)
        mx = max(durs)
        avg = mean(durs) if cnt else 0
        med = median(durs) if cnt else 0
        agg_rows.append({
            'rule': rule,
            'count': cnt,
            'total_seconds': f"{total:.6f}",
            'total_hms': format_time_hms(total),
            'mean_seconds': f"{avg:.6f}" if avg else '',
            'median_seconds': f"{med:.6f}" if med else '',
            'min_seconds': f"{mn:.6f}",
            'max_seconds': f"{mx:.6f}"
        })

    # Calculate grand total
    grand_total_seconds = sum(float(r['total_seconds']) for r in agg_rows)
    total_count = sum(r['count'] for r in agg_rows)
    
    with open(agg_csv, 'w', newline='', encoding='utf8') as fh:
        writer = csv.DictWriter(fh, fieldnames=['rule', 'count', 'total_seconds', 'total_hms', 'mean_seconds', 'median_seconds', 'min_seconds', 'max_seconds'])
        writer.writeheader()
        for r in agg_rows:
            writer.writerow(r)
        
        # Add total row
        writer.writerow({
            'rule': 'TOTAL',
            'count': total_count,
            'total_seconds': f"{grand_total_seconds:.6f}",
            'total_hms': format_time_hms(grand_total_seconds),
            'mean_seconds': '',
            'median_seconds': '',
            'min_seconds': '',
            'max_seconds': ''
        })

    print('Wrote', entries_csv)
    print('Wrote', agg_csv)
    print(f'Total processing time: {grand_total_seconds:.2f} seconds ({grand_total_seconds/3600:.2f} hours)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
