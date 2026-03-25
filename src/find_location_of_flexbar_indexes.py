#!/usr/bin/env python3
"""Scan Undetermined FASTQ reads to find the likely position of inline barcode sequences.

Reads barcode sequences from a Flexbar-style barcode FASTA (format: NNNNN<6mer>NNNN),
extracts the core 6-mer, then searches for exact hits in the first --search-len bases
of each read. Reports a per-barcode and combined position histogram.
"""

from __future__ import annotations

import argparse
import gzip
from collections import Counter
from pathlib import Path


def parse_barcode_fa(fasta_path: Path) -> dict[str, str]:
    """Return {barcode_name: 6mer_sequence} by stripping flanking Ns from each entry."""
    barcodes: dict[str, str] = {}
    name: str | None = None
    with fasta_path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                name = line[1:]
            elif name is not None:
                core = line.strip("Nn")
                if not core:
                    raise ValueError(f"Barcode sequence for {name!r} is all Ns: {line!r}")
                barcodes[name] = core
                name = None
    return barcodes


def scan_reads(
    fastq_gz: Path,
    barcodes: dict[str, str],
    n_reads: int,
    search_len: int,
) -> dict[str, Counter]:
    """Scan reads and return per-barcode position hit counters."""
    counters: dict[str, Counter] = {name: Counter() for name in barcodes}
    reads_seen = 0

    open_fn = gzip.open if fastq_gz.suffix in {".gz", ".gzip"} else open
    with open_fn(fastq_gz, "rt", encoding="utf-8") as fh:
        while True:
            header = fh.readline()
            if not header:
                break
            seq = fh.readline().strip()
            fh.readline()  # +
            fh.readline()  # qual

            window = seq[:search_len]
            for name, barcode in barcodes.items():
                blen = len(barcode)
                for pos in range(len(window) - blen + 1):
                    if window[pos : pos + blen] == barcode:
                        counters[name][pos] += 1

            reads_seen += 1
            if n_reads and reads_seen >= n_reads:
                break

    return counters, reads_seen


def print_summary(
    counters: dict[str, Counter],
    barcodes: dict[str, str],
    reads_seen: int,
    search_len: int,
) -> None:
    print(f"\nScanned {reads_seen:,} reads (search window: first {search_len} bp)\n")

    # Per-barcode table
    for name, seq in barcodes.items():
        c = counters[name]
        total = sum(c.values())
        pct = 100 * total / reads_seen if reads_seen else 0
        print(f"{name} ({seq})  —  {total:,} hits ({pct:.1f}% of reads)")
        if c:
            for pos, cnt in sorted(c.items(), key=lambda x: -x[1])[:5]:
                bar = "#" * min(40, int(40 * cnt / max(c.values())))
                print(f"  pos {pos:3d}: {cnt:7,}  {bar}")
        else:
            print("  (no hits)")
        print()

    # Combined histogram
    combined: Counter = Counter()
    for c in counters.values():
        combined.update(c)

    if combined:
        print("Combined position histogram (all barcodes):")
        peak_pos = combined.most_common(1)[0][0]
        max_count = combined.most_common(1)[0][1]
        for pos in sorted(combined):
            cnt = combined[pos]
            bar = "#" * min(50, int(50 * cnt / max_count))
            marker = " <-- peak" if pos == peak_pos else ""
            print(f"  pos {pos:3d}: {cnt:7,}  {bar}{marker}")
        print(f"\nModal barcode position: {peak_pos} (0-based)")
    else:
        print("No barcode hits found in scanned reads.")


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fasta",
        default=str(script_dir / "flexbar" / "xR074-L1-G8-flexbar-barcodes.tsv.fa"),
        help="Barcode FASTA file (NNNNN<6mer>NNNN format)",
    )
    parser.add_argument(
        "--fastq",
        default=str(repo_root / ".output" / "lane1" / "Undetermined_S0_L001_R1_001.fastq.gz"),
        help="Input FASTQ.gz to scan",
    )
    parser.add_argument(
        "--n-reads",
        type=int,
        default=100_000,
        help="Number of reads to sample (0 = all reads)",
    )
    parser.add_argument(
        "--search-len",
        type=int,
        default=30,
        help="Only search the first N bp of each read",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print configuration and exit without scanning",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    fasta = Path(args.fasta).resolve()
    fastq = Path(args.fastq).resolve()

    print(f"Barcode FASTA : {fasta}")
    print(f"FASTQ input   : {fastq}")
    print(f"Reads to scan : {'all' if args.n_reads == 0 else f'{args.n_reads:,}'}")
    print(f"Search window : first {args.search_len} bp")

    if not fasta.exists():
        raise FileNotFoundError(f"Barcode FASTA not found: {fasta}")
    if not fastq.exists():
        raise FileNotFoundError(f"FASTQ not found: {fastq}")

    barcodes = parse_barcode_fa(fasta)
    print(f"\nLoaded {len(barcodes)} barcodes:")
    for name, seq in barcodes.items():
        print(f"  {name}: {seq}")

    if args.dry_run:
        print("\nDry run — exiting without scanning.")
        return 0

    counters, reads_seen = scan_reads(fastq, barcodes, args.n_reads, args.search_len)
    print_summary(counters, barcodes, reads_seen, args.search_len)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
