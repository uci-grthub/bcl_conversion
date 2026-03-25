#!/usr/bin/env python3
"""Convert barcode TSV to FASTA for Flexbar.

Input columns: <name> <barcode>
Output sequence: NNNNN + reverse_complement(barcode) + NNNN
"""

from __future__ import annotations

import argparse
from pathlib import Path


def reverse_complement(seq: str) -> str:
    trans = str.maketrans("ATCGNatcgn", "TAGCNtagcn")
    return seq.translate(trans)[::-1]


def convert(sample_info: Path, out_fasta: Path) -> int:
    written = 0
    with sample_info.open("r", encoding="utf-8") as src, out_fasta.open("w", encoding="utf-8") as out:
        for line in src:
            s = line.strip()
            if not s:
                continue
            parts = s.split()
            if len(parts) < 2:
                raise ValueError(f"Invalid sample-info line: {s}")
            name = parts[0]
            barcode = parts[1]
            out.write(f">{name}\n")
            out.write(f"NNNNN{reverse_complement(barcode)}NNNN\n")
            written += 1
    return written


def main() -> int:
    p = argparse.ArgumentParser(description="Build Flexbar barcode FASTA from sample info TSV")
    p.add_argument("sample_info", help="Path to barcode TSV")
    p.add_argument("output_fasta", help="Path to output FASTA")
    args = p.parse_args()

    n = convert(Path(args.sample_info), Path(args.output_fasta))
    print(f"Wrote {args.output_fasta} with {n} barcodes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
