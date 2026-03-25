#!/usr/bin/env python3
"""Positional inline-barcode demultiplexer for MurnJ-style R1 reads.

Read structure (before BCL Convert trimming):
  [0:5]   5 bp UMI prefix  (Ns)
  [5:11]  6 bp barcode     (R1-direction = RC of TruSeq convention)
  [11:15] 4 bp UMI suffix  (Ns)
  [15:]   insert sequence

Barcode FASTA input contains R1-direction sequences (one per sample).
Hamming distance ≤ 1; ties → Undetermined.
Output reads are hard-clipped to remove the first 15 bp (UMI+barcode+UMI).
UMI (R1[0:5] + R1[11:15]) is appended to the read name as :UMI=<seq> when
--add-umi is set.
"""
from __future__ import annotations

import argparse
import gzip
import os
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Barcode utilities
# ---------------------------------------------------------------------------

def _revcomp(seq: str) -> str:
    trans = str.maketrans("ATGCNatgcn", "TACGNtacgn")
    return seq.translate(trans)[::-1]


def load_barcodes_fasta(fasta_path: Path) -> dict[str, str]:
    """Return {name: r1_barcode} from a FASTA of R1-direction sequences."""
    barcodes: dict[str, str] = {}
    name = None
    with fasta_path.open() as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                name = line[1:].split()[0]
            elif name is not None:
                barcodes[name] = line.upper()
                name = None
    return barcodes


def load_barcodes_tsv(tsv_path: Path) -> dict[str, str]:
    """Return {name: r1_barcode} from a TSV with TruSeq-convention barcodes."""
    barcodes: dict[str, str] = {}
    with tsv_path.open() as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 2:
                continue
            name, truseq_bc = parts[0], parts[1].upper()
            barcodes[name] = _revcomp(truseq_bc)
    return barcodes


def hamming(a: str, b: str) -> int:
    if len(a) != len(b):
        return max(len(a), len(b))
    return sum(x != y for x, y in zip(a, b))


def assign_barcode(obs: str, barcodes: dict[str, str], max_mismatches: int) -> str | None:
    """Return sample name or None (unassigned/tie)."""
    best_name: str | None = None
    best_dist = max_mismatches + 1
    tie = False
    for name, ref in barcodes.items():
        d = hamming(obs, ref)
        if d < best_dist:
            best_dist = d
            best_name = name
            tie = False
        elif d == best_dist:
            tie = True
    return None if tie else best_name


# ---------------------------------------------------------------------------
# FASTQ I/O
# ---------------------------------------------------------------------------

def _open_fastq(path: Path, mode: str = "rt"):
    if str(path).endswith(".gz"):
        return gzip.open(path, mode)
    return open(path, mode)


def _open_output(path: Path):
    return gzip.open(path, "wt", compresslevel=4)


def read_fastq_records(fh):
    """Yield (header, seq, plus, qual) tuples."""
    while True:
        header = fh.readline()
        if not header:
            break
        seq = fh.readline().rstrip("\n")
        plus = fh.readline().rstrip("\n")
        qual = fh.readline().rstrip("\n")
        yield header.rstrip("\n"), seq, plus, qual


# ---------------------------------------------------------------------------
# Main demux logic
# ---------------------------------------------------------------------------

def demux(
    r1_path: Path,
    r2_path: Path | None,
    barcodes: dict[str, str],
    out_dir: Path,
    bc_start: int,
    bc_len: int,
    clip_5p: int,
    max_mismatches: int,
    add_umi: bool,
    umi_prefix_len: int,
    umi_suffix_len: int,
    sample_name_prefix: str,
) -> dict[str, int]:
    out_dir.mkdir(parents=True, exist_ok=True)

    sample_names = list(barcodes.keys()) + ["Undetermined"]
    r1_handles = {n: _open_output(out_dir / f"{sample_name_prefix}{n}_R1.fastq.gz") for n in sample_names}
    r2_handles: dict[str, object] = {}
    if r2_path is not None:
        r2_handles = {n: _open_output(out_dir / f"{sample_name_prefix}{n}_R2.fastq.gz") for n in sample_names}

    counts: dict[str, int] = {n: 0 for n in sample_names}
    bc_end = bc_start + bc_len

    with _open_fastq(r1_path) as r1_fh:
        r2_fh = _open_fastq(r2_path) if r2_path else None
        try:
            r2_iter = read_fastq_records(r2_fh) if r2_fh else None
            for r1_rec in read_fastq_records(r1_fh):
                r1_header, r1_seq, r1_plus, r1_qual = r1_rec

                obs_bc = r1_seq[bc_start:bc_end].upper()
                name = assign_barcode(obs_bc, barcodes, max_mismatches) or "Undetermined"

                if add_umi and len(r1_seq) >= bc_end + umi_suffix_len:
                    umi = r1_seq[:umi_prefix_len] + r1_seq[bc_end: bc_end + umi_suffix_len]
                    tag = f":UMI={umi}"
                    # Insert UMI tag before any existing comment on the header line
                    parts = r1_header.split(" ", 1)
                    r1_header = parts[0] + tag + (" " + parts[1] if len(parts) > 1 else "")

                # Clip 5' bases
                r1_seq_out = r1_seq[clip_5p:]
                r1_qual_out = r1_qual[clip_5p:]

                r1_handles[name].write(f"{r1_header}\n{r1_seq_out}\n{r1_plus}\n{r1_qual_out}\n")
                counts[name] += 1

                if r2_iter is not None:
                    r2_header, r2_seq, r2_plus, r2_qual = next(r2_iter)
                    if add_umi:
                        parts = r2_header.split(" ", 1)
                        r2_header = parts[0] + tag + (" " + parts[1] if len(parts) > 1 else "")
                    r2_handles[name].write(f"{r2_header}\n{r2_seq}\n{r2_plus}\n{r2_qual}\n")
        finally:
            if r2_fh:
                r2_fh.close()

    for fh in r1_handles.values():
        fh.close()
    for fh in r2_handles.values():
        fh.close()

    return counts


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--r1", required=True, help="Input R1 FASTQ(.gz)")
    p.add_argument("--r2", default=None, help="Input R2 FASTQ(.gz) (optional)")
    p.add_argument(
        "--barcodes-fasta",
        default=None,
        help="FASTA of R1-direction barcode sequences (one per sample)",
    )
    p.add_argument(
        "--barcodes-tsv",
        default=None,
        help="TSV of TruSeq-convention barcodes (converted to R1-direction internally)",
    )
    p.add_argument("--out-dir", required=True, help="Output directory")
    p.add_argument("--sample-prefix", default="", help="Prefix for output file names (default: none)")
    p.add_argument("--bc-start", type=int, default=5, help="0-based start of barcode in R1 (default: 5)")
    p.add_argument("--bc-len", type=int, default=6, help="Barcode length (default: 6)")
    p.add_argument(
        "--clip-5p",
        type=int,
        default=15,
        help="Bases to hard-clip from 5' of output R1 (default: 15 = 5N+6bc+4N)",
    )
    p.add_argument("--max-mismatches", type=int, default=1, help="Max Hamming mismatches (default: 1)")
    p.add_argument(
        "--add-umi",
        action="store_true",
        help="Append UMI (prefix + suffix flanking the barcode) to read name as :UMI=<seq>",
    )
    p.add_argument("--umi-prefix-len", type=int, default=5, help="UMI prefix length before barcode (default: 5)")
    p.add_argument("--umi-suffix-len", type=int, default=4, help="UMI suffix length after barcode (default: 4)")
    p.add_argument("--stats-out", default=None, help="Write per-sample read counts to this file")
    return p.parse_args()


def main() -> int:
    args = parse_args()

    if not args.barcodes_fasta and not args.barcodes_tsv:
        print("ERROR: one of --barcodes-fasta or --barcodes-tsv is required", file=sys.stderr)
        return 1

    if args.barcodes_fasta:
        barcodes = load_barcodes_fasta(Path(args.barcodes_fasta))
    else:
        barcodes = load_barcodes_tsv(Path(args.barcodes_tsv))

    if not barcodes:
        print("ERROR: no barcodes loaded", file=sys.stderr)
        return 1

    r2 = Path(args.r2) if args.r2 else None

    counts = demux(
        r1_path=Path(args.r1),
        r2_path=r2,
        barcodes=barcodes,
        out_dir=Path(args.out_dir),
        bc_start=args.bc_start,
        bc_len=args.bc_len,
        clip_5p=args.clip_5p,
        max_mismatches=args.max_mismatches,
        add_umi=args.add_umi,
        umi_prefix_len=args.umi_prefix_len,
        umi_suffix_len=args.umi_suffix_len,
        sample_name_prefix=args.sample_prefix,
    )

    total = sum(counts.values())
    assigned = total - counts.get("Undetermined", 0)
    print(f"Total reads: {total}")
    print(f"Assigned:    {assigned} ({100*assigned/total:.1f}%)" if total else "Assigned: 0")
    for name, n in sorted(counts.items()):
        print(f"  {name}: {n}")

    if args.stats_out:
        with open(args.stats_out, "w") as fh:
            fh.write("Sample\tReads\n")
            for name, n in sorted(counts.items()):
                fh.write(f"{name}\t{n}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
