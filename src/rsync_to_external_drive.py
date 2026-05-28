#!/usr/bin/env python3
"""
Rsync the current run directory to an external drive.

Usage:
    python src/rsync_to_external_drive.py [--dest-dir PATH] [--library NAME] [--dry-run]

Defaults are read from snakemake_config_project.yaml, falling back to
snakemake_config.yaml, then to built-in defaults.
"""

import argparse
import os
import subprocess
import sys
import yaml


def load_config():
    configs = ["snakemake_config_project.yaml", "snakemake_config.yaml"]
    merged = {}
    for path in reversed(configs):
        if os.path.exists(path):
            with open(path) as f:
                merged.update(yaml.safe_load(f) or {})
    return merged


def main():
    cfg = load_config()

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dest-dir", default=cfg.get("external_drive_path"),
                        help="Root destination directory (default: external_drive_path from config)")
    parser.add_argument("--library", default=cfg.get("library_name", ""),
                        help="Library/run name appended to dest-dir (default: library_name from config)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Pass --dry-run to rsync; show what would be transferred without copying")
    args = parser.parse_args()

    src = os.path.abspath(os.getcwd())
    working_dir = src

    if working_dir.startswith("/mnt/"):
        print(f"Working directory {working_dir} is on /mnt/ path. Skipping rsync.")
        sys.exit(0)

    if not args.dest_dir:
        print("No destination directory specified (--dest-dir or external_drive_path in config). Aborting.")
        sys.exit(1)

    dest = os.path.join(args.dest_dir, args.library) if args.library else args.dest_dir
    print(f"Source : {src}/")
    print(f"Dest   : {dest}/")

    os.makedirs(dest, exist_ok=True)

    cmd = [
        "rsync", "-aW", "--delete",
        "--exclude=.snakemake/",
        "--exclude=*Undetermined*",
    ]
    if args.dry_run:
        cmd += ["--dry-run", "--verbose"]
    else:
        cmd.append("--info=progress2")
    cmd += [src + "/", dest + "/"]

    print("Running:", " ".join(cmd))
    result = subprocess.run(cmd, text=True)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
