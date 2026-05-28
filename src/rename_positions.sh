#!/bin/bash
# Rename FASTQ files whose position numbers don't match the renaming map,
# then update md5sums.txt in-place (no recomputation).
#
# Usage: bash src/rename_positions.sh [--dry-run] [lane ...]
#   Default lanes: 2 3 4
#   --dry-run  print planned renames without executing them

set -eo pipefail

DRY_RUN=0
LANES=()

for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=1
    else
        LANES+=("$arg")
    fi
done
[[ ${#LANES[@]} -eq 0 ]] && LANES=(2 3 4)

OUTPUT_ROOT="/mnt/jbod_raid/nextshare/bcl_convert/NovaSeqX/xR089/output"
RESULTS_ROOT="/mnt/jbod_raid/nextshare/bcl_convert/NovaSeqX/xR089/results"

for lane in "${LANES[@]}"; do
    map="$RESULTS_ROOT/lane$lane/renaming_map_lane$lane.csv"
    [[ -f "$map" ]] || { echo "WARNING: $map not found, skipping lane $lane"; continue; }

    for dir in "$OUTPUT_ROOT/lane$lane"/*/; do
        [[ -d "$dir" ]] || continue

        # Extract group number from directory name (e.g. _L2_G4 -> 4)
        dirbase=$(basename "$dir")
        grp=$(echo "$dirbase" | grep -oP '(?<=_G)\d+$' || true)
        [[ -z "$grp" ]] && continue

        # Build lookup: "i7:i5" -> correct position number (digits only)
        declare -A pos_lookup=()
        while IFS=',' read -r _sid _sname _proj map_lane i7 i5 _run map_grp pos; do
            [[ "$map_lane" == "Lane" ]] && continue
            [[ "$map_lane" != "$lane" ]] && continue
            [[ "$map_grp" != "$grp" ]] && continue
            pos_num="${pos#P}"
            pos_lookup["${i7}:${i5}"]="$pos_num"
        done < "$map"

        [[ ${#pos_lookup[@]} -eq 0 ]] && { unset pos_lookup; continue; }

        # Collect renames: old_basename -> new_basename
        declare -A renames=()

        for f in "$dir"*.fastq.gz; do
            [[ -f "$f" || -L "$f" ]] || continue
            fname=$(basename "$f")

            # Dual-index: xR089-L{l}-G{g}-P{pos}-{i7}-{i5}-R{1|2}.fastq.gz
            if [[ "$fname" =~ ^xR089-L[0-9]+-G[0-9]+-P([0-9]+)-([A-Z]+)-([A-Z]+)-(R[12]\.fastq\.gz)$ ]]; then
                cur_pos="${BASH_REMATCH[1]}"
                i7="${BASH_REMATCH[2]}"
                i5="${BASH_REMATCH[3]}"
                key="${i7}:${i5}"
            # Single-index: xR089-L{l}-G{g}-P{pos}-{i7}-R{1|2}.fastq.gz
            elif [[ "$fname" =~ ^xR089-L[0-9]+-G[0-9]+-P([0-9]+)-([A-Z]+)-(R[12]\.fastq\.gz)$ ]]; then
                cur_pos="${BASH_REMATCH[1]}"
                i7="${BASH_REMATCH[2]}"
                key="${i7}:"
            else
                continue
            fi

            correct_pos="${pos_lookup[$key]:-}"
            [[ -z "$correct_pos" ]] && continue
            [[ "$cur_pos" == "$correct_pos" ]] && continue

            new_fname=$(echo "$fname" | sed "s/-P${cur_pos}-/-P${correct_pos}-/")
            renames["$fname"]="$new_fname"
        done

        if [[ ${#renames[@]} -eq 0 ]]; then
            unset pos_lookup renames
            continue
        fi

        echo "=== $dirbase ==="

        # Execute renames
        for old_fname in "${!renames[@]}"; do
            new_fname="${renames[$old_fname]}"
            echo "  mv $old_fname -> $new_fname"
            if [[ $DRY_RUN -eq 0 ]]; then
                mv -f "$dir$old_fname" "$dir$new_fname"
            fi
        done

        # Update md5sums.txt in-place
        md5file="${dir}md5sums.txt"
        if [[ -f "$md5file" && $DRY_RUN -eq 0 ]]; then
            for old_fname in "${!renames[@]}"; do
                new_fname="${renames[$old_fname]}"
                old_pos=$(echo "$old_fname" | cut -d'-' -f4)
                new_pos=$(echo "$new_fname" | cut -d'-' -f4)
                [[ -z "$old_pos" || -z "$new_pos" ]] && continue
                sed -i "s/${old_pos}-/${new_pos}-/g" "$md5file"
            done
            echo "  -> updated md5sums.txt"
        fi

        unset pos_lookup renames
    done
done

echo "Done."
