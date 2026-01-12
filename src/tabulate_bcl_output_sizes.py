#!/usr/bin/env python3
"""Summarize disk usage of bcl_convert output directories aggregated by project.

By default scans the top-level "output" directory for per-config outputs
created by the Snakemake bcl_convert rule (directories containing a .done file).
For each project subdirectory inside those config outputs, it totals the size
and prints a tab-separated table with columns: Project, Size_Bytes, Size_Human.
"""

import argparse
import os
import sys
from typing import Dict, Iterable, Tuple

def human_readable_size(num_bytes: int) -> str:
    """Convert bytes to a human-friendly string (decimal units)."""
    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    size = float(num_bytes)
    for unit in units:
        if size < 1000 or unit == units[-1]:
            return f"{size:,.1f} {unit}"
        size /= 1000
    return f"{num_bytes} B"

def dir_size_bytes(path: str) -> int:
    """Recursively sum file sizes under a directory, excluding Undetermined*.fastq.gz files."""
    total = 0
    for root, _, files in os.walk(path):
        for fname in files:
            # Skip Undetermined FASTQ files
            if fname.startswith("Undetermined") and fname.endswith(".fastq.gz"):
                continue
            fpath = os.path.join(root, fname)
            try:
                total += os.path.getsize(fpath)
            except OSError:
                # Skip unreadable files but continue
                continue
    return total

def find_bcl_output_dirs(base_dir: str) -> Iterable[Tuple[str, str]]:
    """Yield (config_id, path) for bcl_convert outputs under base_dir.

    A directory qualifies if it contains a ".done" sentinel file produced by
    the bcl_convert rule.
    """
    if not os.path.isdir(base_dir):
        return []
    results = []
    for entry in sorted(os.listdir(base_dir)):
        path = os.path.join(base_dir, entry)
        if not os.path.isdir(path):
            continue
        done_file = os.path.join(path, ".done")
        if os.path.exists(done_file):
            results.append((entry, path))
    return results

def main(argv: Iterable[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "base_dir",
        nargs="?",
        default="output",
        help="Base directory containing bcl_convert outputs (default: output)",
    )
    args = parser.parse_args(list(argv))

    outputs = list(find_bcl_output_dirs(args.base_dir))
    if not outputs:
        print(f"No bcl_convert output directories with .done found under {args.base_dir}", file=sys.stderr)
        return 1

    project_sizes: Dict[str, int] = {}

    for _, config_path in outputs:
        for entry in os.listdir(config_path):
            project_path = os.path.join(config_path, entry)
            if not os.path.isdir(project_path):
                continue
            size_bytes = dir_size_bytes(project_path)
            project_sizes[entry] = project_sizes.get(entry, 0) + size_bytes

    if not project_sizes:
        print("No project subdirectories found under bcl_convert outputs", file=sys.stderr)
        return 1

    print("Project\tSize_Bytes\tSize_Human")
    for project in sorted(project_sizes):
        size_bytes = project_sizes[project]
        print(f"{project}\t{size_bytes}\t{human_readable_size(size_bytes)}")

    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
