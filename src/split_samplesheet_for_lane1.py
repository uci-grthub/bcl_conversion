#!/usr/bin/env python3
import argparse
import csv
import sys
from pathlib import Path


def parse_samplesheet(path: Path):
    lines = path.read_text().splitlines()

    section = None
    header_lines = []
    settings_rows = []
    data_header = None
    data_rows = []

    for line in lines:
        stripped = line.strip()
        if stripped == "[Header]":
            section = "header"
            continue
        if stripped == "[BCLConvert_Settings]":
            section = "settings"
            continue
        if stripped == "[BCLConvert_Data]":
            section = "data"
            continue

        if section == "header":
            if stripped:
                header_lines.append(stripped)
        elif section == "settings":
            if stripped:
                row = next(csv.reader([line]))
                if len(row) >= 2:
                    settings_rows.append([row[0], row[1]])
        elif section == "data":
            if not stripped:
                continue
            row = next(csv.reader([line]))
            if data_header is None:
                data_header = row
            else:
                data_rows.append(row)

    if data_header is None:
        raise ValueError("Could not find [BCLConvert_Data] section header")

    return header_lines, settings_rows, data_header, data_rows


def write_samplesheet(path: Path, header_lines, settings_rows, data_header, data_rows):
    with path.open("w", newline="") as fh:
        fh.write("[Header]\n")
        for line in header_lines:
            fh.write(f"{line}\n")
        fh.write("\n[BCLConvert_Settings]\n")
        writer = csv.writer(fh, lineterminator="\n")
        for row in settings_rows:
            writer.writerow(row)
        fh.write("\n[BCLConvert_Data]\n")
        writer.writerow(data_header)
        for row in data_rows:
            writer.writerow(row)


def main():
    parser = argparse.ArgumentParser(description="Split lane1 SampleSheet into i7 and i2 subsets")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output-i7", required=True)
    parser.add_argument("--output-i2", required=True)
    parser.add_argument("--target-project", required=True)
    args = parser.parse_args()

    in_path = Path(args.input)
    out_i7 = Path(args.output_i7)
    out_i2 = Path(args.output_i2)

    header_lines, settings_rows, data_header, data_rows = parse_samplesheet(in_path)

    col_map = {name: idx for idx, name in enumerate(data_header)}
    project_col = "Sample_Project" if "Sample_Project" in col_map else "Project"
    if project_col not in col_map:
        raise ValueError("SampleSheet data section missing Sample_Project/Project column")

    pidx = col_map[project_col]
    i2_rows = [r for r in data_rows if pidx < len(r) and r[pidx] == args.target_project]
    i7_rows = [r for r in data_rows if not (pidx < len(r) and r[pidx] == args.target_project)]

    if not i2_rows:
        raise ValueError(f"No rows found for target project: {args.target_project}")
    if not i7_rows:
        raise ValueError("No non-target rows found for i7 split")

    def without_mismatch(rows):
        return [r for r in rows if not r[0].startswith("BarcodeMismatchesIndex")]

    i7_settings = without_mismatch(settings_rows) + [["BarcodeMismatchesIndex1", "0"]]
    i2_settings = without_mismatch(settings_rows)

    write_samplesheet(out_i7, header_lines, i7_settings, data_header, i7_rows)
    write_samplesheet(out_i2, header_lines, i2_settings, data_header, i2_rows)

    print(f"Wrote i7 sheet: {out_i7} ({len(i7_rows)} rows)")
    print(f"Wrote i2 sheet: {out_i2} ({len(i2_rows)} rows)")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
