#!/usr/bin/env python3
"""
Compatibility wrapper for metadata validation.

This script now delegates to the shared validator used by run_validation.py
so both entry points stay in sync.

Usage:
    python3 debug/validate_metadata.py [metadata_file.xlsx]
    python3 debug/validate_metadata.py --config snakemake_config_project.yaml
"""

import argparse
import os
import sys

import yaml


def _resolve_repo_root() -> str:
    """Return repository root (parent of this debug directory)."""
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _load_metadata_from_config(config_path: str) -> str:
    """Read metadata path from YAML config."""
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Config file not found: {config_path}")

    with open(config_path, "r", encoding="utf-8") as handle:
        config = yaml.safe_load(handle) or {}

    metadata_path = config.get("metadata")
    if not metadata_path:
        raise ValueError(f"No 'metadata' key found in {config_path}")

    return metadata_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate metadata Excel file")
    parser.add_argument(
        "metadata_file",
        nargs="?",
        help="Path to metadata Excel file (optional if using config)",
    )
    parser.add_argument(
        "--config",
        default="snakemake_config.yaml",
        help="Config YAML file to read metadata path from",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Optional output report path (.xlsx). Defaults to metadata/metadata_validation_<input>.xlsx",
    )
    args = parser.parse_args()

    repo_root = _resolve_repo_root()
    os.chdir(repo_root)

    # Import shared validator from src after moving into repo root.
    src_dir = os.path.join(repo_root, "src")
    if src_dir not in sys.path:
        sys.path.insert(0, src_dir)

    from metadata_validation import validate_metadata_and_write_report

    metadata_file = args.metadata_file
    if not metadata_file:
        try:
            metadata_file = _load_metadata_from_config(args.config)
            print(f"Using metadata file from {args.config}: {metadata_file}")
        except Exception as exc:
            print(f"Error: {exc}")
            return 1

    output_xlsx = args.output
    if output_xlsx is None:
        output_xlsx = os.path.join(
            "metadata", f"metadata_validation_{os.path.basename(metadata_file)}.xlsx"
        )

    print("Starting metadata validation...")
    print(f"Input:  {metadata_file}")
    print(f"Output: {output_xlsx}")
    print("=" * 80)

    try:
        validate_metadata_and_write_report(metadata_file, out_xlsx=output_xlsx)
    except Exception as exc:
        print("=" * 80)
        print(f"Validation failed with exception: {exc}")
        return 1

    print("=" * 80)
    print("Validation completed.")
    print(f"Validation report saved to: {output_xlsx}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
