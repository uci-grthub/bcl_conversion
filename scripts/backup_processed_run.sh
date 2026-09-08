#!/bin/bash
# processed_novaseqx_backup -- copy a PROCESSED run directory (FASTQs, reports,
# metadata, masking sweeps) from staging to HPC3.
#
#   processed_novaseqx_backup <run> [dest_base] [host]
#
#   <run>       run dir name under /staging/nextcloud/testing_illumina/<instrument>
#               (resolved case-insensitively across instruments), or an absolute
#               path to the run dir itself
#   dest_base   remote parent dir (default /dfs3b/ucightf_lab/NSProcessed); the
#               run dir is created as a NEW subdirectory inside it
#   host        ssh target (default hpc3 -- see ~/.ssh/config ControlMaster)
#
#   DRY_RUN=1      show what would transfer, move nothing
#   SKIP_SWEEPS=1  omit sweeps/ (masking-sweep variants)
#   KEEP_PIXI=1    include .pixi/ (~1.2 G of rebuildable environment)
#   BWLIMIT=50M    pass --bwlimit to rsync (shared uplink courtesy)
#
# example:
#   ssh -fN hpc3                                    # DUO once, then:
#   processed_novaseqx_backup xR112
#
# This is the processed-data counterpart to raw_novaseqx_backup (raw BCLs ->
# NSRaw) in ~/.bash_functions, and shares its SSH/sftp conventions: no -W, so an
# interrupted multi-terabyte copy resumes by delta rather than restarting every
# file; --partial --append-verify to keep the partial pieces; no -z because
# .fastq.gz/.cbcl are already compressed; remote checks via sftp because
# access-hpc3 permits no arbitrary remote commands.
#
# Unlike sync_run (local NFS) this does NOT fan output/ out across parallel
# rsyncs. rsync only preserves hardlinks among files it sees in ONE invocation,
# and a masking sweep hardlinks R1/I1/I2 from the run's own output/ into each
# variant under sweeps/ -- splitting the transfer would re-send each of those as
# a full copy. One pass with -H keeps them shared on the remote too. The single
# stream is also the right shape for SSH, where the bottleneck is the link and
# the cipher, not NFS round-trip latency.
# ---------------------------------------------------------------------------

processed_novaseqx_backup() {
    local run="${1:?Usage: processed_novaseqx_backup <run> [dest_base] [host]}"
    local dest_base="${2:-/dfs3b/ucightf_lab/NSProcessed}"
    local host="${3:-hpc3}"
    local src_base="/staging/nextcloud/testing_illumina"

    # Accept either a bare run dir name or an absolute path; strip any trailing
    # slash, since the nesting behaviour below depends on its absence.
    local src
    if [[ "$run" == /* ]]; then
        src="${run%/}"
    else
        # The instrument dir is not given (processed runs live under
        # <instrument>/<run_id>) and its casing on disk varies (NovaSeqX vs
        # NovaSeqx), so match case-insensitively the way sync_run does.
        src=$(find "$src_base" -maxdepth 2 -mindepth 2 -type d \
              -ipath "$src_base/*/${run%/}" -print -quit 2>/dev/null)
    fi

    if [[ -z "$src" || ! -d "$src" ]]; then
        echo "ERROR: run dir not found: ${run} (searched $src_base/*/)" >&2
        return 1
    fi

    # Refuse a run whose conversion has not delivered. Backing up mid-pipeline
    # produces a copy that looks complete and silently isn't -- the same failure
    # raw_novaseqx_backup guards with RTAComplete.txt. The processed equivalent is
    # the per-project md5sums.txt each delivered project gets at the end of
    # conversion; if none exists, nothing has been delivered yet.
    if ! compgen -G "$src/output/*/*/md5sums.txt" >/dev/null; then
        echo "ERROR: no output/*/*/md5sums.txt in $src -- run has not finished delivering" >&2
        return 1
    fi

    # A held snakemake lock means a run is in flight right now and outputs are
    # still being written; copying under it captures half-written FASTQs.
    if compgen -G "$src/.snakemake/locks/*" >/dev/null; then
        echo "ERROR: $src/.snakemake/locks is not empty -- a snakemake run is active" >&2
        echo "       wait for it to finish (or clear a stale lock) before backing up" >&2
        return 1
    fi

    # One multiplexed SSH connection carries every command below, so DUO is
    # answered once rather than per-rsync.
    if ! ssh -O check "$host" >/dev/null 2>&1; then
        echo "ERROR: no SSH master connection to '$host'." >&2
        echo "       Run 'ssh -fN $host' first and answer the DUO prompt." >&2
        return 1
    fi

    # access-hpc3 is a restricted transfer node: it serves rsync/scp/sftp but
    # rejects arbitrary remote commands ("Command '[' not allowed"), so the dest
    # check and free-space report both go through sftp rather than ssh. The lab
    # share is shared, so require the parent to exist rather than mkdir -p it --
    # a typo'd dest_base must fail, not litter a new directory.
    local remote_df
    if ! remote_df=$(printf 'cd "%s"\ndf -h .\n' "$dest_base" \
                     | sftp -b - "$host" 2>&1); then
        echo "ERROR: remote dest not reachable: ${host}:${dest_base}" >&2
        echo "$remote_df" | sed 's/^/[proc_backup]   /' >&2
        return 1
    fi

    local name dest
    name=$(basename "$src")
    dest="${dest_base}/${name}"

    # .pixi is a per-platform environment rebuilt from pixi.lock, which travels
    # with the run dir -- 1.2 G of binaries that are the one thing here nobody
    # needs a copy of. Everything else (metadata, logs, benchmarks, .snakemake
    # provenance, Reports) is small and is kept.
    local -a excludes=(--exclude '.DS_Store')
    [[ -z "${KEEP_PIXI:-}" ]] && excludes+=(--exclude '/.pixi')
    [[ -n "${SKIP_SWEEPS:-}" ]] && excludes+=(--exclude '/sweeps')

    local -a rsync_opts=(-a -H --partial --append-verify)
    [[ -n "${BWLIMIT:-}" ]] && rsync_opts+=(--bwlimit="$BWLIMIT")

    echo "[proc_backup] src:  $src ($(du -sh "$src" 2>/dev/null | cut -f1))"
    echo "[proc_backup] dest: ${host}:${dest}"
    echo "[proc_backup] excluded: ${excludes[*]}"
    echo "[proc_backup] hardlinks preserved (-H) across output/ and sweeps/ in one pass"
    echo "$remote_df" | grep -vE '^sftp>' | sed 's/^/[proc_backup] df: /'

    if [[ -n "${DRY_RUN:-}" ]]; then
        echo "[proc_backup] DRY_RUN -- no data will be transferred"
        rsync -anH --itemize-changes "${excludes[@]}" "$src" "${host}:${dest_base}/"
        return $?
    fi

    if ! rsync "${rsync_opts[@]}" --info=progress2 --stats -h \
        "${excludes[@]}" "$src" "${host}:${dest_base}/"
    then
        echo "[proc_backup] ERROR: transfer failed -- rerun to resume" >&2
        return 1
    fi

    # Verify by re-running as a dry run: anything still listed did not land.
    # No --delete here; this must never be able to remove anything on the share.
    echo "[proc_backup] verifying..."
    local diff
    diff=$(rsync -anH --itemize-changes "${excludes[@]}" "$src" "${host}:${dest_base}/")
    if [[ -n "$diff" ]]; then
        echo "[proc_backup] ERROR: mirror incomplete, still differing:" >&2
        echo "$diff" | head -20 >&2
        return 1
    fi

    echo "[proc_backup] complete and verified: ${host}:${dest}"
}

# Allow direct execution: `bash scripts/backup_processed_run.sh <run> ...`
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    processed_novaseqx_backup "$@"
fi
