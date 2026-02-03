#!/usr/bin/env python3
import re
import json
import os
import csv
from datetime import datetime
from statistics import mean, median
import math


def extract_timeline_obj(text: str):
    m = re.search(r"var\s+timeline_spec\s*=\s*(\{.*?\});", text, re.DOTALL)
    if not m:
        raise RuntimeError("Could not find timeline_spec in report.html")
    return m.group(1)


def parse_iso(s):
    if s is None:
        return None
    try:
        # Python's fromisoformat handles the format seen in Snakemake reports
        return datetime.fromisoformat(s)
    except Exception:
        # fallback: try removing Z or other tokens
        try:
            return datetime.fromisoformat(s.replace('Z', ''))
        except Exception:
            return None


def main():
    repo_root = os.getcwd()
    report_path = os.path.join(repo_root, 'report.html')
    if not os.path.exists(report_path):
        print(f"report.html not found at {report_path}")
        return 2

    text = open(report_path, 'r', encoding='utf8').read()
    obj_text = extract_timeline_obj(text)

    try:
        timeline = json.loads(obj_text)
    except json.JSONDecodeError as e:
        print('Failed to decode JSON from timeline_spec:', e)
        return 3

    values = timeline.get('data', {}).get('values', [])

    os.makedirs('reports', exist_ok=True)
    entries_csv = os.path.join('reports', 'timeline_entries.csv')
    agg_csv = os.path.join('reports', 'timings_per_rule.csv')

    rows = []
    durations_by_rule = {}

    for v in values:
        rule = v.get('rule')
        start_s = v.get('starttime')
        end_s = v.get('endtime')
        start_dt = parse_iso(start_s)
        end_dt = parse_iso(end_s)
        duration = None
        if start_dt is not None and end_dt is not None:
            try:
                duration = (end_dt - start_dt).total_seconds()
            except Exception:
                duration = None

        rows.append({'rule': rule, 'starttime': start_s, 'endtime': end_s, 'duration_seconds': '' if duration is None else f"{duration:.6f}"})

        if duration is not None and math.isfinite(duration):
            durations_by_rule.setdefault(rule, []).append(duration)

    # write raw entries
    with open(entries_csv, 'w', newline='', encoding='utf8') as fh:
        writer = csv.DictWriter(fh, fieldnames=['rule', 'starttime', 'endtime', 'duration_seconds'])
        writer.writeheader()
        for r in rows:
            writer.writerow(r)

    # aggregate
    agg_rows = []
    for rule, durs in sorted(durations_by_rule.items()):
        cnt = len(durs)
        total = sum(durs)
        mn = min(durs)
        mx = max(durs)
        avg = mean(durs) if cnt else ''
        med = median(durs) if cnt else ''
        agg_rows.append({'rule': rule, 'count': cnt, 'total_seconds': f"{total:.6f}", 'mean_seconds': f"{avg:.6f}" if avg != '' else '', 'median_seconds': f"{med:.6f}" if med != '' else '', 'min_seconds': f"{mn:.6f}", 'max_seconds': f"{mx:.6f}"})

    with open(agg_csv, 'w', newline='', encoding='utf8') as fh:
        writer = csv.DictWriter(fh, fieldnames=['rule', 'count', 'total_seconds', 'mean_seconds', 'median_seconds', 'min_seconds', 'max_seconds'])
        writer.writeheader()
        for r in agg_rows:
            writer.writerow(r)

    print('Wrote', entries_csv)
    print('Wrote', agg_csv)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
