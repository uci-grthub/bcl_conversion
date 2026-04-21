#!/usr/bin/env bash
# Stage flexbar output for UMI-aware alignment, fixing read names as needed.
#
# Handles three cases detected automatically from the first read of each sample:
#
#   1. UMI already in read name (readname_NNNNNNNNN <comment>)
#      Fixed flexbar --umi-tags output.  Files are hardlinked/copied as-is;
#      UMI is already in the QNAME-safe portion and survives BAM conversion.
#
#   2. UMI in comment after space (readname <comment_NNNNNNNNN> or <comment+NNNNNNNNN>)
#      Buggy --umi-tags output (pre-fix binary).  Headers are rewritten on the
#      fly to move _UMI from the comment to the read-name portion; output is
#      written as a new gzip file.
#
#   3. No UMI anywhere (BCL-Convert demux or pre --umi-tags flexbar run).
#      Files are hardlinked/copied as-is with an informational note.
#
# Usage:
#   bash src/umi_extract_flexbar.sh <config_id> [output_root]
#
# Example:
#   bash src/umi_extract_flexbar.sh lane8
#   bash src/umi_extract_flexbar.sh lane8 output/lane8_umi
#
# Reads at:  output/<config_id>/flexbar/flexbarOut_barcode_*.fastq.gz
# Output to: <output_root>/flexbarOut_barcode_*.fastq.gz

set -euo pipefail

CONFIG_ID="${1:?Usage: $0 <config_id> [output_root]}"
OUTPUT_ROOT="${2:-output/${CONFIG_ID}_umi}"
INPUT_ROOT="output/${CONFIG_ID}/flexbar"

log() { echo "[$(date '+%H:%M:%S')] $*" >&2; }

log "Config:      $CONFIG_ID"
log "Input root:  $INPUT_ROOT"
log "Output root: $OUTPUT_ROOT"

# Detect where the UMI lives in the first read of a fastq.gz.
# Prints: "name"    – UMI appended to read-name before first space (correct)
#         "comment" – UMI appended to comment after first space   (pre-fix bug)
#         "none"    – no UMI detected
detect_umi() {
    local header
    header=$(zcat "$1" 2>/dev/null | head -1)
    local name="${header%% *}"
    local comment="${header#* }"
    if [[ "$name" =~ _[ACGTNacgtn]{4,}$ ]]; then
        echo "name"
    elif [[ "$comment" =~ _[ACGTNacgtn]{4,}$ || "$comment" =~ \+[ACGTNacgtn]{4,}$ ]]; then
        echo "comment"
    else
        echo "none"
    fi
}

# awk filter: move trailing UMI from the comment field to the read-name.
# Supports both "..._UMI" and "...+UMI" comment styles.
FIX_HEADERS_AWK='
NR % 4 == 1 {
    space = index($0, " ")
    if (space == 0) { print; next }
    name    = substr($0, 1, space - 1)
    comment = substr($0, space + 1)
    if (match(comment, /_[ACGTNacgtn]+$/)) {
        umi     = substr(comment, RSTART + 1)
        name    = name "_" umi
        comment = substr(comment, 1, RSTART - 1)
    } else if (match(comment, /\+[ACGTNacgtn]+$/)) {
        umi     = substr(comment, RSTART + 1)
        name    = name "_" umi
        comment = substr(comment, 1, RSTART - 1)
    }
    print name (length(comment) ? " " comment : "")
    next
}
{ print }
'

# Copy or hardlink a file; fall back to plain copy if hardlink fails.
link_or_copy() {
    cp -l "$1" "$2" 2>/dev/null || cp "$1" "$2"
}

shopt -s nullglob

n_samples=0
n_failed=0

mkdir -p "$OUTPUT_ROOT"

for r1 in "${INPUT_ROOT}"/flexbarOut_barcode_*.fastq.gz; do
    [[ "$r1" == *_R2.fastq.gz ]] && continue

    base_name=$(basename "$r1" .fastq.gz)
    sample_name=${base_name#flexbarOut_barcode_}
    r2="${INPUT_ROOT}/${base_name}_R2.fastq.gz"

    out_r1="${OUTPUT_ROOT}/${base_name}.fastq.gz"
    out_r2="${OUTPUT_ROOT}/${base_name}_R2.fastq.gz"

    umi_loc=$(detect_umi "$r1")

    if {
        case "$umi_loc" in
            name)
                log "Processing $sample_name [UMI in read name → hardlink]"
                link_or_copy "$r1" "$out_r1"
                if [[ -f "$r2" ]]; then
                    link_or_copy "$r2" "$out_r2"
                fi
                ;;
            comment)
                log "Processing $sample_name [UMI in comment → fixing header placement]"
                zcat "$r1" | awk "$FIX_HEADERS_AWK" | gzip -c > "$out_r1"
                if [[ -f "$r2" ]]; then
                    # R2 headers have the same UMI suffix appended; fix those too.
                    zcat "$r2" | awk "$FIX_HEADERS_AWK" | gzip -c > "$out_r2"
                fi
                ;;
            none)
                log "Processing $sample_name [no UMI → hardlink (dedup will not be effective)]"
                link_or_copy "$r1" "$out_r1"
                if [[ -f "$r2" ]]; then
                    link_or_copy "$r2" "$out_r2"
                fi
                ;;
        esac
    }; then
        (( ++n_samples ))
    else
        log "  FAILED: $sample_name"
        (( ++n_failed ))
    fi
done

log "Done. Processed: $n_samples  Failed: $n_failed"
[[ $n_failed -eq 0 ]]
