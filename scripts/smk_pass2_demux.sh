#!/usr/bin/env bash
# Pass 2: re-demux SMK samples from Undetermined reads produced by the VerdA-only
# DRAGEN pass (Pass 1).  Pass 1 demuxes VerdA dual-indexed samples cleanly; SMK
# reads (no i5) fall to Undetermined.  Here we recover them by matching i7 only.
#
# Usage: bash scripts/smk_pass2_demux.sh <config_id> <output_base>
#   config_id   : e.g. lane3
#   output_base : e.g. .output  (the directory that contains <config_id>/)
#
# Requires: fqtk (conda env bcl_convert)

set -euo pipefail

CONFIG_ID="${1:-lane3}"
OUTPUT_BASE="${2:-.output}"
LANE_DIR="${OUTPUT_BASE}/${CONFIG_ID}"

# Extract lane number from config_id (lane3 -> 003)
LANE_NUM=$(echo "$CONFIG_ID" | grep -o '[0-9]*')
LANE_PAD=$(printf "%03d" "$LANE_NUM")

R1="${LANE_DIR}/Undetermined_S0_L${LANE_PAD}_R1_001.fastq.gz"
I1="${LANE_DIR}/Undetermined_S0_L${LANE_PAD}_I1_001.fastq.gz"
R2="${LANE_DIR}/Undetermined_S0_L${LANE_PAD}_R2_001.fastq.gz"

for f in "$R1" "$I1" "$R2"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: expected file not found: $f"
        echo "  Make sure Pass 1 (VerdA-only DRAGEN run) has completed and"
        echo "  CreateFastqForIndexReads=1 is set in the sample sheet."
        exit 1
    fi
done

# Probe I1 read length to build the correct read structure.
# DRAGEN with OverrideCycles I8N2 outputs 10bp reads (8 called + 2 masked).
# DRAGEN with OverrideCycles I8   outputs  8bp reads.
I1_LEN=$(zcat "$I1" | awk 'NR==2{print length($0); exit}')
if [ "$I1_LEN" -ge 10 ]; then
    I1_READ_STRUCT="8B$(( I1_LEN - 8 ))S"
else
    I1_READ_STRUCT="8B"
fi
echo "Detected I1 read length: ${I1_LEN}bp  ->  read structure: ${I1_READ_STRUCT}"

PROJECT="SwarV_BD_SMK_L1_SMK_L2"
OUTPUT_DIR="${LANE_DIR}/${PROJECT}"
mkdir -p "$OUTPUT_DIR"

METADATA=$(mktemp --suffix=.tsv)
trap 'rm -f "$METADATA"' EXIT
printf "sample_id\tbarcode\nSMK_L1\tCGAGGCTG\nSMK_L2\tGTAGAGGA\n" > "$METADATA"

echo "Running fqtk demux..."
fqtk demux \
    --inputs "$R1" "$I1" "$R2" \
    --read-structures "151T" "$I1_READ_STRUCT" "151T" \
    --sample-metadata "$METADATA" \
    --output "$OUTPUT_DIR" \
    --max-mismatches 1 \
    --min-mismatch-delta 2

# Rename fqtk output (SMK_L1.R1.fq.gz) to DRAGEN-style (SMK_L1_S1_L003_R1_001.fastq.gz)
s=1
for sample in SMK_L1 SMK_L2; do
    for read in R1 R2; do
        src="${OUTPUT_DIR}/${sample}.${read}.fq.gz"
        dst="${OUTPUT_DIR}/${sample}_S${s}_L${LANE_PAD}_${read}_001.fastq.gz"
        if [ -f "$src" ]; then
            mv "$src" "$dst"
            echo "  $src -> $dst"
        fi
    done
    s=$(( s + 1 ))
done

echo ""
echo "Demux metrics:"
cat "${OUTPUT_DIR}/demux-metrics.txt"
echo ""
echo "Done. FASTQs written to ${OUTPUT_DIR}/"
