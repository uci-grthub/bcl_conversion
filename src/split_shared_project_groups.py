#!/usr/bin/env python3
"""
Split samples from a shared-project-name BCL Convert output folder into per-group
output folders so each order gets its own Nextcloud link and report.

For each lane, finds project names that appear in multiple groups (different orders
submitted under the same Sample_Project name).  For each such project:
  - The existing output folder keeps the samples that belong to the LAST group
    (the one whose name was used for the folder, e.g. DaiX_0326I-48_xR087_L4_G4).
  - New folders are created for the earlier groups by moving the relevant
    sample files out of the shared folder.
  - .project_done and .fastq_names_done sentinels are created so Snakemake's
    downstream rules (calculate_md5sums, project_link, report_order_id) can run.

Usage:
    pixi run python3 src/split_shared_project_groups.py \\
        --metadata metadata/260401_23N3TKLT4_25B_PE151_xR087.xlsx \\
        --library xR087 \\
        [--dry-run]
"""
import argparse
import os
import re
import sys
import pandas as pd
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--metadata", required=True)
    p.add_argument("--library", required=True)
    p.add_argument("--output-base", default="output")
    p.add_argument("--renaming-maps", default="results")
    p.add_argument("--dry-run", action="store_true")
    return p.parse_args()


def main():
    args = parse_args()

    # --- read Summary sheet ---
    df_summary = pd.read_excel(args.metadata, sheet_name="Summary", header=2)
    df_summary = df_summary.dropna(subset=["Lane", "Gr"])
    df_summary["Lane"] = df_summary["Lane"].apply(lambda x: int(float(x)))
    df_summary["Gr"] = df_summary["Gr"].apply(lambda x: int(float(x)))

    # Find project names that appear in >1 group on the same lane
    counts = df_summary.groupby(["Lane", "Project Name"]).size()
    multi_group = counts[counts > 1].reset_index()[["Lane", "Project Name"]]

    if multi_group.empty:
        print("No shared-project-name groups found.")
        return

    for _, row in multi_group.iterrows():
        lane = row["Lane"]
        project_name = row["Project Name"]
        config_id = f"lane{lane}"
        map_path = os.path.join(args.renaming_maps, f"renaming_map_{config_id}.csv")
        if not os.path.exists(map_path):
            print(f"SKIP: renaming map not found: {map_path}")
            continue

        df_map = pd.read_csv(map_path)
        proj_rows = df_map[df_map["Sample_Project"].astype(str).str.strip() == project_name]

        # Groups present in this project on this lane
        groups = sorted(proj_rows["Group"].dropna().apply(lambda x: int(float(x))).unique())
        if len(groups) <= 1:
            continue

        print(f"\nLane {lane}: '{project_name}' spans groups {groups}")

        # Collect metadata rows for each group
        for g in groups:
            g_rows = proj_rows[proj_rows["Group"].apply(lambda x: int(float(x))) == g]
            summary_row = df_summary[(df_summary["Lane"] == lane) & (df_summary["Gr"] == g)].iloc[0]
            lab_id = str(summary_row["Lab ID"]).strip().replace(" ", "-").replace("_", "-")
            order_id = str(summary_row["Order ID"]).strip().replace(" ", "-").replace("_", "-").replace("i", "I")
            folder_name = f"{lab_id}_{order_id}_{args.library}_L{lane}_G{g}"
            dest_dir = Path(args.output_base) / config_id / folder_name

            # Find the source folder (the shared folder that already exists)
            # It will be named after one of the groups — find whichever one exists.
            src_dir = None
            for g2 in groups:
                summary_row2 = df_summary[(df_summary["Lane"] == lane) & (df_summary["Gr"] == g2)].iloc[0]
                lab2 = str(summary_row2["Lab ID"]).strip().replace(" ", "-").replace("_", "-")
                oid2 = str(summary_row2["Order ID"]).strip().replace(" ", "-").replace("_", "-").replace("i", "I")
                candidate = Path(args.output_base) / config_id / f"{lab2}_{oid2}_{args.library}_L{lane}_G{g2}"
                if candidate.exists():
                    src_dir = candidate
                    break

            if src_dir is None:
                print(f"  SKIP group {g}: no source folder found for '{project_name}' on lane {lane}")
                continue

            if dest_dir.exists():
                print(f"  SKIP group {g}: {dest_dir} already exists")
                continue

            sample_names = [str(r.get("Sample_Name", "")).strip() for _, r in g_rows.iterrows()
                            if str(r.get("Sample_Name", "")).strip().lower() not in ("", "nan")]
            print(f"  Group {g} → {dest_dir}")
            print(f"    Samples: {sample_names}")
            print(f"    Source:  {src_dir}")

            if args.dry_run:
                continue

            dest_dir.mkdir(parents=True, exist_ok=True)

            moved = 0
            for fname in list(src_dir.iterdir()):
                if not fname.name.endswith(".fastq.gz"):
                    continue
                # Match by sample name prefix
                for sname in sample_names:
                    if fname.name.startswith(sname + "_"):
                        dest_file = dest_dir / fname.name
                        if not dest_file.exists():
                            fname.rename(dest_file)
                            moved += 1
                        break

            print(f"    Moved {moved} fastq.gz file(s)")

            # Create sentinels so Snakemake sees the folder as ready
            for sentinel in [".project_done", ".fastq_names_done"]:
                (dest_dir / sentinel).touch()
            print(f"    Created sentinels (.project_done, .fastq_names_done)")

    print("\nDone. Run snakemake to generate md5sums, Nextcloud links, and reports.")


if __name__ == "__main__":
    main()
