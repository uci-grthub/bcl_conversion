#!/usr/bin/env python3
"""Backfill delivered FASTQ names for a run that was demultiplexed on a
reverse-complemented barcode.

Where an RC orientation won, DRAGEN demultiplexed against the reverse complement
of the submitted index but the pipeline named the delivered files from the
workbook barcode, so the filename advertises a sequence that is not the one in
the index reads. Clients match our FASTQs against their own barcode list, so the
name has to carry the sequence actually observed.

The workflow does this for new runs (see generate_effective_renaming_map and the
re-stem in normalize_project_fastq_names). This script repairs runs that already
shipped.

Renames are matched on the barcode-free prefix {run}-L{lane}-G{group}-{position},
never on the barcode, so a sample can only ever be renamed onto itself.

Dry-run by default; pass --apply to make changes.

    # what would change for lane5
    python3 scripts/backfill_rc_barcode_names.py --config-id lane5

    # a run predating orientation_decision_*.json
    python3 scripts/backfill_rc_barcode_names.py --config-id lane5 \
        --project ThomL_WGS_Pool2 --force-orientation rc_i5 --apply

After applying: re-run verify_project_links, then re-sync the external mirror
AND delete the stale old-named copies there (scripts/sync_run.sh +
scripts/verify_mirror.py). A plain rsync leaves both names present.
"""
import argparse
import datetime
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

import pandas as pd  # noqa: E402

from rename_pipeline_outputs import _row_parts, restem_by_position  # noqa: E402

# Same mapping the workflow uses, kept local so this script can run standalone.
RC_ORIENTATION_COLUMNS = {
    'rc_i7': ('index',),
    'rc_i5': ('index2',),
    'rc_both': ('index', 'index2'),
}


def revcomp(seq):
    return str(seq).translate(str.maketrans('ATGCNatgcn', 'TACGNtacgn'))[::-1]


def load_decision(run_root, config_id, force_orientation, projects):
    """Orientation per project: the recorded decision, or a forced override."""
    if force_orientation:
        if not projects:
            sys.exit("--force-orientation requires at least one --project")
        return {p: force_orientation for p in projects}

    path = os.path.join(run_root, "logs", config_id,
                        f"orientation_decision_{config_id}.json")
    if not os.path.exists(path):
        sys.exit(f"No orientation decision at {path}. "
                 f"Use --project NAME --force-orientation rc_i5 for older runs.")
    with open(path) as f:
        decision = json.load(f)
    decision = {p: o for p, o in decision.items() if str(o).startswith("rc")}
    if projects:
        decision = {p: o for p, o in decision.items() if p in projects}
    return decision


def build_effective_rows(map_df, project, orientation):
    """Rows for `project` carrying the delivered barcodes."""
    rows = map_df[map_df["Sample_Project"].astype(str).str.strip() == project].copy()
    for column in RC_ORIENTATION_COLUMNS.get(orientation, ()):
        values = rows[column].astype(str).str.strip()
        flip = (values != "") & (values.str.lower() != "nan")
        rows.loc[flip, column] = values[flip].map(revcomp)
    return rows


def rewrite_lines(path, replacements, apply_changes):
    """Swap old stems for new ones in a text artifact. Returns lines changed."""
    if not os.path.exists(path):
        return 0
    with open(path) as f:
        content = f.read()
    updated = content
    for old, new in replacements.items():
        updated = updated.replace(old, new)
    if updated == content:
        return 0
    changed = sum(1 for a, b in zip(content.splitlines(), updated.splitlines()) if a != b)
    if apply_changes:
        with open(path, "w") as f:
            f.write(updated)
    return changed or 1


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--run-root", default=".", help="Run directory (default: cwd)")
    parser.add_argument("--config-id", required=True, help="e.g. lane5")
    parser.add_argument("--project", action="append", default=[],
                        help="Original Sample_Project name; repeatable. Default: every RC project.")
    parser.add_argument("--order-id", action="append", default=[],
                        help="Limit report/md5 rewrites to these orders. Default: all under Reports/.")
    parser.add_argument("--force-orientation", choices=sorted(RC_ORIENTATION_COLUMNS),
                        help="Assume this orientation instead of reading the decision file.")
    parser.add_argument("--apply", action="store_true",
                        help="Make the changes. Without it, nothing is written.")
    args = parser.parse_args()

    run_root = os.path.abspath(args.run_root)
    config_id = args.config_id
    apply_changes = args.apply

    map_path = os.path.join(run_root, "results", config_id,
                            f"renaming_map_{config_id}.csv")
    if not os.path.exists(map_path):
        sys.exit(f"Renaming map not found: {map_path}")
    map_df = pd.read_csv(map_path, dtype=str, keep_default_na=False)

    decision = load_decision(run_root, config_id, args.force_orientation, args.project)
    if not decision:
        print(f"No project in {config_id} was delivered on a reverse-complemented "
              f"barcode. Nothing to do.")
        return 0

    # Original project name -> delivered directory name, read off disk so this
    # does not depend on the Snakefile's in-memory rename maps.
    output_root = os.path.join(run_root, "output", config_id)
    results_root = os.path.join(run_root, "results", config_id)

    audit = {
        "taken": datetime.datetime.now().isoformat(timespec="seconds"),
        "run_root": run_root,
        "config_id": config_id,
        "applied": apply_changes,
        "decision": decision,
        "projects": [],
    }
    total_renames = 0

    for project, orientation in sorted(decision.items()):
        rows = build_effective_rows(map_df, project, orientation)
        if rows.empty:
            print(f"WARNING: {project} has no rows in {map_path}; skipping")
            continue

        # Old -> new stem, for rewriting the text artifacts.
        replacements = {}
        for _, row in rows.iterrows():
            new_prefix, new_barcode, _l, _p, _s = _row_parts(row)
            old_row = map_df.loc[row.name]
            _op, old_barcode, _l2, _p2, _s2 = _row_parts(old_row)
            if old_barcode != new_barcode:
                replacements[f"{new_prefix}-{old_barcode}"] = f"{new_prefix}-{new_barcode}"

        record = {"project": project, "orientation": orientation,
                  "n_samples": len(rows), "renames": [], "text_edits": {}}

        # Directories that may hold this project's artifacts. The delivered
        # directory name is {lab_id}_{order_id}_{library}_L{lane}_G{group}, which
        # shares no token with the Sample_Project name — so do not try to guess it.
        # Scan the lane's directories and let the per-sample prefix match decide;
        # a directory holding none of these samples is left untouched.
        candidate_dirs = []
        for base in (output_root, results_root):
            if not os.path.isdir(base):
                continue
            candidate_dirs.append(base)
            for entry in sorted(glob.glob(os.path.join(base, "*"))):
                if os.path.isdir(entry):
                    candidate_dirs.append(entry)
                    plots = os.path.join(entry, "plots")
                    if os.path.isdir(plots):
                        candidate_dirs.append(plots)

        touched_dirs = []
        for directory in candidate_dirs:
            renamed = restem_by_position(directory, rows.to_dict("records"),
                                         dry_run=not apply_changes)
            if renamed:
                touched_dirs.append(directory)
            for src, dst in renamed:
                record["renames"].append(
                    {"old": os.path.relpath(src, run_root),
                     "new": os.path.relpath(dst, run_root)})
            total_renames += len(renamed)

        # Text artifacts: md5 manifests (checksums are unchanged, only the
        # filename column), the per-order report, and the read-count CSV.
        targets = [os.path.join(d, "md5sums.txt")
                   for d in dict.fromkeys(candidate_dirs + touched_dirs)]
        order_dirs = ([os.path.join(run_root, "Reports", f"order_{o}") for o in args.order_id]
                      or sorted(glob.glob(os.path.join(run_root, "Reports", "order_*"))))
        for order_dir in order_dirs:
            targets.append(os.path.join(order_dir, "md5sums.txt"))
            targets.append(os.path.join(order_dir, "index.html"))
        targets.extend(glob.glob(os.path.join(run_root, "results", "*-count.csv")))

        for target in targets:
            changed = rewrite_lines(target, replacements, apply_changes)
            if changed:
                record["text_edits"][os.path.relpath(target, run_root)] = changed

        audit["projects"].append(record)

        verb = "Renamed" if apply_changes else "Would rename"
        print(f"\n{project} ({orientation}, {len(rows)} samples)")
        print(f"  {verb} {len(record['renames'])} files")
        for old, new in sorted(replacements.items())[:3]:
            print(f"    {old}-R1.fastq.gz -> {new}-R1.fastq.gz")
        if len(replacements) > 3:
            print(f"    ... and {len(replacements) - 3} more samples")
        for target, changed in sorted(record["text_edits"].items()):
            print(f"  {verb.lower()} {changed} line(s) in {target}")

    log_dir = os.path.join(run_root, "logs")
    os.makedirs(log_dir, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    suffix = "" if apply_changes else "_dryrun"
    log_path = os.path.join(log_dir, f"backfill_rc_names_{config_id}_{stamp}{suffix}.json")
    with open(log_path, "w") as f:
        json.dump(audit, f, indent=2)

    print(f"\n{'Applied' if apply_changes else 'Planned'} {total_renames} rename(s).")
    print(f"Audit log: {os.path.relpath(log_path, run_root)}")
    if not apply_changes:
        print("Dry run — nothing was written. Re-run with --apply.")
    else:
        print("Now re-run verify_project_links, then re-sync the mirror and delete "
              "the stale old-named copies there.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
