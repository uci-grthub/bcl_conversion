#!/usr/bin/env python3
import csv
import os
from collections import defaultdict
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def read_entries(path):
    durations = defaultdict(list)
    labels_map = defaultdict(list)
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
            bf = r.get('benchmark_file', '')
            # strip path and extension for a short label
            lbl = os.path.splitext(os.path.basename(bf))[0]
            labels_map[rule].append(lbl)
    return durations, labels_map


def main():
    repo_root = os.getcwd()
    entries_csv = os.path.join(repo_root, 'reports', 'benchmark_entries.csv')
    if not os.path.exists(entries_csv):
        print('benchmark_entries.csv not found; run parse_timeline.py first')
        return 2

    durations, labels_map = read_entries(entries_csv)
    if not durations:
        print('No durations found in', entries_csv)
        return 3

    import statistics

    rules_stats = []
    for rule, vals in durations.items():
        raw_lbls = labels_map[rule]
        # filter outliers and keep matching labels
        if len(vals) >= 4:
            mins = [v / 60.0 for v in vals]
            qs = statistics.quantiles(mins, n=4)
            q1, q3 = qs[0], qs[2]
            iqr = q3 - q1
            if iqr > 0:
                lower, upper = q1 - 1.5 * iqr, q3 + 1.5 * iqr
                pairs = [(v, l) for v, l in zip(mins, raw_lbls) if lower <= v <= upper]
            else:
                pairs = list(zip([v / 60.0 for v in vals], raw_lbls))
        else:
            pairs = list(zip([v / 60.0 for v in vals], raw_lbls))
        filtered = [p[0] for p in pairs]
        pt_labels = [p[1] for p in pairs]
        med = statistics.median(filtered) if filtered else 0.0
        rules_stats.append((rule, med, filtered, pt_labels))

    # sort rules by median duration (descending)
    rules_stats.sort(key=lambda x: x[1], reverse=True)

    labels = [r[0] for r in rules_stats]
    data = [r[2] for r in rules_stats]
    point_labels = [r[3] for r in rules_stats]

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
    for i, (vals, pt_lbls, rule) in enumerate(zip(data, point_labels, labels), start=1):
        jitter = rng.uniform(-0.2, 0.2, size=len(vals))
        y_pos = [i + j for j in jitter]
        ax.scatter(vals, y_pos, color='black', alpha=0.4, s=12, zorder=3)

        # annotate the 4 highest points for bcl_convert
        if rule == 'bcl_convert' and vals:
            indexed = sorted(enumerate(vals), key=lambda x: x[1], reverse=True)[:4]
            for idx, v in indexed:
                ax.annotate(
                    pt_lbls[idx],
                    xy=(v, y_pos[idx]),
                    xytext=(4, 4),
                    textcoords='offset points',
                    fontsize=6,
                    va='bottom',
                    rotation=45,
                )

    ax.set_yticklabels(labels, rotation=45, ha='right')
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
