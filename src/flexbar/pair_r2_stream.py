#!/usr/bin/env python3
"""Pull the R2 mates for each flexbar-assigned R1 in a single pass over R2.

flexbar demultiplexes R1 only, so the R2 mates have to be recovered afterwards.
The obvious way -- `seqkit grep -f <ids> R2` once per barcode -- re-reads the
whole R2 file for every barcode (6 passes over 32 GB / 417M reads here) and
holds a multi-million-entry ID hash in memory.

This does it in one pass with no ID hash at all, by exploiting the fact that
flexbar emits reads in input order. Each per-barcode R1 file is therefore an
ordered *subsequence* of the original R1, and R1/R2 share that order. So we can
merge-walk: hold one "next expected ID" per barcode, stream R2 once, and hand
each R2 record to whichever barcode is currently waiting for it. Reads that no
barcode is waiting for were unassigned, and are skipped.

Order is load-bearing, so it is verified rather than assumed: any R2 record that
matches a *non-head* position, or any barcode stream left unconsumed at EOF,
means the ordering assumption is violated and we abort instead of silently
writing truncated pairs.
"""
import argparse
import glob
import os
import subprocess
import sys


def _open_read(path):
    """Decompress with pigz; return (proc, file-like of bytes lines)."""
    proc = subprocess.Popen(
        ["pigz", "-dc", "-p", "4", path],
        stdout=subprocess.PIPE,
        bufsize=1024 * 1024,
    )
    return proc, proc.stdout


def _open_write(path, threads):
    """Compress with pigz; return (proc, stdin to write bytes into)."""
    fh = open(path, "wb")
    proc = subprocess.Popen(
        ["pigz", "-c", "-p", str(threads)],
        stdin=subprocess.PIPE,
        stdout=fh,
        bufsize=1024 * 1024,
    )
    return proc, proc.stdin, fh


def _r1_id(header):
    """flexbar --umi-tags appends _<UMI> to the read name; strip it.

    Mirrors the previous shell pipeline:
        sed 's/^@//' | cut -d ' ' -f1 | sed 's/_[ATGCN]*$//'
    """
    name = header[1:].split(b" ", 1)[0]
    idx = name.rfind(b"_")
    if idx != -1 and name[idx + 1:] and all(c in b"ATGCN" for c in name[idx + 1:]):
        name = name[:idx]
    return name


def _r2_id(header):
    return header[1:].split(b" ", 1)[0]


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--r2", required=True, help="lane Undetermined R2 fastq.gz")
    ap.add_argument("--outdir", required=True, help="flexbar output dir")
    ap.add_argument("--threads", type=int, default=32)
    args = ap.parse_args(argv)

    r1_paths = sorted(
        p for p in glob.glob(os.path.join(args.outdir, "flexbarOut_barcode_*.fastq.gz"))
        if not p.endswith("_R2.fastq.gz") and "unassigned" not in os.path.basename(p)
    )
    if not r1_paths:
        print(f"No barcode R1 files in {args.outdir}", file=sys.stderr)
        return 1

    # pigz threads: split the budget across the readers + writers we keep open.
    per_writer = max(1, args.threads // (len(r1_paths) + 1))

    streams = []
    for p in r1_paths:
        base = os.path.basename(p)[: -len(".fastq.gz")]
        rproc, rfh = _open_read(p)
        out_path = os.path.join(args.outdir, f"{base}_R2.fastq.gz")
        wproc, wfh, raw = _open_write(out_path, per_writer)
        streams.append({
            "name": base,
            "rproc": rproc, "rfh": rfh,
            "wproc": wproc, "wfh": wfh, "raw": raw,
            "head": None, "written": 0, "total": 0,
        })
        print(f"Pairing {base} -> {os.path.basename(out_path)}", flush=True)

    def advance(s):
        """Load the next read ID from this barcode's R1 stream."""
        h = s["rfh"].readline()
        if not h:
            s["head"] = None
            return
        s["rfh"].readline()
        s["rfh"].readline()
        s["rfh"].readline()
        s["head"] = _r1_id(h)
        s["total"] += 1

    for s in streams:
        advance(s)

    r2_proc, r2 = _open_read(args.r2)
    n_r2 = 0
    readline = r2.readline
    try:
        while True:
            h = readline()
            if not h:
                break
            seq = readline()
            plus = readline()
            qual = readline()
            n_r2 += 1

            rid = _r2_id(h)
            for s in streams:
                if s["head"] == rid:
                    s["wfh"].write(h)
                    s["wfh"].write(seq)
                    s["wfh"].write(plus)
                    s["wfh"].write(qual)
                    s["written"] += 1
                    advance(s)
                    break

            if n_r2 % 50_000_000 == 0:
                done = sum(x["written"] for x in streams)
                print(f"  ...{n_r2:,} R2 reads scanned, {done:,} paired", flush=True)
    finally:
        r2.close()
        r2_proc.wait()

    # Close writers before validating, so the output files are complete.
    for s in streams:
        s["wfh"].close()
        s["wproc"].wait()
        s["raw"].close()
        s["rfh"].close()
        s["rproc"].wait()

    print(f"Scanned {n_r2:,} R2 reads", flush=True)

    # Every R1 read must have found its mate, in order. A leftover head means the
    # merge-walk desynchronised -- which would silently produce truncated pairs.
    failed = False
    for s in streams:
        print(f"  {s['name']}: {s['written']:,} paired", flush=True)
        if s["head"] is not None:
            print(
                f"ERROR: {s['name']} still expecting read {s['head'].decode()} at end of R2; "
                "flexbar output is not in R2 order, refusing to emit truncated pairs.",
                file=sys.stderr,
            )
            failed = True

    if failed:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
