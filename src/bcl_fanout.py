#!/usr/bin/env python3
"""Fan-out one lane's outputs from the single combined BCL Convert run.

`rule bcl_convert_all` runs DRAGEN once over an all-lane SampleSheet and writes a
single staging directory (`.output/.combined`). This script reconstructs the
per-lane `.output/{config_id}/` tree that the per-lane downstream workflow expects,
so that nothing downstream of `bcl_convert` has to change.

For lane N it:
  1. Hardlinks project FASTQs and Undetermined FASTQs carrying the `_L00N_` token
     into `.output/{config_id}/` (hardlinks share inodes -> no extra disk; they
     behave as real files for the later shutil.move in `bcl_project_done`).
  2. Copies accessory outputs (Reports/, Logs/, dragen*.json), lane-filtering any
     CSV that has a `Lane` column so per-lane stats match the old single-lane run.
  3. Applies the keep/delete-Undetermined policy, then renames FASTQs via
     run_rename.sh exactly as the old per-lane rule did.

Usage:
    bcl_fanout.py CONFIG_ID LANE COMBINED_DIR FINAL_OUT RENAMING_MAP \
        --keep-undetermined-configs "lane1 lane2 ..."
"""
import argparse
import csv
import glob
import os
import shutil
import subprocess
import sys


def lane_filter_csv(src, dst, lane):
    """Copy a CSV, keeping only rows for `lane` when it has a Lane column.

    CSVs without a Lane column (or empty files) are copied unchanged.
    """
    with open(src, newline="") as fin:
        rows = list(csv.reader(fin))
    if not rows:
        shutil.copy2(src, dst)
        return
    header = rows[0]
    if "Lane" in header:
        li = header.index("Lane")
        kept = [r for r in rows[1:] if len(r) > li and r[li].strip() == str(lane)]
        out_rows = [header] + kept
    else:
        out_rows = rows
    with open(dst, "w", newline="") as fout:
        csv.writer(fout).writerows(out_rows)


def link_or_copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst):
        os.remove(dst)
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("config_id")
    ap.add_argument("lane")
    ap.add_argument("combined_dir")
    ap.add_argument("final_out")
    ap.add_argument("renaming_map")
    ap.add_argument("--keep-undetermined-configs", default="")
    args = ap.parse_args()

    config_id = args.config_id
    lane = int(args.lane)
    lane_token = f"_L{lane:03d}_"
    combined = args.combined_dir
    final_out = args.final_out

    if not os.path.isdir(combined):
        sys.exit(f"ERROR: combined staging dir not found: {combined}")

    os.makedirs(final_out, exist_ok=True)
    print(f"Fan-out {config_id}: lane {lane} (token {lane_token}) from {combined} -> {final_out}")

    # Clear any FASTQs from a previous fan-out so re-runs stay clean (mirrors the
    # old rule's `find -delete` of *.fastq.gz before DRAGEN).
    for f in glob.glob(os.path.join(final_out, "**", "*.fastq.gz"), recursive=True):
        os.remove(f)

    # 1. Hardlink this lane's FASTQs (project subdirs + top-level Undetermined).
    n_fastq = 0
    for src in glob.glob(os.path.join(combined, "**", f"*{lane_token}*.fastq.gz"), recursive=True):
        rel = os.path.relpath(src, combined)
        link_or_copy(src, os.path.join(final_out, rel))
        n_fastq += 1
    print(f"  linked {n_fastq} FASTQ files")

    # 2. Copy accessory outputs, lane-filtering CSVs. FASTQs are skipped (already linked).
    for entry in sorted(os.listdir(combined)):
        if entry == ".done":
            continue
        src = os.path.join(combined, entry)
        if os.path.isdir(src):
            for root, _dirs, files in os.walk(src):
                rel_root = os.path.relpath(root, combined)
                os.makedirs(os.path.join(final_out, rel_root), exist_ok=True)
                for fn in files:
                    if fn.endswith(".fastq.gz"):
                        continue
                    s = os.path.join(root, fn)
                    d = os.path.join(final_out, rel_root, fn)
                    if fn.endswith(".csv"):
                        lane_filter_csv(s, d, lane)
                    else:
                        if os.path.exists(d):
                            os.remove(d)
                        shutil.copy2(s, d)
        elif not entry.endswith(".fastq.gz"):
            d = os.path.join(final_out, entry)
            if entry.endswith(".csv"):
                lane_filter_csv(src, d, lane)
            else:
                if os.path.exists(d):
                    os.remove(d)
                shutil.copy2(src, d)

    # 3. Keep/delete Undetermined (same policy as the old per-lane rule).
    keep_configs = args.keep_undetermined_configs.split()
    keep_undetermined = config_id in keep_configs
    if os.path.exists(f"metadata/flexbar_barcodes_{config_id}.txt"):
        print("  inline (flexbar) demux lane detected; preserving Undetermined reads")
        keep_undetermined = True
    if os.path.exists(f"metadata/fqtk_barcodes_{config_id}.tsv"):
        print("  fqtk demux lane detected; preserving Undetermined reads")
        keep_undetermined = True

    if keep_undetermined:
        print(f"  keeping Undetermined reads for {config_id}")
    else:
        removed = 0
        for f in glob.glob(os.path.join(final_out, "Undetermined*")):
            os.remove(f)
            removed += 1
        print(f"  deleted {removed} Undetermined files")

    # 4. Rename FASTQs to lab conventions (lane-specific names; S-number agnostic).
    subprocess.run(["src/run_rename.sh", config_id, final_out, args.renaming_map], check=True)
    print(f"Fan-out complete for {config_id}")


if __name__ == "__main__":
    main()
