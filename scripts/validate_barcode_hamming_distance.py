#!/usr/bin/env python3
"""
Validate barcode Hamming distances in sample sheets.

Checks that all barcode combinations maintain minimum Hamming distance
required for 1-mismatch tolerance. Fails fast with clear error reporting.

Usage:
    python3 validate_barcode_hamming_distance.py \
        --samplesheets SampleSheet_lane1.csv SampleSheet_lane2.csv \
        --mismatch-tolerance 1 \
        --output validation_report.txt
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


def parse_samplesheet_data(sheet_path):
    """Extract barcode data from sample sheet."""
    try:
        with open(sheet_path, 'r') as f:
            lines = f.readlines()
    except Exception as e:
        raise RuntimeError(f"Could not read {sheet_path}: {e}")

    # Find [BCLConvert_Data] or [Data] section
    header_row = -1
    for i, line in enumerate(lines):
        if line.strip().startswith("[BCLConvert_Data]") or line.strip().startswith("[Data]"):
            header_row = i + 1
            break

    if header_row == -1 or header_row >= len(lines):
        raise RuntimeError(f"Could not find data section in {sheet_path}")

    data_str = "".join(lines[header_row:])
    try:
        reader = csv.DictReader(StringIO(data_str))
        rows = list(reader)
    except Exception as e:
        raise RuntimeError(f"Error parsing data section in {sheet_path}: {e}")

    return rows


def validate_sheet_barcodes(sheet_path, tolerance=1):
    """
    Validate barcode Hamming distances in a single sample sheet.
    
    Returns: (is_valid, errors, config_id)
    """
    rows = parse_samplesheet_data(sheet_path)
    
    # Extract config_id from filename (e.g., SampleSheet_lane5.csv -> lane5)
    config_id = Path(sheet_path).stem.replace("SampleSheet_", "")
    
    errors = []
    
    # Group by lane (lane-specific validation required by DRAGEN)
    lanes = defaultdict(list)
    for i, row in enumerate(rows):
        lane = row.get("Lane", "").strip()
        if not lane:
            continue
        lanes[lane].append((i, row))
    
    # Validate each lane's barcodes
    for lane, lane_rows in lanes.items():
        # Extract all index pairs for this lane
        index_pairs = []
        for row_idx, row in lane_rows:
            idx1 = row.get("index", "").strip()
            idx2 = row.get("index2", "").strip()
            project = row.get("Sample_Project", "").strip()
            sample = row.get("Sample_Name", row.get("Sample_ID", "")).strip()
            
            if not idx1:
                continue
            
            index_pairs.append({
                "row": row_idx,
                "project": project,
                "sample": sample,
                "i7": idx1,
                "i5": idx2 or "",
                "barcode_str": f"{idx1}-{idx2}" if idx2 else idx1,
            })
        
        if len(index_pairs) < 2:
            continue
        
        # Check pairwise Hamming distances (i7, i5 separately)
        for i in range(len(index_pairs)):
            for j in range(i + 1, len(index_pairs)):
                pair1 = index_pairs[i]
                pair2 = index_pairs[j]
                
                # Check i7 distance
                i7_dist = hamming_distance(pair1["i7"], pair2["i7"])
                if i7_dist is not None and i7_dist <= tolerance:
                    msg = (
                        f"Lane {lane}: Insufficient i7 Hamming distance ({i7_dist}) "
                        f"between {pair1['barcode_str']} ({pair1['project']}/{pair1['sample']}) "
                        f"and {pair2['barcode_str']} ({pair2['project']}/{pair2['sample']})"
                    )
                    errors.append(msg)
                
                # Check i5 distance (if both have i5)
                if pair1["i5"] and pair2["i5"]:
                    i5_dist = hamming_distance(pair1["i5"], pair2["i5"])
                    if i5_dist is not None and i5_dist <= tolerance:
                        msg = (
                            f"Lane {lane}: Insufficient i5 Hamming distance ({i5_dist}) "
                            f"between {pair1['barcode_str']} ({pair1['project']}/{pair1['sample']}) "
                            f"and {pair2['barcode_str']} ({pair2['project']}/{pair2['sample']})"
                        )
                        errors.append(msg)
    
    return len(errors) == 0, errors, config_id


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
        help="Mismatch tolerance for barcode distance check (default: 1)"
    )
    parser.add_argument(
        "--output", type=str, default=None,
        help="Output file for validation report (default: stdout)"
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Output results in JSON format"
    )
    
    args = parser.parse_args()
    
    results = {
        "valid": True,
        "sheets": {},
        "all_errors": [],
    }
    
    # Validate each sample sheet
    for sheet_path in args.samplesheets:
        try:
            is_valid, errors, config_id = validate_sheet_barcodes(
                sheet_path, args.mismatch_tolerance
            )
            
            results["sheets"][sheet_path] = {
                "config_id": config_id,
                "valid": is_valid,
                "errors": errors,
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
            }
            results["all_errors"].append(error_msg)
    
    # Output results
    output_text = ""
    if args.json:
        output_text = json.dumps(results, indent=2)
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
    
    # Exit with error code if validation failed
    sys.exit(0 if results["valid"] else 1)


if __name__ == "__main__":
    main()
