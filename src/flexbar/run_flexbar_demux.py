#!/usr/bin/env python3
"""Run Flexbar demultiplexing similar to xR074_data/flexbar/script.sh + demux.sh.

This script:
1. Reads a barcode TSV like: Barcode1<TAB>ATCACG
2. Writes a barcode FASTA with the historical format used by the legacy helper:
   >Barcode1
   NNNNN<reverse-complement(barcode)>NNNN
3. Runs Flexbar with the same arguments as demux.sh.
    Binary resolution order:
    - --flexbar-bin
    - $FLEXBAR_BIN
    - common local build paths
    - flexbar found on $PATH
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from pathlib import Path


def reverse_complement(seq: str) -> str:
    trans = str.maketrans("ATCGNatcgn", "TAGCNtagcn")
    return seq.translate(trans)[::-1]


def build_barcode_fasta(sample_info: Path, barcode_fasta: Path) -> int:
    count = 0
    with sample_info.open("r", encoding="utf-8") as src, barcode_fasta.open(
        "w", encoding="utf-8"
    ) as out:
        for line in src:
            stripped = line.strip()
            if not stripped:
                continue
            parts = stripped.split()
            if len(parts) < 2:
                raise ValueError(f"Invalid barcode line (expected 2 columns): {stripped}")
            name = parts[0]
            barcode = parts[1].strip()
            rc = reverse_complement(barcode)
            out.write(f">{name}\n")
            out.write(f"NNNNN{rc}NNNN\n")
            count += 1
    return count


def build_flexbar_command(
    flexbar_bin: Path,
    barcode_fasta: Path,
    raw_data: Path,
    adapter_fasta: Path,
    threads: int,
) -> list[str]:
    return [
        str(flexbar_bin),
        "-n",
        str(threads),
        "--barcodes",
        str(barcode_fasta),
        "-r",
        str(raw_data),
        "--barcode-trim-end",
        "LTAIL",
        "--barcode-error-rate",
        "0",
        "--adapters",
        str(adapter_fasta),
        "--adapter-error-rate",
        "0.1",
        "--adapter-min-overlap",
        "1",
        "--adapter-trim-end",
        "RIGHT",
        "--zip-output",
        "GZ",
        "--barcode-unassigned",
        "--min-read-length",
        "15",
        "--umi-tags",
    ]


def resolve_flexbar_bin(explicit: str | None, repo_root: Path) -> Path:
    candidates: list[Path] = []

    if explicit:
        candidates.append(Path(explicit).expanduser())

    env_bin = os.environ.get("FLEXBAR_BIN", "").strip()
    if env_bin:
        candidates.append(Path(env_bin).expanduser())

    # Common local build locations used in this workflow.
    candidates.extend(
        [
            repo_root / "build_parasail" / "src" / "flexbar",
            Path("/home/kstachel/TOOLS/flexbar-speedup/build_parasail/src/flexbar"),
        ]
    )

    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved.exists() and os.access(resolved, os.X_OK):
            return resolved

    in_path = shutil.which("flexbar")
    if in_path:
        return Path(in_path).resolve()

    checked = "\n".join(f"- {c}" for c in candidates)
    raise FileNotFoundError(
        "Flexbar binary not found. Checked:\n"
        f"{checked}\n"
        "Also checked $PATH for 'flexbar'. Set --flexbar-bin or FLEXBAR_BIN."
    )


def gzip_fastq_outputs(work_dir: Path) -> int:
    fastq_files = sorted(work_dir.glob("flexbarOut*.fastq"))
    if not fastq_files:
        return 0

    compressor = shutil.which("pigz") or shutil.which("gzip")
    if not compressor:
        raise RuntimeError(
            "Flexbar produced .fastq files, but neither pigz nor gzip is available in PATH"
        )

    for fq in fastq_files:
        subprocess.run([compressor, "-f", str(fq)], check=True)

    return len(fastq_files)


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent

    parser = argparse.ArgumentParser(
        description="Run Flexbar demux in the same manner as legacy demux.sh"
    )
    parser.add_argument(
        "--sample-info",
        default="xR074-L1-G8-flexbar-barcodes.tsv",
        help="Barcode TSV file (default: xR074-L1-G8-flexbar-barcodes.tsv)",
    )
    parser.add_argument(
        "--raw-data",
        default="Undetermined_S0_L001_R1_001.fastq.gz",
        help="Input FASTQ file to demultiplex",
    )
    parser.add_argument(
        "--adapter",
        default="adapter.3.fa",
        help="Adapter FASTA file",
    )
    parser.add_argument(
        "--barcode-fasta",
        default=None,
        help="Output barcode FASTA path (default: <sample-info>.fa)",
    )
    parser.add_argument(
        "--work-dir",
        default=str(script_dir),
        help="Working directory for resolving input files",
    )
    parser.add_argument(
        "--output-dir",
        default="output/flexbar",
        help=(
            "Directory where Flexbar output files are written "
            "(default: output/flexbar relative to repository root)"
        ),
    )
    parser.add_argument(
        "--flexbar-bin",
        default=None,
        help="Path to Flexbar binary (optional; can also use FLEXBAR_BIN)",
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=32,
        help="Number of Flexbar threads to use (default: 32)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print actions and command without running Flexbar",
    )
    parser.add_argument(
        "--no-auto-gzip",
        action="store_true",
        help="Disable post-run gzip fallback when Flexbar outputs plain .fastq files",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent

    work_dir = Path(args.work_dir).resolve()
    output_dir_arg = Path(args.output_dir)
    if output_dir_arg.is_absolute():
        output_dir = output_dir_arg.resolve()
    else:
        output_dir = (repo_root / output_dir_arg).resolve()

    output_dir.mkdir(parents=True, exist_ok=True)

    sample_info = (work_dir / args.sample_info).resolve()
    raw_data = (work_dir / args.raw_data).resolve()
    adapter_fasta = (work_dir / args.adapter).resolve()
    flexbar_bin = resolve_flexbar_bin(args.flexbar_bin, repo_root)

    if args.barcode_fasta:
        barcode_fasta = (work_dir / args.barcode_fasta).resolve()
    else:
        barcode_fasta = Path(str(sample_info) + ".fa")

    if not sample_info.exists():
        raise FileNotFoundError(f"Sample info file not found: {sample_info}")
    if not raw_data.exists():
        raise FileNotFoundError(f"Raw data FASTQ not found: {raw_data}")
    if not adapter_fasta.exists():
        raise FileNotFoundError(f"Adapter FASTA not found: {adapter_fasta}")
    if args.threads < 1:
        raise ValueError("--threads must be >= 1")

    count = build_barcode_fasta(sample_info, barcode_fasta)
    print(f"Wrote barcode FASTA: {barcode_fasta} ({count} entries)")

    cmd = build_flexbar_command(
        flexbar_bin,
        barcode_fasta,
        raw_data,
        adapter_fasta,
        args.threads,
    )
    print("Running Flexbar command:")
    print(" ".join(cmd))
    print(f"Writing outputs to: {output_dir}")

    if args.dry_run:
        print("Dry run requested; exiting without executing Flexbar.")
        return 0

    proc = subprocess.run(cmd, cwd=output_dir)
    if proc.returncode != 0:
        return proc.returncode

    if not args.no_auto_gzip:
        gzipped = gzip_fastq_outputs(output_dir)
        if gzipped:
            print(f"Compressed {gzipped} Flexbar FASTQ outputs to .gz")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
