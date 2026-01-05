#!/usr/bin/env python3
import argparse
import glob
import os
import re
from typing import List, Tuple

PO_PATTERN = re.compile(r"-P(\d+)-")

def extract_po(filename: str) -> Tuple[int, str]:
    match = PO_PATTERN.search(filename)
    if match:
        return int(match.group(1)), filename
    return float("inf"), filename

def sort_md5_file(path: str) -> None:
    with open(path, "r") as f:
        lines = [line.rstrip("\n") for line in f if line.strip()]
    def key_fn(line: str):
        parts = line.split()
        fname = parts[1] if len(parts) > 1 else ""
        po_val, fname_val = extract_po(fname)
        return (po_val, fname_val)
    lines.sort(key=key_fn)
    tmp_path = f"{path}.tmp"
    with open(tmp_path, "w") as f:
        for line in lines:
            f.write(line + "\n")
    os.replace(tmp_path, path)


def main():
    parser = argparse.ArgumentParser(description="Sort md5sums.txt files by PO number in filenames.")
    parser.add_argument("paths", nargs="*", help="md5sums.txt files to sort; defaults to Reports/*/md5sums.txt")
    args = parser.parse_args()

    targets: List[str] = args.paths if args.paths else glob.glob(os.path.join("Reports", "*", "md5sums.txt"))
    if not targets:
        print("No md5sums.txt files found.")
        return

    for path in targets:
        if os.path.isfile(path):
            sort_md5_file(path)
            print(f"Sorted {path}")
        else:
            print(f"Skipped {path} (not a file)")

if __name__ == "__main__":
    main()
