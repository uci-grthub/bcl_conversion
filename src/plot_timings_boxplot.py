#!/usr/bin/env python3
import csv
import os
from collections import defaultdict
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def read_entries(path):
    durations = defaultdict(list)
    with open(path, newline='', encoding='utf8') as fh:
        reader = csv.DictReader(fh)
        for r in reader:
            rule = r.get('rule')
            ds = r.get('duration_seconds', '').strip()
            if ds == '':
                continue
            try:
                d = float(ds)
            except Exception:
                continue
            durations[rule].append(d)
    return durations


def main():
    repo_root = os.getcwd()
    entries_csv = os.path.join(repo_root, 'reports', 'benchmark_entries.csv')
    if not os.path.exists(entries_csv):
        print('benchmark_entries.csv not found; run parse_timeline.py first')
        return 2

    durations = read_entries(entries_csv)
    if not durations:
        print('No durations found in', entries_csv)
        return 3

    # convert to minutes and exclude outliers per rule (1.5 * IQR)
    import statistics
    def filter_outliers_minutes(vals_seconds):
        # convert to minutes
        vals = [v / 60.0 for v in vals_seconds]
        if len(vals) < 4:
            return vals
        qs = statistics.quantiles(vals, n=4)
        q1 = qs[0]
        q3 = qs[2]
        iqr = q3 - q1
        if iqr == 0:
            return vals
        lower = q1 - 1.5 * iqr
        upper = q3 + 1.5 * iqr
        return [v for v in vals if lower <= v <= upper]

    rules_stats = []
    for rule, vals in durations.items():
        filtered = filter_outliers_minutes(vals)
        med = statistics.median(filtered) if filtered else 0.0
        rules_stats.append((rule, med, filtered))

    # sort rules by median duration (descending)
    rules_stats.sort(key=lambda x: x[1], reverse=True)

    labels = [r[0] for r in rules_stats]
    data = [r[2] for r in rules_stats]

    # plot (minutes)
    fig_w = max(8, 0.4 * len(labels))
    fig_h = 8
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))
    b = ax.boxplot(data, vert=False, patch_artist=True, labels=labels, showfliers=False)

    # style
    for patch in b['boxes']:
        patch.set_facecolor('#007bff')
        patch.set_alpha(0.6)

    # overlay individual points with jitter
    import numpy as np
    rng = np.random.default_rng(42)
    for i, vals in enumerate(data, start=1):
        jitter = rng.uniform(-0.2, 0.2, size=len(vals))
        ax.scatter(vals, [i + j for j in jitter], color='black', alpha=0.4, s=12, zorder=3)

    ax.set_xlabel('Duration (minutes)')
    ax.set_title('Rule timings (per-job, outliers removed)')
    plt.tight_layout()

    out_dir = os.path.join(repo_root, 'reports')
    os.makedirs(out_dir, exist_ok=True)
    png = os.path.join(out_dir, 'timings_boxplot.png')
    svg = os.path.join(out_dir, 'timings_boxplot.svg')
    fig.savefig(png, dpi=150)
    fig.savefig(svg)
    print('Wrote', png)
    print('Wrote', svg)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
