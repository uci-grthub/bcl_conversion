#!/usr/bin/env python3
"""Check for index reverse-complement / swap issues by comparing
undetermined index sequences to expected sample-sheet indexes.

Usage:
  python3 scripts/check_index_rc_swap.py
    --samples results/SampleSheet_*.csv
    --undetermined results/undetermined_indices/*.csv

The script prints a summary of observed undetermined index sequences and
which expected sample-sheet index pairs they best match (exact, rc, swapped, etc.).
"""
import argparse
import csv
import glob
import os
import sys
from collections import defaultdict, Counter


def rc(seq):
    comp = {'A':'T','T':'A','C':'G','G':'C','N':'N'}
    return ''.join(comp.get(b.upper(), 'N') for b in reversed(seq))


def parse_bclconvert_samplesheet(path):
    """Parse a BCLConvert-style SampleSheet in attachments.
    It contains sections and a header line for the data like:
    Lane,Sample_ID,Sample_Name,index,index2,Sample_Project,OverrideCycles
    """
    if not os.path.exists(path):
        return []
    rows = []
    with open(path, 'r') as fh:
        lines = fh.readlines()

    # find the header line index
    header_idx = None
    for i, ln in enumerate(lines):
        if ln.strip().startswith('Lane,'):
            header_idx = i
            break
    if header_idx is None:
        return []

    reader = csv.DictReader(lines[header_idx:])
    for r in reader:
        # Normalize indexes
        idx1 = (r.get('index') or '').strip()
        idx2 = (r.get('index2') or '').strip()
        project = (r.get('Sample_Project') or '').strip()
        sample = (r.get('Sample_Name') or r.get('Sample_ID') or '').strip()
        if not idx1 and not idx2:
            continue
        if idx2:
            pair = f"{idx1}+{idx2}"
        else:
            pair = idx1
        rows.append({'sample': sample, 'project': project, 'pair': pair, 'idx1': idx1, 'idx2': idx2})
    return rows


def parse_undetermined(path):
    # Undetermined files have a short preamble line, then a header like:
    # Count,Type,Index Sequence
    obs = []
    with open(path, 'r') as fh:
        lines = [l for l in fh]

    # find the header line index (line that starts with 'Count,' or contains 'Index Sequence')
    header_idx = None
    for i, ln in enumerate(lines):
        if 'Count' in ln and 'Index' in ln:
            header_idx = i
            break
    if header_idx is None:
        return obs

    reader = csv.DictReader(lines[header_idx:])
    for r in reader:
        try:
            count = int(r.get('Count', 0))
        except Exception:
            count = 0
        seq = r.get('Index Sequence') or r.get('Index Sequence'.strip())
        if seq is None:
            continue
        obs.append({'count': count, 'seq': seq.strip()})
    return obs


def classify_observed(obs_seq, expected_set):
    """Return list of match types and matched expected pairs for obs_seq."""
    results = []
    # observed may be like AAA+BBB or single AAA
    parts = obs_seq.split('+')
    # compare against every expected pair
    for exp in expected_set:
        exp_parts = exp.split('+')
        # exact
        if parts == exp_parts:
            results.append(('exact', exp))
            continue
        # rc on first
        if len(parts) == len(exp_parts):
            match = True
            for i, p in enumerate(parts):
                if p == exp_parts[i]:
                    continue
                # check rc
                if p == rc(exp_parts[i]):
                    match = True
                else:
                    match = False
                    break
            if match:
                # Determine which positions are rc
                rc_flags = [p != exp_parts[i] for i, p in enumerate(parts)]
                results.append((f"rc_flags={rc_flags}", exp))
                continue
        # swapped order
        if len(parts) == 2 and len(exp_parts) == 2:
            if parts == [exp_parts[1], exp_parts[0]]:
                results.append(('swapped', exp))
                continue
            # swapped with rc possibilities
            if parts == [rc(exp_parts[1]), rc(exp_parts[0])]:
                results.append(('swapped_rc_both', exp))
                continue
            if parts == [rc(exp_parts[1]), exp_parts[0]]:
                results.append(('swapped_rc_first', exp))
                continue
            if parts == [exp_parts[1], rc(exp_parts[0])]:
                results.append(('swapped_rc_second', exp))
                continue
    return results


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument('--samples', nargs='+', default=glob.glob('results/SampleSheet_*.csv'))
    parser.add_argument('--undetermined', nargs='+', default=glob.glob('results/undetermined_indices/*.csv'))
    args = parser.parse_args(argv)

    expected = []
    for p in args.samples:
        expected.extend(parse_bclconvert_samplesheet(p))

    expected_pairs = set(e['pair'] for e in expected)
    expected_map = {e['pair']: e for e in expected}

    if not expected_pairs:
        print('No expected index pairs parsed from sample sheets.', file=sys.stderr)
        return 1

    # Read undetermined files
    obs_all = []
    for u in args.undetermined:
        if not os.path.exists(u):
            continue
        obs = parse_undetermined(u)
        obs_all.append((u, obs))

    # classify
    summary = []
    agg = Counter()
    mapping = defaultdict(list)
    for u, obs in obs_all:
        for o in obs:
            seq = o['seq']
            cnt = o['count']
            matches = classify_observed(seq, expected_pairs)
            if matches:
                for mtype, exp in matches:
                    mapping[exp].append((seq, cnt, mtype, u))
            else:
                # also check if obs equals rc of any single expected component
                # we already check rc_flags in classify_observed, so here mark as unknown
                mapping['<unknown>'].append((seq, cnt, 'no_match', u))
            agg[seq] += cnt

    # Print top observed undetermined sequences and candidate matches
    print('\nObserved undetermined index sequences (top 30):')
    for seq, cnt in agg.most_common(30):
        print(f"{cnt:9d}  {seq}")

    print('\nCandidate mappings to expected index pairs (showing totals per expected pair):')
    for exp, hits in sorted(mapping.items(), key=lambda kv: sum(h[1] for h in kv[1]), reverse=True):
        total = sum(h[1] for h in hits)
        print(f"\n{total:9d}  EXPECTED: {exp}")
        for seq, cnt, mtype, src in sorted(hits, key=lambda x: -x[1])[:10]:
            print(f"   {cnt:9d}  {seq:20s}  match={mtype}  src={os.path.basename(src)}")

    # Heuristic: identify expected pairs where most of the matching undetermined counts
    # come from sequences that are reverse-complements of one or both indexes.
    suspect = []
    for exp, hits in mapping.items():
        if exp == '<unknown>':
            continue
        total = sum(h[1] for h in hits)
        rc_votes = sum(h[1] for h in hits if 'rc' in h[2])
        if total and rc_votes / total > 0.5:
            suspect.append((exp, total, rc_votes))

    if suspect:
        print('\nSuspect expected index pairs likely affected by reverse-complement swap:')
        for exp, total, rc_votes in sorted(suspect, key=lambda x: -x[2]):
            print(f"  {exp}: {rc_votes}/{total} undetermined reads map to rc matches")
    else:
        print('\nNo strong reverse-complement suspects found by simple heuristic.')

    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
