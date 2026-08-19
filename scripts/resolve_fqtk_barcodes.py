#!/usr/bin/env python3
"""Extend short fqtk barcodes to the lane's full index-read length, from real data.

A sample routed to fqtk because of an index collision carries a short index (e.g. the
6bp GTAGAG that collides with the 8bp GTAGAGGA). fqtk matches a fixed number of bases,
so the short index has to be expressed at the full length actually sequenced. The
trailing cycles are not part of the library's index -- they read whatever follows it,
usually a constant adapter sequence -- so the only reliable source is the run itself.

For each short barcode this samples the Undetermined I1 reads, tallies the full-length
forms whose prefix matches, and keeps the dominant one.

Undetermined also holds reads that belong to samples DRAGEN did demultiplex -- ones it
could not assign confidently -- and a resolved barcode can sit within fqtk's mismatch
tolerance of one of those sample indexes. To stop those reads leaking into a recovered
sample, every index in the DRAGEN sheet is written to the output as a decoy entry.
fqtk then assigns such a read to the decoy that actually matches it best rather than to
a routed sample, and the caller discards the decoy FASTQs afterwards.

Decoys cannot help when a resolved barcode is *identical* to a sheet index, since no
rule could tell the two apart; that case fails loudly instead.

Adding decoys tightens how close two barcodes can be, so the matching thresholds fqtk
should run with follow from the finished table rather than being fixed in the caller.
They are written to a shell-sourceable sidecar next to the output TSV.

Usage:
    resolve_fqtk_barcodes.py --barcodes metadata/fqtk_barcodes_lane2.tsv \
        --undetermined-i1 .output/lane2/Undetermined_S0_L002_I1_001.fastq.gz \
        --samplesheet results/lane2/SampleSheet_lane2_validated.csv \
        --output metadata/fqtk_barcodes_lane2_resolved.tsv
"""

import argparse
import csv
import gzip
import sys
from collections import Counter
from io import StringIO


def read_barcode_tsv(path):
    entries = []
    with open(path) as f:
        header = f.readline().rstrip("\n").split("\t")
        for line in f:
            if not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            entries.append(dict(zip(header, fields)))
    return header, entries


def read_sheet_indexes(path):
    """Return every i7 index in the DRAGEN sheet, to check separation against."""
    with open(path) as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        if line.strip().startswith("[BCLConvert_Data]") or line.strip().startswith("[Data]"):
            data_lines = lines[i + 1 :]
            break
    else:
        return []
    reader = csv.DictReader(StringIO("".join(data_lines)))
    return [r["index"].strip() for r in reader if (r.get("index") or "").strip()]


def observed_forms(i1_path, prefix, max_reads):
    """Tally full-length I1 sequences starting with prefix, over the first max_reads."""
    counts = Counter()
    scanned = 0
    with gzip.open(i1_path, "rt") as f:
        for line_no, line in enumerate(f):
            if line_no % 4 != 1:
                continue
            scanned += 1
            if scanned > max_reads:
                break
            seq = line.strip()
            if seq.startswith(prefix):
                counts[seq] += 1
    return counts, scanned


def hamming(s1, s2):
    n = min(len(s1), len(s2))
    return sum(a != b for a, b in zip(s1[:n], s2[:n]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--barcodes", required=True, help="fqtk barcode TSV to resolve")
    parser.add_argument("--undetermined-i1", required=True, help="Undetermined I1 FASTQ (gz)")
    parser.add_argument("--samplesheet", help="DRAGEN sheet whose indexes must stay separable")
    parser.add_argument("--output", required=True, help="resolved TSV to write")
    parser.add_argument(
        "--params-output",
        help="shell-sourceable fqtk matching thresholds (default: <output>.params)",
    )
    parser.add_argument(
        "--target-length", type=int, default=8,
        help="barcode length fqtk will match (default: 8, matching the demux read structure)",
    )
    parser.add_argument(
        "--max-reads", type=int, default=4_000_000,
        help="Undetermined reads to sample when measuring (default: 4,000,000)",
    )
    parser.add_argument(
        "--decoy-prefix", default="decoy__",
        help="sample_id prefix for decoy entries covering DRAGEN-assigned indexes",
    )
    parser.add_argument(
        "--min-fraction", type=float, default=0.5,
        help="dominant form must hold at least this share of matching reads (default: 0.5)",
    )
    args = parser.parse_args()

    header, entries = read_barcode_tsv(args.barcodes)
    sheet_indexes = read_sheet_indexes(args.samplesheet) if args.samplesheet else []

    errors = []
    short = [e for e in entries if len(e["barcode"]) < args.target_length]
    if not short:
        print(f"All barcodes already {args.target_length}bp or longer.")

    for entry in short:
        prefix = entry["barcode"]
        counts, scanned = observed_forms(args.undetermined_i1, prefix, args.max_reads)
        total = sum(counts.values())
        if not total:
            errors.append(
                f"{entry['sample_id']}: no Undetermined read starts with {prefix} "
                f"in the first {scanned:,} reads; the sample may have no reads at all"
            )
            continue

        full, hits = counts.most_common(1)[0]
        resolved = full[: args.target_length]
        share = hits / total
        print(
            f"{entry['sample_id']}: {prefix} -> {resolved} "
            f"({hits:,}/{total:,} matching reads, {share:.1%}); "
            f"top forms: {[f'{seq}:{n}' for seq, n in counts.most_common(3)]}"
        )

        if share < args.min_fraction:
            errors.append(
                f"{entry['sample_id']}: no dominant full-length form for {prefix} "
                f"(best {resolved} holds only {share:.1%} of {total:,} reads). The trailing "
                f"cycles are not constant for this library, so a fixed barcode cannot "
                f"represent it -- demultiplex this sample by hand"
            )
            continue

        entry["barcode"] = resolved

    # A resolved barcode identical to a sheet index is unresolvable: the decoy below
    # would compete with the real sample on equal terms and fqtk would split the reads
    # arbitrarily between them.
    resolved_by_barcode = {e["barcode"]: e["sample_id"] for e in entries}
    for other in sheet_indexes:
        truncated = other[: args.target_length]
        if truncated in resolved_by_barcode:
            errors.append(
                f"{resolved_by_barcode[truncated]}: resolved barcode {truncated} is identical "
                f"to sheet index {other}; no rule can separate these two libraries -- "
                f"they need different indexes"
            )

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    # Decoys soak up reads belonging to samples DRAGEN already demultiplexed, so a
    # near-miss index cannot leak into a recovered sample. Only full-length indexes can
    # be represented at the demux read structure; a shorter one stays in the sheet and
    # keeps its own reads anyway.
    decoys = []
    seen = set(resolved_by_barcode)
    skipped_short = 0
    for other in sheet_indexes:
        if len(other) < args.target_length:
            skipped_short += 1
            continue
        truncated = other[: args.target_length]
        if truncated in seen:
            continue
        seen.add(truncated)
        # Build with the TSV's own column names so the decoy rows line up with header.
        decoys.append({header[0]: f"{args.decoy_prefix}{truncated}", header[1]: truncated})

    nearest = []
    for entry in entries:
        for decoy in decoys:
            distance = hamming(entry[header[1]], decoy[header[1]])
            if distance <= 2:
                nearest.append(f"{entry[header[0]]}~{decoy[header[1]]}(d={distance})")
    if nearest:
        print(f"Decoys covering near neighbours: {', '.join(nearest)}")
    print(
        f"Added {len(decoys)} decoy entries from the DRAGEN sheet"
        + (f" ({skipped_short} indexes shorter than {args.target_length}bp skipped)" if skipped_short else "")
    )

    # fqtk's matching thresholds have to follow from how close the barcodes actually
    # are, not from a fixed guess. A routed sample one mismatch from a decoy loses
    # every read under --min-mismatch-delta 2: a perfect read scores 0 against the
    # sample and 1 against the decoy, a delta of 1, so fqtk calls it ambiguous and
    # writes it to unmatched. Exactly that silently emptied lane4's 1JK (ATCACGAT,
    # one mismatch from the sheet's ACCACGAT).
    #
    # Assignment is safe when the winning margin still exceeds the delta:
    #   min distance >= 2  ->  perfect reads clear a delta of 2, and one mismatch of
    #                          error tolerance cannot reach another barcode first
    #   min distance == 1  ->  only exact matches can be told apart, so drop both the
    #                          tolerance and the delta rather than dropping the sample
    min_distance = None
    for entry in entries:
        for other in entries + decoys:
            if other is entry:
                continue
            distance = hamming(entry[header[1]], other[header[1]])
            if min_distance is None or distance < min_distance:
                min_distance = distance
    if min_distance is None:
        min_distance = args.target_length

    max_mismatches = 1 if min_distance >= 2 else 0
    min_mismatch_delta = min(2, min_distance)
    print(
        f"Closest barcode pair involving a routed sample: {min_distance} mismatch(es) "
        f"-> --max-mismatches {max_mismatches} --min-mismatch-delta {min_mismatch_delta}"
    )
    if max_mismatches == 0:
        print(
            "Exact-match-only assignment: reads carrying a sequencing error in the "
            "barcode go to unmatched. Widening the tolerance here would assign reads "
            "to the wrong library instead."
        )

    params_path = args.params_output or f"{args.output}.params"
    with open(params_path, "w") as f:
        f.write(f"FQTK_MAX_MISMATCHES={max_mismatches}\n")
        f.write(f"FQTK_MIN_MISMATCH_DELTA={min_mismatch_delta}\n")
        f.write(f"FQTK_MIN_BARCODE_DISTANCE={min_distance}\n")
    print(f"Wrote {params_path}")

    with open(args.output, "w") as f:
        f.write("\t".join(header) + "\n")
        for entry in entries:
            f.write("\t".join(entry[col] for col in header) + "\n")
        for decoy in decoys:
            f.write("\t".join(decoy[col] for col in header) + "\n")
    print(f"Wrote {args.output}: {len(entries)} samples + {len(decoys)} decoys")
    return 0


if __name__ == "__main__":
    sys.exit(main())
