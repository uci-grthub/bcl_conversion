#!/usr/bin/env python3
"""Summarize Snakemake benchmark files: duration and memory stats per rule.

Reads all *.bench files under benchmarks/, matches each to a rule name using
the benchmark patterns in the Snakefile, then writes reports/benchmark_summary.csv.
"""

import os
import re
import csv
from pathlib import Path
from collections import defaultdict
from statistics import mean, median


BENCHMARKS_DIR = 'benchmarks'
SNAKEFILE = 'Snakefile'
OUT_CSV = os.path.join('reports', 'benchmark_summary.csv')

# columns present in every Snakemake benchmark file
BENCH_COLS = ['s', 'max_rss', 'max_vms', 'cpu_time', 'io_in', 'io_out', 'mean_load']


def load_rule_patterns(snakefile_path):
    """Return {rule_name: benchmark_path_pattern} parsed from the Snakefile."""
    patterns = {}
    current_rule = None
    in_benchmark = False
    with open(snakefile_path, 'r', encoding='utf8') as fh:
        for line in fh:
            # new rule or checkpoint
            m = re.match(r'^(?:rule|checkpoint)\s+(\w+)\s*:', line)
            if m:
                current_rule = m.group(1)
                in_benchmark = False
                continue
            # benchmark directive
            if re.match(r'\s+benchmark\s*:', line):
                in_benchmark = True
                continue
            # another top-level directive resets benchmark state
            if in_benchmark and re.match(r'\s+\w[\w\s]*:', line):
                in_benchmark = False
                continue
            if in_benchmark and current_rule:
                stripped = line.strip().strip('"').strip("'")
                if stripped:
                    patterns[current_rule] = stripped
                    in_benchmark = False
    return patterns


def pattern_to_regex(pattern):
    """Convert a Snakemake benchmark path pattern to a compiled regex.

    Strips the leading 'benchmarks/' prefix, then replaces {wildcard}
    tokens with '.*' (allowing slashes, so wildcards that expand to
    paths work correctly).
    """
    rel = re.sub(r'^benchmarks/', '', pattern)
    # split on wildcard tokens and re.escape the literal parts
    parts = re.split(r'\{[^}]+\}', rel)
    rx = '.*'.join(re.escape(p) for p in parts)
    return re.compile('^' + rx + '$')


def match_rule(rel_path, compiled_patterns):
    """Return rule name for rel_path (relative to benchmarks/), or None."""
    for rule, rx in compiled_patterns.items():
        if rx.match(rel_path):
            return rule
    return None


def parse_bench_file(path):
    """Return {col: float} from a benchmark file, or None on error."""
    try:
        with open(path, 'r', encoding='utf8') as fh:
            reader = csv.DictReader(fh, delimiter='\t')
            for row in reader:
                result = {}
                for k, v in row.items():
                    v = v.strip()
                    if v:
                        try:
                            result[k] = float(v)
                        except ValueError:
                            pass
                return result if result else None
    except Exception:
        return None


def fmt(v):
    return f'{v:.3f}'


def main():
    repo_root = os.getcwd()
    bench_dir = Path(repo_root) / BENCHMARKS_DIR
    snakefile = Path(repo_root) / SNAKEFILE

    if not bench_dir.is_dir():
        print(f'benchmarks/ not found at {bench_dir}')
        return 2

    # build rule -> regex from Snakefile
    compiled_patterns = {}
    if snakefile.exists():
        raw = load_rule_patterns(snakefile)
        compiled_patterns = {rule: pattern_to_regex(pat) for rule, pat in raw.items()}

    # collect all .bench files
    bench_files = sorted(bench_dir.rglob('*.bench'))
    if not bench_files:
        print('No .bench files found under', bench_dir)
        return 3

    stats_by_rule = defaultdict(lambda: defaultdict(list))

    for path in bench_files:
        rel = str(path.relative_to(bench_dir))
        rule = match_rule(rel, compiled_patterns) if compiled_patterns else None
        if rule is None:
            # fallback: top-level file → stem; nested → parent dir name
            parts = Path(rel).parts
            rule = Path(parts[0]).stem if len(parts) == 1 else parts[0]

        data = parse_bench_file(path)
        if data is None:
            continue
        for col, val in data.items():
            stats_by_rule[rule][col].append(val)

    if not stats_by_rule:
        print('No benchmark data could be parsed.')
        return 4

    # sort rules by median wall-clock duration descending
    def median_s(rule):
        vals = stats_by_rule[rule].get('s', [])
        return median(vals) if vals else 0.0

    rules = sorted(stats_by_rule.keys(), key=median_s, reverse=True)

    out_dir = Path(repo_root) / 'reports'
    out_dir.mkdir(exist_ok=True)
    out_path = out_dir / 'benchmark_summary.csv'

    fieldnames = ['rule', 'count']
    for col in BENCH_COLS:
        for stat in ('min', 'mean', 'median', 'max'):
            fieldnames.append(f'{col}_{stat}')

    with open(out_path, 'w', newline='', encoding='utf8') as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        for rule in rules:
            d = stats_by_rule[rule]
            row = {'rule': rule, 'count': len(d.get('s', []))}
            for col in BENCH_COLS:
                vals = d.get(col, [])
                if vals:
                    row[f'{col}_min'] = fmt(min(vals))
                    row[f'{col}_mean'] = fmt(mean(vals))
                    row[f'{col}_median'] = fmt(median(vals))
                    row[f'{col}_max'] = fmt(max(vals))
                else:
                    for stat in ('min', 'mean', 'median', 'max'):
                        row[f'{col}_{stat}'] = ''
            writer.writerow(row)

    print(f'Wrote {out_path}')

    # print a concise text summary to stdout
    name_w = max(len(r) for r in rules)
    header = f"{'rule':<{name_w}}  {'n':>4}  {'s_median':>10}  {'s_max':>10}  {'max_rss_median':>14}  {'max_rss_max':>11}"
    print()
    print(header)
    print('-' * len(header))
    for rule in rules:
        d = stats_by_rule[rule]
        n = len(d.get('s', []))
        s_med = fmt(median(d['s'])) if d.get('s') else '-'
        s_max = fmt(max(d['s'])) if d.get('s') else '-'
        rss_med = fmt(median(d['max_rss'])) if d.get('max_rss') else '-'
        rss_max = fmt(max(d['max_rss'])) if d.get('max_rss') else '-'
        print(f'{rule:<{name_w}}  {n:>4}  {s_med:>10}  {s_max:>10}  {rss_med:>14}  {rss_max:>11}')

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
