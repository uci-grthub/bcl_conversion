#!/bin/bash

# One-off fix for xR085: rename existing BD ATAC FASTQ files to BD Rhapsody conventions.
#
# BCL Convert with U60 OverrideCycles produced:
#   R1=genomic, R2=barcode(60bp), R3=genomic
#
# BD Rhapsody expects:
#   R1=genomic, R2=genomic, I2=barcode
#
# Renames: R2→I2, R3→R2
# Also updates md5sums.txt in each project directory.
#
# Usage: bash scripts/fix_bd_atac_read_names_xR085.sh [--dry-run]

set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    echo "DRY RUN — no files will be modified"
fi

ATAC_LANES=(5 6 7 8)
BASE="/mnt/jbod_raid/nextshare/bcl_convert/NovaSeqX/xR085/output"

do_mv() {
    local src="$1" dst="$2"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [dry-run] mv $src -> $dst"
    else
        mv "$src" "$dst"
        echo "  Renamed: $(basename "$src") -> $(basename "$dst")"
    fi
}

for lane in "${ATAC_LANES[@]}"; do
    project_dir="$BASE/lane${lane}/SwarV_0326I-10_xR085_L${lane}_G1"
    if [ ! -d "$project_dir" ]; then
        echo "WARNING: $project_dir not found, skipping"
        continue
    fi

    echo "=== lane${lane}: $project_dir ==="

    r2_files=("$project_dir"/*ATAC*_R2_001.fastq.gz)
    r3_files=("$project_dir"/*ATAC*_R3_001.fastq.gz)

    if [ ${#r2_files[@]} -eq 0 ] || [ ! -e "${r2_files[0]}" ]; then
        echo "  No ATAC R2 files found, skipping"
        continue
    fi

    # Step 1: R2 (barcode) → I2
    for f in "${r2_files[@]}"; do
        [ -e "$f" ] || continue
        new="${f%_R2_001.fastq.gz}_I2_001.fastq.gz"
        if [ -e "$new" ]; then
            echo "  ERROR: $new already exists, skipping" >&2
            continue
        fi
        do_mv "$f" "$new"
    done

    # Step 2: R3 (genomic read 2) → R2
    for f in "${r3_files[@]}"; do
        [ -e "$f" ] || continue
        new="${f%_R3_001.fastq.gz}_R2_001.fastq.gz"
        if [ -e "$new" ]; then
            echo "  ERROR: $new already exists, skipping" >&2
            continue
        fi
        do_mv "$f" "$new"
    done

    # Step 3: update md5sums.txt (rename entries in-place, hashes unchanged)
    md5file="$project_dir/md5sums.txt"
    if [ -f "$md5file" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  [dry-run] update $md5file: s/_R2_001/_I2_001/ and s/_R3_001/_R2_001/ for ATAC entries"
        else
            python3 - "$md5file" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path) as fh:
    lines = fh.readlines()

updated = []
for line in lines:
    parts = line.rstrip('\n').split(None, 1)
    if len(parts) != 2:
        updated.append(line)
        continue
    md5, fname = parts
    # Only touch ATAC sample filenames
    if 'ATAC' not in fname:
        updated.append(line)
        continue
    # Apply in two passes: first mark R2 as pending I2, then rename R3→R2
    fname = re.sub(r'_R2_001\.fastq\.gz$', '_I2_001.fastq.gz', fname)
    fname = re.sub(r'_R3_001\.fastq\.gz$', '_R2_001.fastq.gz', fname)
    updated.append(f"{md5}  {fname}\n")

with open(path, 'w') as fh:
    fh.writelines(updated)
print(f"  Updated {path}")
PYEOF
        fi
    fi
done

echo "Done."
