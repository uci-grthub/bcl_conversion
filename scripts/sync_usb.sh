#!/bin/bash
# sync_usb -- copy a run's deliverables (the contents of output/) to a USB drive.
#
#   bash scripts/sync_usb.sh <instrument> <run_id> <usb_base> [lanes]
#   bash scripts/sync_usb.sh NovaSeqX xR130 /mnt/extusb3
#   bash scripts/sync_usb.sh NovaSeqX xR130 /mnt/extusb4 7,8     # lane subset
#
# The USB copy is a delivery archive, not a second publish mirror: it holds only
# what was under output/, flattened one level, so the drive reads
#   <usb_base>/<instrument>/<run_id>/lane1/<project>/...
# with no repo files, .output/ scratch, results/, logs/ or .pixi/. sync_run.sh
# still makes the full run-dir mirror on the JBOD share, which publish needs.
#
# The source run dir is resolved the same way sync_run does it: staging first,
# then the JBOD mirror, so this works before and after staging is cleared.
# Undetermined_S0_* FASTQs are left out (fqtk lanes keep them; not deliverables).
# Lanes not named in [lanes] are neither copied nor deleted at the destination.
# After the copy, verify_mirror.py --flat checks every FASTQ against the source.
set -euo pipefail

usage="sync_usb.sh <instrument> <run_id> <usb_base> [lanes]"
instrument="${1:?Usage: $usage}"
run_id="${2:?Usage: $usage}"
usb_base="${3:?Usage: $usage}"
lanes_arg="${4:-}"

src=""
for base in /staging/nextcloud/testing_illumina /mnt/jbod_localdisk/nextshare/bcl_convert; do
    hit=$(find "$base" -maxdepth 2 -mindepth 2 -type d \
        -ipath "$base/${instrument}/${run_id}" -print -quit 2>/dev/null)
    if [[ -n "$hit" ]]; then
        src="$hit"
        break
    fi
done
if [[ -z "$src" ]]; then
    echo "ERROR: run dir not found for ${instrument}/${run_id} in either staging or jbod_localdisk" >&2
    exit 1
fi
if [[ ! -d "$src/output" ]]; then
    echo "ERROR: $src has no output/ to copy" >&2
    exit 1
fi
run_id=$(basename "$src")
instrument=$(basename "$(dirname "$src")")
dest="${usb_base}/${instrument}/${run_id}"

# Same lane spec as sync_run: "4-6" -> lane4 lane5 lane6, "7,8", "lane3".
lane_dirs=()
if [[ -n "$lanes_arg" ]]; then
    for tok in ${lanes_arg//,/ }; do
        tok="${tok#lane}"
        if [[ "$tok" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            for ((n = BASH_REMATCH[1]; n <= BASH_REMATCH[2]; n++)); do
                lane_dirs+=("lane$n")
            done
        elif [[ "$tok" =~ ^[0-9]+$ ]]; then
            lane_dirs+=("lane$tok")
        else
            echo "ERROR: bad lane spec '$tok' in '$lanes_arg' (want e.g. 4-6, 7,8, lane3)" >&2
            exit 1
        fi
    done
    for n in "${lane_dirs[@]}"; do
        [[ -d "$src/output/$n" ]] || { echo "ERROR: no such lane dir: $src/output/$n" >&2; exit 1; }
    done
else
    for d in "$src"/output/*/; do
        lane_dirs+=("$(basename "$d")")
    done
fi

echo "[sync_usb] src:   $src/output"
echo "[sync_usb] dest:  $dest"
echo "[sync_usb] lanes: ${lane_dirs[*]}"
mkdir -p "$dest"

# One sequential rsync: a single USB drive gains nothing from parallel writes.
# -H keeps hardlinked FASTQs (dedupe_mirror.py) as one copy on the drive.
rsync -aWH --info=progress2 --stats -h \
    --exclude 'Undetermined_S0_*.fastq.gz' \
    "${lane_dirs[@]/#/$src/output/}" "$dest/"

lane_args=()
[[ -n "$lanes_arg" ]] && lane_args=(--lanes "${lane_dirs[@]}")
python3 -I "$(dirname "$(realpath "$0")")/verify_mirror.py" "$dest" --flat \
    --src "$src" "${lane_args[@]}"
echo "[sync_usb] done: $dest"
