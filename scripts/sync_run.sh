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
    echo "[sync_run] hardlinks preserved within the sequential pass (-H); across passes, see dedupe_mirror.py"

    if [[ "$parallel_enabled" != "false" && -d "$src/output" ]]; then
        mkdir -p "$dest/output"
        echo "[sync_run] output/ subdirs to sync: $(ls "$src/output" | wc -l)"
        # Per-subdir start/finish lines with size and duration -- concurrent
        # rsync progress meters would scramble each other, so the transfers stay
        # quiet and each worker reports around its own rsync instead.
        #
        # Each worker returns its rsync's exit status, and xargs exits non-zero if
        # any of them failed. Without this the worker printed DONE regardless, the
        # failure scrolled past in a parallel log, and publish_run.sh went on to
        # --touch the missing outputs current and mail links for them.
        if ! ls "$src/output" | xargs -P"$parallel" -I{} \
            sh -c '
                started=$(date +%s)
                echo "[sync_run $(date +%H:%M:%S)] START  output/{} ($(du -sh "$1/output/{}" 2>/dev/null | cut -f1))"
                rsync -aWq "$1/output/{}" "$2/output/"
                status=$?
                if [ "$status" -ne 0 ]; then
                    echo "[sync_run $(date +%H:%M:%S)] FAILED output/{} (rsync exit $status)" >&2
                    exit "$status"
                fi
                finished=$(date +%s)
                echo "[sync_run $(date +%H:%M:%S)] DONE   output/{} in $(( (finished - started) / 60 ))m$(( (finished - started) % 60 ))s"
            ' _ "$src" "$dest"
        then
            echo "[sync_run] ERROR: at least one output/ subdir failed to transfer (see FAILED lines above)" >&2
            return 1
        fi
        echo "[sync_run] output/ transfers complete"
    fi

    # Everything else (small, recreatable metadata) in a single pass -- plus
    # sweeps/, which is not small: a masking sweep hardlinks R1/I1/I2 into each
    # variant because only R2 differs between maskings. -H keeps those shared here
    # instead of writing one full copy per variant (209G -> 96.5G for three
    # variants of one lane). It cannot reach across to output/, which the parallel
    # branch above transfers in separate rsync invocations -- rsync only preserves
    # links among files it sees in a single run. dedupe_mirror.py collapses the
    # rest afterwards, against the delivery those variants were seeded from.
    echo "[sync_run] syncing remaining run files (metadata, results, sweeps, logs, configs)"
    #
    # The Reports excludes are ANCHORED (leading /). An unanchored 'Reports' matches
    # a directory of that name at any depth, which also stripped every
    # output/<lane>/Reports/ under sweeps/ -- the DRAGEN demux reports. The run's own
    # output/ survived only because the parallel branch above transfers it with no
    # excludes at all; the sweeps have no such reprieve, and generate_report.py then
    # found no Demultiplex_Stats.csv and printed "N/A" for every sample's paired
    # reads. Only the top-level order reports are meant to be excluded here, for the
    # run and for each variant, because publish rebuilds those in the mirror.
    if ! rsync -aWH --info=progress2 --stats -h \
        --exclude '.snakemake' \
        --exclude 'logs/*link*' \
        --exclude 'logs/**/*link*' \
        --exclude '/Reports' \
        --exclude '/sweeps/*/Reports' \
        "$src/" "$dest/"
    then
        echo "[sync_run] ERROR: rsync of the remaining run files failed" >&2
        return 1
    fi

    # Point the synced copy's config at the local JBOD share rather than the
    # dragen share, so publishing from this mirror lands in the right place.
    #
    # Masking-sweep variants carry their own copy of this file, and the Snakefile
    # loads it by a relative path, so `snakemake -d <variant>` reads the variant's
    # copy and not the run root's. Repoint those too, or a variant's project_link
    # mints its share against the dragen storage and mails a link into the wrong
    # place entirely.
    local cfg
    for cfg in "$dest/snakemake_config_project.yaml" \
               "$dest"/sweeps/*/snakemake_config_project.yaml; do
        [[ -f "$cfg" ]] || continue
        sed -i \
            -e 's/^nextcloud_dir_name: .*/nextcloud_dir_name: "Jbod2"/' \
            -e 's/^nextcloud_dir_path: .*/nextcloud_dir_path: "nextshare"/' \
            "$cfg"
        echo "[sync_run] repointed ${cfg#"$dest"/} at the Jbod2 share"
    done

    # rsync copies a symlink verbatim, target string and all, so a masking sweep's
    # Snakefile/src/scripts/profiles links in the mirror still point into the source
    # run directory. They dangle the moment staging is cleared, which breaks any
    # attempt to re-run snakemake inside a mirrored variant. Repoint them at the
    # mirror, relatively, so the share is self-contained.
    echo "[sync_run] repointing sweep symlinks at the mirror"
    bash "$(dirname "${BASH_SOURCE[0]}")/relink_mirror.sh" "$dest" --apply \
        | sed 's/^/[sync_run]   /'

    # Publish the resolved source and destination to the caller (publish_run.sh
    # runs the post-sync snakemake steps in the mirror, not in the source run dir,
    # and verifies the mirror against the source before touching anything).
    SYNC_RUN_DEST="$dest"
    SYNC_RUN_SRC="$src"
    echo "[sync_run] mirror ready: $dest"
}

# Allow direct execution: `bash scripts/sync_run.sh <instrument> <run_id> ...`
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    sync_run "$@"
fi
