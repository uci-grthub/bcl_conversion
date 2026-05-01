#!/usr/bin/env bash
# Pass 2: re-demux SMK samples from Undetermined reads produced by the VerdA-only
# DRAGEN pass (Pass 1).  Pass 1 demuxes VerdA dual-indexed samples cleanly; SMK
# reads (no i5) fall to Undetermined.  Here we recover them by matching i7 only.
#
# Usage: bash scripts/smk_pass2_demux.sh [--dry-run] <config_id> <output_base>
#   --dry-run   : print commands without executing them
#   config_id   : e.g. lane3
#   output_base : e.g. .output  (the directory that contains <config_id>/)
#
# Requires: fqtk (conda env bcl_convert)

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

run() {
    if $DRY_RUN; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

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
I1_LEN=$(set +o pipefail; zcat "$I1" | awk 'NR==2{print length($0); exit}')
if [ "$I1_LEN" -ge 10 ]; then
    I1_READ_STRUCT="8B$(( I1_LEN - 8 ))S"
else
    I1_READ_STRUCT="8B"
fi
echo "Detected I1 read length: ${I1_LEN}bp  ->  read structure: ${I1_READ_STRUCT}"

PROJECT="SwarV_BD_SMK_L1_SMK_L2"
OUTPUT_DIR="${LANE_DIR}/${PROJECT}"
run mkdir -p "$OUTPUT_DIR"

METADATA=$(mktemp --suffix=.tsv)
EXTRACT_PY=$(mktemp --suffix=.py)
trap 'rm -f "$METADATA" "$EXTRACT_PY"' EXIT
printf "sample_id\tbarcode\nSMK_L1\tCGAGGCTG\nSMK_L2\tGTAGAGGA\n" > "$METADATA"

echo "Running fqtk demux..."
run conda run -n bcl_convert fqtk demux \
    --inputs "$R1" "$I1" "$R2" \
    --read-structures "151T" "$I1_READ_STRUCT" "151T" \
    --sample-metadata "$METADATA" \
    --output "$OUTPUT_DIR" \
    --max-mismatches 1 \
    --min-mismatch-delta 2

# Extract per-sample I1 reads by matching read names from demuxed R1
cat > "$EXTRACT_PY" << 'PYEOF'
import sys, gzip

r1_gz, i1_src_gz, i1_out_gz = sys.argv[1], sys.argv[2], sys.argv[3]

names = set()
with gzip.open(r1_gz, "rt") as fh:
    for line in fh:
        header = line.rstrip()
        # consume seq, +, qual lines
        for _ in range(3):
            next(fh)
        names.add(header.split()[0][1:])  # strip '@', take first word

with gzip.open(i1_src_gz, "rt") as src, gzip.open(i1_out_gz, "wt") as dst:
    while True:
        header = src.readline()
        if not header:
            break
        seq  = src.readline()
        plus = src.readline()
        qual = src.readline()
        if header.split()[0][1:] in names:
            dst.write(header + seq + plus + qual)
PYEOF

echo "Extracting per-sample I1 reads..."
for sample in SMK_L1 SMK_L2; do
    r1_src="${OUTPUT_DIR}/${sample}.R1.fq.gz"
    i1_out="${OUTPUT_DIR}/${sample}.I1.fq.gz"
    if $DRY_RUN; then
        echo "[dry-run] python3 $EXTRACT_PY $r1_src $I1 $i1_out"
    elif [ -f "$r1_src" ]; then
        conda run -n bcl_convert python3 "$EXTRACT_PY" "$r1_src" "$I1" "$i1_out"
        echo "  extracted I1 -> $i1_out"
    fi
done

# Rename fqtk output (SMK_L1.R1.fq.gz) to DRAGEN-style (SMK_L1_S1_L003_R1_001.fastq.gz)
s=1
for sample in SMK_L1 SMK_L2; do
    for read in R1 I1 R2; do
        src="${OUTPUT_DIR}/${sample}.${read}.fq.gz"
        dst="${OUTPUT_DIR}/${sample}_S${s}_L${LANE_PAD}_${read}_001.fastq.gz"
        if [ -f "$src" ]; then
            run mv "$src" "$dst"
            echo "  $src -> $dst"
        fi
    done
    s=$(( s + 1 ))
done

echo ""
if ! $DRY_RUN; then
    echo "Demux metrics:"
    cat "${OUTPUT_DIR}/demux-metrics.txt"
fi
echo ""
echo "Done. FASTQs written to ${OUTPUT_DIR}/"
