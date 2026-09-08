#!/usr/bin/env bash
# Compare the masking-sweep variants against the main run's baseline output.
#
#   pixi run masking-sweep-report            # all sweeps/<library>_L8_R2-* variants
#   SWEEP_FULL=1 pixi run masking-sweep-report   # prefix-check whole files, not first 1M reads
#
# Checks, per variant:
#   - number of delivered FASTQ files and samples
#   - observed R2 read lengths (must be the single requested value)
#   - R2 is an exact prefix of the baseline R2 for one sample
#   - R1 byte-identical to baseline (uncompressed stream)
#
# Reads are looked up in .output/<lane> first and in the delivery second, because
# bcl_project_done MOVES .output/<lane>/<Sample_Project> into
# output/<lane>/<renamed project>: once a run has finished the lane, its staging
# tree holds Reports/, Logs/ and the dragen JSONs and not one read.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

LANE="${SWEEP_LANE:-8}"
CONFIG_ID="lane${LANE}"
HEAD_READS="${SWEEP_HEAD_READS:-1000000}"
# Print whichever of a run tree's two conversion roots actually holds reads.
# See the note at the top: a finished lane has been drained out of .output.
fastq_root() {
    local tree="$1" root
    for root in "$tree/.output/$CONFIG_ID" "$tree/output/$CONFIG_ID"; do
        if [ -d "$root" ] && [ -n "$(find "$root" -name '*.fastq.gz' -print -quit)" ]; then
            printf '%s' "$root"
            return 0
        fi
    done
    return 1
}

BASE_OUT="$(fastq_root "$REPO")" || {
    echo "ERROR: no FASTQs under $REPO/.output/$CONFIG_ID or $REPO/output/$CONFIG_ID"
    exit 1
}

# One representative sample: the first baseline R2. Match variants on the BASENAME,
# not on the path relative to the root -- a variant's delivered project folder
# carries its own masking tag (LinE_R2-39_...), so the relative paths differ even
# though the per-sample filenames are identical.
BASE_R2="$(find "$BASE_OUT" -name '*_R2_001.fastq.gz' ! -name 'Undetermined*' | sort | head -1)"
[ -n "$BASE_R2" ] || { echo "ERROR: no R2 FASTQs under $BASE_OUT"; exit 1; }
BASE_R1="${BASE_R2/_R2_001/_R1_001}"
SAMPLE_BASE="$(basename "$BASE_R2")"

r2_lengths() {  # file -> sorted unique read lengths (sampled)
    pigz -dc "$1" | head -n $((HEAD_READS * 4)) \
        | awk 'NR%4==2{print length($0)}' | sort -un | paste -sd, -
}

echo "baseline: $BASE_OUT"
echo "representative sample: $SAMPLE_BASE"
echo
printf '%-14s %8s %8s %-14s %-10s %-10s\n' variant fastqs samples r2_lengths r2_prefix r1_identical

count_line() {  # dir -> "<fastq count> <sample count>"
    local d="$1"
    local n s
    n="$(find "$d" -name '*.fastq.gz' | wc -l)"
    s="$(find "$d" -name '*_R1_001.fastq.gz' | wc -l)"
    printf '%s %s' "$n" "$s"
}

read -r B_N B_S <<< "$(count_line "$BASE_OUT")"
printf '%-14s %8s %8s %-14s %-10s %-10s\n' \
    "baseline" "$B_N" "$B_S" "$(r2_lengths "$BASE_R2")" "-" "-"

shopt -s nullglob
for work in sweeps/*_L${LANE}_R2-*; do
    tag="${work##*_}"
    n="${tag#R2-}"
    if ! vout="$(fastq_root "$REPO/$work")"; then
        printf '%-14s %8s %8s %-14s %-10s %-10s\n' "$tag" "-" "-" "NOT BUILT" "-" "-"
        continue
    fi

    v_r2="$(find "$vout" -name "$SAMPLE_BASE" -print -quit)"
    if [ -z "$v_r2" ]; then
        printf '%-14s %8s %8s %-14s %-10s %-10s\n' "$tag" "-" "-" "NO SUCH SAMPLE" "-" "-"
        continue
    fi
    v_r1="${v_r2/_R2_001/_R1_001}"
    read -r V_N V_S <<< "$(count_line "$vout")"

    if [ -n "${SWEEP_FULL:-}" ]; then
        prefix_ok=$(cmp -s <(pigz -dc "$BASE_R2" | seqtk trimfq -L "$n" -) \
                           <(pigz -dc "$v_r2") && echo yes || echo NO)
        r1_ok=$(cmp -s <(pigz -dc "$BASE_R1") <(pigz -dc "$v_r1") && echo yes || echo NO)
    else
        prefix_ok=$(cmp -s <(pigz -dc "$BASE_R2" | seqtk trimfq -L "$n" - | head -n $((HEAD_READS * 4))) \
                           <(pigz -dc "$v_r2" | head -n $((HEAD_READS * 4))) && echo yes || echo NO)
        r1_ok=$(cmp -s <(pigz -dc "$BASE_R1" | head -n $((HEAD_READS * 4))) \
                       <(pigz -dc "$v_r1" | head -n $((HEAD_READS * 4))) && echo yes || echo NO)
    fi

    printf '%-14s %8s %8s %-14s %-10s %-10s\n' \
        "$tag" "$V_N" "$V_S" "$(r2_lengths "$v_r2")" "$prefix_ok" "$r1_ok"
done

echo
echo "Delivered folders:"
find "$REPO/output/$CONFIG_ID" -maxdepth 1 -mindepth 1 -type d ! -name Reports 2>/dev/null | sed 's|^|  |'
find "$REPO"/sweeps/*_L${LANE}_R2-*/output/"$CONFIG_ID" -maxdepth 1 -mindepth 1 -type d ! -name Reports 2>/dev/null | sed 's|^|  |'
