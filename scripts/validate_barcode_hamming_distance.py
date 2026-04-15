#!/usr/bin/env python3
"""
Validate barcode Hamming distances in sample sheets.

Checks that all barcode combinations maintain minimum Hamming distance
required for 1-mismatch tolerance. Fails fast with clear error reporting.

With --fix: when conflicts are found, sets BarcodeMismatchesIndex1/2 to 0
for the conflicting samples in-place and retries validation.

Usage:
    python3 validate_barcode_hamming_distance.py \
        --samplesheets SampleSheet_lane1.csv SampleSheet_lane2.csv \
        --mismatch-tolerance 1 \
        --output validation_report.txt \
        [--fix]
"""

import argparse
import csv
import sys
import json
from pathlib import Path
from collections import defaultdict
from io import StringIO


def hamming_distance(s1, s2):
    """Calculate Hamming distance between two sequences."""
    if len(s1) != len(s2):
        return None
    return sum(c1 != c2 for c1, c2 in zip(s1, s2))


def _find_data_section(lines):
    """Return (preamble, data_lines) split at the line after [BCLConvert_Data]/[Data]."""
    for i, line in enumerate(lines):
        if line.strip().startswith("[BCLConvert_Data]") or line.strip().startswith("[Data]"):
            return lines[:i + 1], lines[i + 1:]
    return None, None


def parse_samplesheet_data(sheet_path):
    """Extract barcode data rows from sample sheet."""
    try:
        with open(sheet_path, 'r') as f:
            lines = f.readlines()
    except Exception as e:
        raise RuntimeError(f"Could not read {sheet_path}: {e}")

    _, data_lines = _find_data_section(lines)
    if data_lines is None or not data_lines:
        raise RuntimeError(f"Could not find data section in {sheet_path}")

    try:
        reader = csv.DictReader(StringIO("".join(data_lines)))
        rows = list(reader)
    except Exception as e:
        raise RuntimeError(f"Error parsing data section in {sheet_path}: {e}")

    return rows


def validate_sheet_barcodes(sheet_path, tolerance=1):
    """
    Validate barcode Hamming distances in a single sample sheet.

    Returns: (is_valid, errors, config_id, conflict_rows)
      conflict_rows: dict mapping row_idx -> set of {'i7', 'i5'} indicating
                     which index columns need BMI set to 0 to resolve the conflict.
    """
    rows = parse_samplesheet_data(sheet_path)
    config_id = Path(sheet_path).stem.replace("SampleSheet_", "")

    errors = []
    conflict_rows = defaultdict(set)  # row_idx -> {'i7', 'i5'}

    # Group by lane
    lanes = defaultdict(list)
    for i, row in enumerate(rows):
        lane = row.get("Lane", "").strip()
        if not lane:
            continue
        lanes[lane].append((i, row))

    for lane, lane_rows in lanes.items():
        index_pairs = []
        for row_idx, row in lane_rows:
            idx1 = row.get("index", "").strip()
            idx2 = row.get("index2", "").strip()
            project = row.get("Sample_Project", "").strip()
            sample = row.get("Sample_Name", row.get("Sample_ID", "")).strip()

            if not idx1:
                continue

            # Use per-sample BarcodeMismatchesIndex columns; fall back to tolerance
            bmi1 = int(row.get("BarcodeMismatchesIndex1") or tolerance)
            bmi2 = int(row.get("BarcodeMismatchesIndex2") or tolerance) if idx2 else None
            index_pairs.append({
                "row": row_idx,
                "project": project,
                "sample": sample,
                "i7": idx1,
                "i5": idx2 or "",
                "bmi1": bmi1,
                "bmi2": bmi2,
                "barcode_str": f"{idx1}-{idx2}" if idx2 else idx1,
            })

        if len(index_pairs) < 2:
            continue

        # Check pairwise Hamming distances.
        # For 1-mismatch tolerance k, DRAGEN requires distance > 2k between any pair that
        # shares an index channel. Two samples are distinguishable if EITHER i7 OR i5 has
        # sufficient distance; only flag when BOTH are too close (dual-indexed), or when
        # one sample lacks i5 entirely (i7-only comparison).
        for i in range(len(index_pairs)):
            for j in range(i + 1, len(index_pairs)):
                pair1 = index_pairs[i]
                pair2 = index_pairs[j]

                i7_dist = hamming_distance(pair1["i7"], pair2["i7"])
                i5_dist = None
                if pair1["i5"] and pair2["i5"]:
                    i5_dist = hamming_distance(pair1["i5"], pair2["i5"])

                eff_i7_tol = max(pair1["bmi1"], pair2["bmi1"])
                # only_i7: at least one sample lacks i5 (bmi2 is None for single-indexed)
                only_i7 = pair1["bmi2"] is None or pair2["bmi2"] is None

                if only_i7:
                    # DRAGEN requires distance > 2*tol to avoid a midpoint read
                    # matching both samples within tolerance simultaneously.
                    if i7_dist is not None and i7_dist <= 2 * eff_i7_tol:
                        msg = (
                            f"Lane {lane}: Insufficient i7 Hamming distance ({i7_dist}) "
                            f"between {pair1['barcode_str']} ({pair1['project']}/{pair1['sample']}) "
                            f"and {pair2['barcode_str']} ({pair2['project']}/{pair2['sample']})"
                        )
                        errors.append(msg)
                        conflict_rows[pair1["row"]].add("i7")
                        conflict_rows[pair2["row"]].add("i7")
                else:
                    # Dual-indexed: indistinguishable only if BOTH i7 and i5 are too close
                    eff_i5_tol = max(pair1["bmi2"], pair2["bmi2"])
                    i7_too_close = i7_dist is not None and i7_dist <= 2 * eff_i7_tol
                    i5_too_close = i5_dist is not None and i5_dist <= 2 * eff_i5_tol
                    if i7_too_close and i5_too_close:
                        msg = (
                            f"Lane {lane}: Insufficient combined Hamming distance "
                            f"(i7={i7_dist}, i5={i5_dist}) "
                            f"between {pair1['barcode_str']} ({pair1['project']}/{pair1['sample']}) "
                            f"and {pair2['barcode_str']} ({pair2['project']}/{pair2['sample']})"
                        )
                        errors.append(msg)
                        conflict_rows[pair1["row"]].add("i7")
                        conflict_rows[pair1["row"]].add("i5")
                        conflict_rows[pair2["row"]].add("i7")
                        conflict_rows[pair2["row"]].add("i5")

    return len(errors) == 0, errors, config_id, conflict_rows


def fix_sheet_conflicts(sheet_path, conflict_rows, output_path=None):
    """
    Set BarcodeMismatchesIndex1/2 to 0 for rows involved in barcode conflicts.
    Writes the result to output_path (or sheet_path if output_path is None).
    Returns list of sample identifiers that were fixed.
    """
    with open(sheet_path) as f:
        lines = f.readlines()

    preamble, data_lines = _find_data_section(lines)
    if preamble is None or not data_lines:
        print(f"WARNING: Cannot fix {sheet_path}: data section not found", file=sys.stderr)
        return []

    reader = csv.DictReader(StringIO("".join(data_lines)))
    fieldnames = list(reader.fieldnames)
    rows = list(reader)

    if "BarcodeMismatchesIndex1" not in fieldnames:
        fieldnames.append("BarcodeMismatchesIndex1")
    if "BarcodeMismatchesIndex2" not in fieldnames:
        fieldnames.append("BarcodeMismatchesIndex2")

    # DRAGEN requires every row to have a value for BMI columns when the column exists.
    # Fill defaults first (1 for all rows with that index), then override conflicts with 0.
    for row in rows:
        has_i5 = bool(row.get("index2", "").strip())
        if not row.get("BarcodeMismatchesIndex1", "").strip():
            row["BarcodeMismatchesIndex1"] = "1"
        if has_i5:
            if not row.get("BarcodeMismatchesIndex2", "").strip():
                row["BarcodeMismatchesIndex2"] = "1"
        else:
            row["BarcodeMismatchesIndex2"] = ""

    fixed_samples = []
    for row_idx, row in enumerate(rows):
        indices_to_fix = conflict_rows.get(row_idx, set())
        if "i7" in indices_to_fix:
            row["BarcodeMismatchesIndex1"] = "0"
        if "i5" in indices_to_fix:
            row["BarcodeMismatchesIndex2"] = "0"
        if indices_to_fix:
            sample_id = row.get("Sample_ID") or row.get("Sample_Name") or f"row{row_idx}"
            fixed_samples.append(sample_id)

    dest = output_path if output_path is not None else sheet_path
    with open(dest, "w", newline="") as f:
        f.writelines(preamble)
        writer = csv.DictWriter(f, fieldnames=fieldnames, lineterminator="\n", extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    return fixed_samples


def main():
    parser = argparse.ArgumentParser(
        description="Validate barcode Hamming distances in sample sheets"
    )
    parser.add_argument(
        "--samplesheets", nargs="+", required=True,
        help="Path(s) to sample sheet CSV file(s)"
    )
    parser.add_argument(
        "--mismatch-tolerance", type=int, default=1,
        help="Fallback mismatch tolerance when BarcodeMismatchesIndex1/2 columns are absent (default: 1)"
    )
    parser.add_argument(
        "--output", type=str, default=None,
        help="Output file for validation report (default: stdout)"
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Output results in JSON format"
    )
    parser.add_argument(
        "--fix", action="store_true",
        help="On conflict, set BarcodeMismatchesIndex1/2 to 0 for conflicting samples "
             "and retry validation"
    )
    parser.add_argument(
        "--output-sheet", type=str, default=None,
        help="Write the (possibly fixed) samplesheet to this path instead of modifying in-place. "
             "If no fix is needed, the original is copied here unchanged."
    )

    args = parser.parse_args()

    def _run_validation():
        results = {"valid": True, "sheets": {}, "all_errors": []}
        for sheet_path in args.samplesheets:
            try:
                is_valid, errors, config_id, conflict_rows = validate_sheet_barcodes(
                    sheet_path, args.mismatch_tolerance
                )
                results["sheets"][sheet_path] = {
                    "config_id": config_id,
                    "valid": is_valid,
                    "errors": errors,
                    "conflict_rows": conflict_rows,
                }
                if not is_valid:
                    results["valid"] = False
                    results["all_errors"].extend(errors)
            except Exception as e:
                results["valid"] = False
                error_msg = f"Error validating {sheet_path}: {e}"
                results["sheets"][sheet_path] = {
                    "valid": False,
                    "errors": [error_msg],
                    "conflict_rows": {},
                }
                results["all_errors"].append(error_msg)
        return results

    results = _run_validation()

    any_fixed = False
    if not results["valid"] and args.fix:
        for sheet_path, sheet_result in results["sheets"].items():
            if not sheet_result["valid"] and sheet_result.get("conflict_rows"):
                output_path = args.output_sheet if args.output_sheet else None
                fixed = fix_sheet_conflicts(sheet_path, sheet_result["conflict_rows"], output_path)
                if fixed:
                    print(
                        f"Set BarcodeMismatchesIndex to 0 for {len(fixed)} sample(s) in "
                        f"{sheet_path}: {fixed}",
                        file=sys.stderr,
                    )
                    any_fixed = True
        if any_fixed:
            print("Retrying validation after auto-fix...", file=sys.stderr)
            # Re-validate the fixed sheet at output_sheet (or original if no output_sheet)
            validate_path = args.output_sheet if args.output_sheet else args.samplesheets[0]
            original_samplesheets = args.samplesheets
            args.samplesheets = [validate_path]
            results = _run_validation()
            args.samplesheets = original_samplesheets

    # If no fix was applied, still normalize and write output_sheet so per-row
    # BarcodeMismatchesIndex values are explicit for rows that use index2.
    if args.output_sheet and not any_fixed:
        for sheet_path in args.samplesheets:
            if sheet_path != args.output_sheet:
                fix_sheet_conflicts(sheet_path, {}, args.output_sheet)

    # Output results
    if args.json:
        serializable = {
            "valid": results["valid"],
            "all_errors": results["all_errors"],
            "sheets": {
                k: {"config_id": v.get("config_id"), "valid": v["valid"], "errors": v["errors"]}
                for k, v in results["sheets"].items()
            },
        }
        output_text = json.dumps(serializable, indent=2)
    else:
        if results["valid"]:
            output_text = "✓ All sample sheets passed barcode Hamming distance validation\n"
        else:
            output_text = "✗ Barcode Hamming distance validation FAILED\n\n"
            for error in results["all_errors"]:
                output_text += f"  {error}\n"
            output_text += "\nSuggested fix: Apply reverse-complement to i7 or i5 indices for conflicting projects\n"

    if args.output:
        with open(args.output, 'w') as f:
            f.write(output_text)
    else:
        print(output_text, end="")

    sys.exit(0 if results["valid"] else 1)


if __name__ == "__main__":
    main()
