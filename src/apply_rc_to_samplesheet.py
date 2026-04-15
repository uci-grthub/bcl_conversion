#!/usr/bin/env python3
"""Apply per-project index orientation fixes to a BCLConvert SampleSheet.

Supports fix_type values from detect_rc_candidates / check_index_rc_swap:
  i7_rc   — reverse-complement i7 (index) only
  i5_rc   — reverse-complement i5 (index2) only
  both_rc — reverse-complement both indexes

Usage:
  python3 src/apply_rc_to_samplesheet.py \
    --samplesheet results/SampleSheet_lane1.csv \
    --candidates logs/rc_candidates_lane1.json \
    --output results/SampleSheet_lane1_rc.csv
"""
import argparse
import csv
import json
import os
import sys


def rc(seq):
    comp = {'A': 'T', 'T': 'A', 'C': 'G', 'G': 'C', 'N': 'N'}
    return ''.join(comp.get(b.upper(), 'N') for b in reversed(seq))


def _add_per_sample_barcode_mismatches(fieldnames, rows):
    """Add BarcodeMismatchesIndex1/2 columns based on dual vs single index per sample.

    Dual-indexed samples (non-empty index2) get both Index1=1 and Index2=1.
    Single-indexed samples get Index1=1 and Index2 left blank so DRAGEN
    does not try to apply an i5 mismatch setting for samples without i5.
    """
    fn = list(fieldnames)
    if 'BarcodeMismatchesIndex1' not in fn:
        fn.append('BarcodeMismatchesIndex1')
    if 'BarcodeMismatchesIndex2' not in fn:
        fn.append('BarcodeMismatchesIndex2')
    for r in rows:
        if not str(r.get('BarcodeMismatchesIndex1', '')).strip():
            r['BarcodeMismatchesIndex1'] = '1'
        has_i5 = bool(r.get('index2', '').strip())
        if has_i5:
            if not str(r.get('BarcodeMismatchesIndex2', '')).strip():
                r['BarcodeMismatchesIndex2'] = '1'
        else:
            r['BarcodeMismatchesIndex2'] = ''
    return fn


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--samplesheet', required=True)
    parser.add_argument('--candidates', required=True,
                        help='JSON file with list of {project: ...} records from detect_rc_candidates')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    with open(args.candidates) as f:
        candidates = json.load(f)

    # Build per-project fix_type map; if a project appears multiple times (multiple index
    # pairs), pick the fix_type with the highest cumulative rc_hits.
    _fix_votes = {}  # project -> Counter of fix_type -> rc_hits
    for r in candidates:
        proj = r['project']
        ft = r.get('fix_type', 'i7_rc')  # fallback for older JSON without fix_type
        rh = r.get('rc_hits', 1)
        if proj not in _fix_votes:
            _fix_votes[proj] = {}
        _fix_votes[proj][ft] = _fix_votes[proj].get(ft, 0) + rh
    suspect_fix = {proj: max(votes, key=votes.get) for proj, votes in _fix_votes.items()}

    with open(args.samplesheet) as f:
        lines = f.readlines()

    # Find the data header line (starts with 'Lane,')
    header_idx = None
    for i, ln in enumerate(lines):
        if ln.strip().startswith('Lane,'):
            header_idx = i
            break

    os.makedirs(os.path.dirname(args.output) or '.', exist_ok=True)

    if header_idx is None:
        # No data section found: copy as-is
        with open(args.output, 'w') as f:
            f.writelines(lines)
        print("No data section found; copied as-is", file=sys.stderr)
        return 0

    preamble = lines[:header_idx]
    data_lines = lines[header_idx:]
    reader = csv.DictReader(data_lines)
    fieldnames = reader.fieldnames
    rows = []
    rc_count = 0
    for r in reader:
        project = (r.get('Sample_Project') or '').strip()
        fix_type = suspect_fix.get(project)
        if fix_type:
            if fix_type in ('i7_rc', 'both_rc') and r.get('index', '').strip():
                r['index'] = rc(r['index'].strip())
                rc_count += 1
            if fix_type in ('i5_rc', 'both_rc') and r.get('index2', '').strip():
                r['index2'] = rc(r['index2'].strip())
        rows.append(r)

    fieldnames = _add_per_sample_barcode_mismatches(fieldnames, rows)

    with open(args.output, 'w', newline='') as f:
        f.writelines(preamble)
        writer = csv.DictWriter(f, fieldnames=fieldnames, lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)

    if suspect_fix:
        applied = {proj: ft for proj, ft in suspect_fix.items()}
        print(f"Applied RC fixes to {rc_count} samples: {applied}", file=sys.stderr)
    else:
        print("No RC changes applied; added per-sample BarcodeMismatches columns", file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
