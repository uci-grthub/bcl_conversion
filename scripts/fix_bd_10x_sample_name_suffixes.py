#!/usr/bin/env python3
"""
fix_bd_10x_sample_name_suffixes.py

Removes the erroneous _1/_2 numeric suffixes that were incorrectly appended to
BD/10x/Parse sample names by filldown_and_make_unique_sample_names().

For these library types the Illumina lane number in the FASTQ filename
(L001, L002, …) is what CellRanger/BD tools use to distinguish multi-lane
replicates — the sample name must be identical across lanes.

Renames:
  output/lane{N}/{project}/{sample}_1_S{s}_L{lane:03d}_{read}_001.fastq.gz
    → output/lane{N}/{project}/{sample}_S{s}_L{lane:03d}_{read}_001.fastq.gz

  results/fastp/lane{N}/{project}/{sample}_1.json/.html
    → results/fastp/lane{N}/{project}/{sample}.json/.html

  results/renaming_map_lane{N}.csv   — Sample_ID and Sample_Name columns
  output/lane{N}/Reports/SampleSheet.csv — Sample_ID and Sample_Name columns

Run from the project root (xR085/).  Pass --dry-run to preview without
making changes.
"""

import argparse
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


BD_10X_TOKENS = ("10x", "parse", "bd")


def is_bd_or_10x(project: str) -> bool:
    p = (project or "").lower()
    return any(t in p for t in BD_10X_TOKENS)


def strip_suffix(name: str) -> str:
    """Remove a trailing _<digits> suffix added by filldown_and_make_unique."""
    return re.sub(r"_\d+$", "", name)


def rename(src: str, dst: str, dry_run: bool) -> None:
    if src == dst:
        return
    if not os.path.exists(src):
        print(f"  SKIP (not found): {src}")
        return
    if os.path.exists(dst):
        print(f"  SKIP (dest exists): {dst}")
        return
    print(f"  mv {os.path.relpath(src, ROOT)}")
    print(f"     -> {os.path.relpath(dst, ROOT)}")
    if not dry_run:
        os.rename(src, dst)


def fix_renaming_map(map_path: str, dry_run: bool) -> dict:
    """
    Update Sample_ID and Sample_Name in the renaming map CSV.
    Returns {old_name: new_name} for all BD/10x rows.
    """
    mapping = {}
    rows = []
    with open(map_path, newline="") as fh:
        reader = csv.DictReader(fh)
        fieldnames = reader.fieldnames
        for row in reader:
            project = row.get("Sample_Project", "")
            if is_bd_or_10x(project):
                old_id = row.get("Sample_ID", "")
                old_name = row.get("Sample_Name", "")
                new_id = strip_suffix(old_id)
                new_name = strip_suffix(old_name)
                if old_name != new_name:
                    mapping[old_name] = new_name
                    print(f"  map: {old_name!r} -> {new_name!r}")
                row["Sample_ID"] = new_id
                row["Sample_Name"] = new_name
            rows.append(row)

    if not dry_run and mapping:
        with open(map_path, "w", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    return mapping


def fix_samplesheet(ss_path: str, dry_run: bool) -> None:
    """Strip suffixes from Sample_ID and Sample_Name in a BCL Convert SampleSheet."""
    if not os.path.exists(ss_path):
        return

    lines_in = open(ss_path).readlines()
    lines_out = []
    in_data = False
    header_cols = []

    for line in lines_in:
        stripped = line.rstrip("\n")
        if stripped.startswith("[BCLConvert_Data]"):
            in_data = True
            lines_out.append(line)
            continue

        if in_data:
            if stripped.startswith("[") and not stripped.startswith("[BCLConvert"):
                in_data = False
                lines_out.append(line)
                continue

            if not header_cols:
                header_cols = [c.strip() for c in stripped.split(",")]
                lines_out.append(line)
                continue

            cols = stripped.split(",")
            row = dict(zip(header_cols, cols))
            project = row.get("Sample_Project", "")
            if is_bd_or_10x(project):
                for col in ("Sample_ID", "Sample_Name"):
                    if col in row:
                        row[col] = strip_suffix(row[col])
                cols = [row.get(c, cols[i]) for i, c in enumerate(header_cols)]
            lines_out.append(",".join(cols) + "\n")
        else:
            lines_out.append(line)

    if not dry_run:
        with open(ss_path, "w") as fh:
            fh.writelines(lines_out)


def fix_fastq_files(fastq_dir: str, name_map: dict, dry_run: bool) -> None:
    """Rename FASTQ files in fastq_dir using the old->new sample name mapping."""
    if not os.path.isdir(fastq_dir):
        return
    for fname in sorted(os.listdir(fastq_dir)):
        if not fname.endswith(".fastq.gz"):
            continue
        # Match: {sample_name}_S{n}_L{lane}_{read}_001.fastq.gz
        m = re.match(r"^(.+?)_(S\d+_L\d{3}_.+_001\.fastq\.gz)$", fname)
        if not m:
            continue
        old_sample, suffix = m.group(1), m.group(2)
        new_sample = name_map.get(old_sample)
        if new_sample is None:
            continue
        src = os.path.join(fastq_dir, fname)
        dst = os.path.join(fastq_dir, f"{new_sample}_{suffix}")
        rename(src, dst, dry_run)


def fix_fastp_files(fastp_dir: str, name_map: dict, dry_run: bool) -> None:
    """Rename fastp JSON/HTML files using the old->new sample name mapping."""
    if not os.path.isdir(fastp_dir):
        return
    for fname in sorted(os.listdir(fastp_dir)):
        stem, ext = os.path.splitext(fname)
        if ext not in (".json", ".html"):
            continue
        new_stem = name_map.get(stem)
        if new_stem is None:
            continue
        src = os.path.join(fastp_dir, fname)
        dst = os.path.join(fastp_dir, f"{new_stem}{ext}")
        rename(src, dst, dry_run)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="Print what would be done without making changes")
    args = parser.parse_args()

    dry_run = args.dry_run
    if dry_run:
        print("=== DRY RUN — no files will be changed ===\n")

    lanes = sorted(
        d for d in os.listdir(os.path.join(ROOT, "output"))
        if re.match(r"^lane\d+$", d)
    )

    for lane_id in lanes:
        print(f"\n{'='*60}")
        print(f"Lane: {lane_id}")
        print(f"{'='*60}")

        # --- renaming map ---
        map_path = os.path.join(ROOT, "results", f"renaming_map_{lane_id}.csv")
        if not os.path.exists(map_path):
            print(f"  renaming map not found, skipping: {map_path}")
            continue

        print(f"\n[renaming_map_{lane_id}.csv]")
        name_map = fix_renaming_map(map_path, dry_run)

        if not name_map:
            print("  (no BD/10x samples with suffixes found)")
            continue

        # --- output SampleSheet ---
        ss_path = os.path.join(ROOT, "output", lane_id, "Reports", "SampleSheet.csv")
        print(f"\n[SampleSheet]")
        fix_samplesheet(ss_path, dry_run)

        # --- FASTQ files ---
        lane_out = os.path.join(ROOT, "output", lane_id)
        for entry in sorted(os.listdir(lane_out)):
            project_dir = os.path.join(lane_out, entry)
            if not os.path.isdir(project_dir):
                continue
            if entry in ("Reports", "Logs"):
                continue
            print(f"\n[FASTQ] {os.path.relpath(project_dir, ROOT)}/")
            fix_fastq_files(project_dir, name_map, dry_run)

        # --- fastp results ---
        fastp_lane = os.path.join(ROOT, "results", "fastp", lane_id)
        for entry in sorted(os.listdir(fastp_lane)) if os.path.isdir(fastp_lane) else []:
            fastp_project = os.path.join(fastp_lane, entry)
            if not os.path.isdir(fastp_project):
                continue
            print(f"\n[fastp] {os.path.relpath(fastp_project, ROOT)}/")
            fix_fastp_files(fastp_project, name_map, dry_run)

    print("\nDone." if not dry_run else "\nDry run complete. Re-run without --dry-run to apply.")


if __name__ == "__main__":
    main()
