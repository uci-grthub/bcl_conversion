#!/usr/bin/env bash
# Re-extract R2 reads for a flexbar-demuxed project using seqtk.
# Flexbar --umi-tags appends UMI to R1 names (readID_UMI) but R2 retains bare
# readIDs, so seqtk must search by bare ID, then R2 headers are renamed to
# match R1 so downstream aligners pair correctly and umi_tools read_id works.
set -euo pipefail

ORIG_R2=".output/lane8/Undetermined_S0_L008_R2_001.fastq.gz"
PROJECT_DIR="output/lane8/WangY_0326I-32_xR087_L8_G7"
THREADS=8

if [ ! -f "$ORIG_R2" ]; then
    echo "ERROR: original R2 not found: $ORIG_R2" >&2
    exit 1
fi

for r1 in "$PROJECT_DIR"/*-R1.fastq.gz; do
    stem=$(basename "$r1" -R1.fastq.gz)
    r2="$PROJECT_DIR/${stem}-R2.fastq.gz"
    bare_headers=$(mktemp)
    umi_map=$(mktemp)

    echo "Extracting R2 for $stem ..."

    # Single pass over R1: build bare readID list for seqtk and bare→tagged map
    # for renaming R2 headers.  Only process R1 records (header contains " 1:N").
    zcat "$r1" | awk '
        /^@/ && / 1:N/ {
            tagged = substr($1, 2)      # strip leading @
            bare = tagged
            sub(/_[ATGCN]+$/, "", bare)
            print bare   > bare_file
            print bare "\t" tagged > map_file
        }
    ' bare_file="$bare_headers" map_file="$umi_map"

    count=$(wc -l < "$bare_headers")
    echo "  Found $count read headers"

    if [ "$count" -eq 0 ]; then
        echo "  WARNING: no headers found, skipping $stem" >&2
        rm "$bare_headers" "$umi_map"
        continue
    fi

    # Extract R2 reads by bare ID, then rename headers to tagged form so R1/R2
    # names match exactly (required for proper BAM pairing and umi_tools).
    seqtk subseq "$ORIG_R2" "$bare_headers" | \
    awk -v mapfile="$umi_map" '
        BEGIN {
            while ((getline line < mapfile) > 0) {
                n = split(line, a, "\t")
                if (n == 2) map[a[1]] = a[2]
            }
        }
        /^@/ {
            # $1 is @readID, rest is the space + flag field
            readid = substr($1, 2)
            if (readid in map) sub(/^@[^ ]*/, "@" map[readid])
            print
            next
        }
        { print }
    ' | pigz -p "$THREADS" > "${r2}.tmp"

    mv "${r2}.tmp" "$r2"
    rm "$bare_headers" "$umi_map"

    extracted=$(zcat "$r2" | awk 'NR%4==1' | wc -l)
    echo "  Wrote $extracted reads to $r2"
done

echo "Done."
