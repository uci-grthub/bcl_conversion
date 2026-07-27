#!/bin/bash
# sync_run -- mirror a completed run directory to the NFS/JBOD share.
#
# Vendored into this repo (previously lived in the operator's ~/.bash_functions)
# so publishing works from a fresh clone with no dotfile setup.
#
# Source it to get the function, or execute it directly as a script:
#   source scripts/sync_run.sh && sync_run NovaSeqx xR101
#   bash scripts/sync_run.sh NovaSeqx xR101

sync_run() {
    # Mirror a run dir to the NFS share. The destination is a 10GbE NFS mount,
    # and a single rsync stream only fills ~20% of the link (NFS latency-bound),
    # so the big output/ FASTQ dirs are transferred in parallel (-P jobs) to use
    # more of the pipe. PARALLEL defaults to 2; override with `PARALLEL=N sync_run ...`.
    #
    # The 4th arg is a parallel on/off flag (default true). Pass `false` when the
    # destination is a USB / local disk: there is no network latency to hide and
    # concurrent writes to a single drive just cause seek contention, so a single
    # sequential stream is faster.
    local instrument="${1:?Usage: sync_run <instrument> <run_id> [dest_base] [parallel]  (instrument: MiSeqi100 | NovaSeqx)}"
    local run_id="${2:?Usage: sync_run <instrument> <run_id> [dest_base] [parallel]}"
    local dest_base="${3:-/mnt/jbod_localdisk/nextshare/bcl_convert}"
    local parallel_enabled="${4:-true}"
    # Resolve run dir case-insensitively: the instrument dir on disk may be
    # cased differently than the arg (e.g. NovaSeqX vs NovaSeqx).
    local src="" base hit
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
        return 1
    fi
    # Use the on-disk canonical casing (args may differ, e.g. NovaSeqx vs
    # NovaSeqX) so the dest path matches the existing, writable share dirs.
    run_id=$(basename "$src")
    instrument=$(basename "$(dirname "$src")")
    local dest="${dest_base}/${instrument}/${run_id}"
    local parallel="${PARALLEL:-2}"

    mkdir -p "$dest"

    # Big payload: per-lane output/ subdirs transferred in parallel (when enabled).
    # Run rsync quietly here -- concurrent progress2 streams scramble each other on
    # the terminal -- and just announce each subdir as it starts. When parallel is
    # off, this branch is skipped and the single pass below copies output/ too.
    echo "[sync_run] src:      $src"
    echo "[sync_run] dest:     $dest"
    echo "[sync_run] parallel: $parallel_enabled (PARALLEL=$parallel)"
    echo "[sync_run] excluded from mirror (rebuilt there): .snakemake, Reports, logs/*link*"

    if [[ "$parallel_enabled" != "false" && -d "$src/output" ]]; then
        mkdir -p "$dest/output"
        echo "[sync_run] output/ subdirs to sync: $(ls "$src/output" | wc -l)"
        # Per-subdir start/finish lines with size and duration -- concurrent
        # rsync progress meters would scramble each other, so the transfers stay
        # quiet and each worker reports around its own rsync instead.
        ls "$src/output" | xargs -P"$parallel" -I{} \
            sh -c '
                started=$(date +%s)
                echo "[sync_run $(date +%H:%M:%S)] START  output/{} ($(du -sh "$1/output/{}" 2>/dev/null | cut -f1))"
                rsync -aWq "$1/output/{}" "$2/output/"
                finished=$(date +%s)
                echo "[sync_run $(date +%H:%M:%S)] DONE   output/{} in $(( (finished - started) / 60 ))m$(( (finished - started) % 60 ))s"
            ' _ "$src" "$dest"
        echo "[sync_run] output/ transfers complete"
    fi

    # Everything else (small, recreatable metadata) in a single pass.
    echo "[sync_run] syncing remaining run files (metadata, results, logs, configs)"
    rsync -aW --info=progress2 --stats -h \
        --exclude '.snakemake' \
        --exclude 'logs/*link*' \
        --exclude 'logs/**/*link*' \
        --exclude 'Reports' \
        "$src/" "$dest/"

    # Point the synced copy's config at the local JBOD share rather than the
    # dragen share, so publishing from this mirror lands in the right place.
    local cfg="$dest/snakemake_config_project.yaml"
    if [[ -f "$cfg" ]]; then
        sed -i \
            -e 's/^nextcloud_dir_name: .*/nextcloud_dir_name: "Jbod2"/' \
            -e 's/^nextcloud_dir_path: .*/nextcloud_dir_path: "nextshare"/' \
            "$cfg"
        echo "[sync_run] repointed $(basename "$cfg") at the Jbod2 share:"
        grep -E '^nextcloud_dir_(name|path):' "$cfg" | sed 's/^/[sync_run]   /'
    fi

    # Publish the resolved destination to the caller (publish_run.sh runs the
    # post-sync snakemake steps in the mirror, not in the source run dir).
    SYNC_RUN_DEST="$dest"
    echo "[sync_run] mirror ready: $dest"
}

# Allow direct execution: `bash scripts/sync_run.sh <instrument> <run_id> ...`
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    sync_run "$@"
fi
