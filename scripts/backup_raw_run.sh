#!/bin/bash
# raw_novaseqx_backup -- copy a raw run directory (BCLs) to HPC3.
#
# Vendored into this repo (previously lived only in the operator's
# ~/.bash_functions) so backups work from a fresh clone with no dotfile setup,
# alongside its processed-data counterpart in scripts/backup_processed_run.sh.
#
#   raw_novaseqx_backup [run] [dest_base] [host]
#
#   [run]       one of:
#                 - omitted: read data_dir from ./snakemake_config_project.yaml,
#                   i.e. back up the raw run THIS processed run was converted from
#                 - a raw run dir name (20260903_LH00626_0128_B257W5HLT4),
#                   resolved under /staging/nextcloud/{NovaseqX,Miseqi100,Miseq}
#                 - an absolute path to the run dir itself
#   dest_base   remote parent dir (default /dfs3b/ucightf_lab/NSRaw); the run
#               dir is created as a NEW subdirectory inside it
#   host        ssh target (default hpc3 -- see ~/.ssh/config ControlMaster)
#
#   DRY_RUN=1              show what would transfer, move nothing
#   KEEP_THUMBNAILS=1      include Thumbnail_Images (~2.6 G, excluded by default)
#   BWLIMIT=50M            pass --bwlimit to rsync (shared uplink courtesy)
#   BACKUP_GROUP=ucightf   group to own the copy on the share (empty to disable)
#
# example:
#   ssh -fN hpc3                                    # DUO once, then:
#   raw_novaseqx_backup                             # from the run dir
#   raw_novaseqx_backup 20260826_LH00626_0126_A257TG5LT4
#
# Notes: unlike sync_run (local NFS) this deliberately does NOT use -W -- over
# SSH that would discard delta transfer and make a resume restart every file.
# --partial --append-verify makes an interrupted 1.2 T copy restartable. No -z:
# .cbcl/.gz are already compressed. Remote checks use sftp because access-hpc3
# permits no arbitrary remote commands.
# ---------------------------------------------------------------------------

# Report the group the copy actually landed in. sftp because access-hpc3 refuses
# arbitrary remote commands; `ls -l` on the PARENT, because sftp's ls on a
# directory lists its contents rather than the directory itself.
#
# A warning, never a failure: the data is transferred and verified by the time
# this runs, and a wrong group is a permissions problem to fix, not a reason to
# report a completed multi-terabyte backup as failed.
_backup_report_group() {
    local host="$1" dest_base="$2" name="$3" want="$4" tag="$5"
    [[ -n "$want" ]] || return 0

    local listing got
    if ! listing=$(printf 'ls -l "%s"\n' "$dest_base" | sftp -b - "$host" 2>&1); then
        echo "[$tag] WARNING: could not list ${host}:${dest_base} to confirm the group" >&2
        return 0
    fi
    # drwxrws--- 5 user group ... name
    got=$(echo "$listing" | awk -v n="$name" '$NF == n {print $4; exit}')
    if [[ -z "$got" ]]; then
        echo "[$tag] WARNING: $name not found in the listing of $dest_base" >&2
    elif [[ "$got" != "$want" ]]; then
        echo "[$tag] WARNING: ${name} is group '${got}', expected '${want}'" >&2
        echo "[$tag]          the transferring account may not be a member of ${want}" >&2
    else
        echo "[$tag] group:    $name is group '$got' on the share"
    fi
}

raw_novaseqx_backup() {
    local run="${1:-}"
    local dest_base="${2:-/dfs3b/ucightf_lab/NSRaw}"
    local host="${3:-hpc3}"
    local backup_group="${BACKUP_GROUP-ucightf}"

    # No run given: take it from the processed run dir we were invoked in. Its
    # snakemake_config_project.yaml records the raw run that was converted, so
    # `pixi run backup-raw` from a run dir backs up that run's BCLs with no
    # 30-character dir name to retype (or mistype).
    local src=""
    if [[ -z "$run" ]]; then
        local cfg="$PWD/snakemake_config_project.yaml"
        if [[ ! -f "$cfg" ]]; then
            echo "ERROR: no run given and no snakemake_config_project.yaml in $PWD" >&2
            echo "       pass a raw run dir name or path explicitly" >&2
            return 1
        fi
        src=$(sed -n 's/^data_dir: *"\?\([^"]*\)"\? *$/\1/p' "$cfg" | tail -1)
        if [[ -z "$src" ]]; then
            echo "ERROR: no data_dir in $cfg" >&2
            return 1
        fi
        src="${src%/}"
        echo "[raw_backup] run from data_dir in ${cfg#"$PWD"/}: $src"
    elif [[ "$run" == /* ]]; then
        # Accept an absolute path; strip any trailing slash, since the nesting
        # behaviour below depends on its absence.
        src="${run%/}"
    else
        # A bare run dir name: the instrument dir is not part of it, so look
        # through the raw staging bases in turn.
        local base
        for base in /staging/nextcloud/NovaseqX /staging/nextcloud/Miseqi100 \
                    /staging/nextcloud/Miseq; do
            if [[ -d "${base}/${run%/}" ]]; then
                src="${base}/${run%/}"
                break
            fi
        done
        if [[ -z "$src" ]]; then
            echo "ERROR: run dir not found: ${run} (searched /staging/nextcloud/{NovaseqX,Miseqi100,Miseq})" >&2
            return 1
        fi
    fi

    if [[ ! -d "$src" ]]; then
        echo "ERROR: run dir not found: $src" >&2
        return 1
    fi

    # Refuse a run the sequencer is still writing. Backing up a partial run
    # produces a copy that looks complete and silently isn't.
    local marker
    for marker in RTAComplete.txt CopyComplete.txt; do
        if [[ ! -f "$src/$marker" ]]; then
            echo "ERROR: $marker missing in $src -- run not finished copying" >&2
            return 1
        fi
    done

    # One multiplexed SSH connection carries every command below, so DUO is
    # answered once rather than per-rsync.
    if ! ssh -O check "$host" >/dev/null 2>&1; then
        echo "ERROR: no SSH master connection to '$host'." >&2
        echo "       Run 'ssh -fN $host' first and answer the DUO prompt." >&2
        return 1
    fi

    # access-hpc3 is a restricted transfer node: it serves rsync/scp/sftp but
    # rejects arbitrary remote commands ("Command '[' not allowed"), so the
    # dest check and free-space report both go through sftp rather than ssh.
    # The lab share is shared, so require the parent to exist rather than
    # mkdir -p it -- a typo'd dest_base must fail, not litter a new directory.
    local remote_df
    if ! remote_df=$(printf 'cd "%s"\ndf -h .\n' "$dest_base" \
                     | sftp -b - "$host" 2>&1); then
        echo "ERROR: remote dest not reachable: ${host}:${dest_base}" >&2
        echo "$remote_df" | sed 's/^/[raw_backup]   /' >&2
        return 1
    fi

    local name dest
    name=$(basename "$src")
    dest="${dest_base}/${name}"

    local -a excludes=()
    [[ -z "${KEEP_THUMBNAILS:-}" ]] && excludes+=(--exclude 'Thumbnail_Images')

    # The copy has to land in the lab group so anyone in ucightf can read it.
    # -a preserves the source group, and 'grthcloud' means nothing on HPC3, so
    # without this every file arrives owned by the transferring user's default
    # group and the share is a backup only that one person can use.
    #
    # This has to be an rsync option rather than a chgrp afterwards: access-hpc3
    # is a restricted transfer node and refuses arbitrary remote commands, which
    # is the same reason the checks above go through sftp.
    #
    # It goes on EVERY rsync here, including the verification pass. That pass
    # re-runs the transfer as a dry run and treats any remaining output as
    # missing data -- so if it did not also map the group, it would see a group
    # it wants to change on every file and report a complete backup as broken.
    local -a group_opts=()
    if [[ -n "$backup_group" ]]; then
        if ! rsync --help 2>&1 | grep -q -- '--chown'; then
            echo "ERROR: rsync $(rsync --version | head -1 | awk '{print $3}') has no --chown (needs 3.1.0+)" >&2
            echo "       set BACKUP_GROUP= to transfer without setting the group" >&2
            return 1
        fi
        group_opts=(--chown=":$backup_group")
    fi

    local -a rsync_opts=(-a --partial --append-verify)
    [[ -n "${BWLIMIT:-}" ]] && rsync_opts+=(--bwlimit="$BWLIMIT")

    echo "[raw_backup] src:  $src ($(du -sh "$src" 2>/dev/null | cut -f1))"
    echo "[raw_backup] dest: ${host}:${dest}"
    echo "[raw_backup] excluded: ${excludes[*]:-none}"
    echo "[raw_backup] group:    ${backup_group:-<source group, unmapped>}"
    echo "$remote_df" | grep -vE '^sftp>' | sed 's/^/[raw_backup] df: /'

    if [[ -n "${DRY_RUN:-}" ]]; then
        echo "[raw_backup] DRY_RUN -- no data will be transferred"
        rsync -an --itemize-changes "${group_opts[@]}" "${excludes[@]}" \
            "$src" "${host}:${dest_base}/"
        return $?
    fi

    if ! rsync "${rsync_opts[@]}" --info=progress2 --stats -h \
        "${group_opts[@]}" "${excludes[@]}" "$src" "${host}:${dest_base}/"
    then
        echo "[raw_backup] ERROR: transfer failed -- rerun to resume" >&2
        return 1
    fi

    # Verify by re-running as a dry run: anything still listed did not land.
    # No --delete here; this must never be able to remove anything on the share.
    echo "[raw_backup] verifying..."
    local diff
    diff=$(rsync -an --itemize-changes "${group_opts[@]}" "${excludes[@]}" \
           "$src" "${host}:${dest_base}/")
    if [[ -n "$diff" ]]; then
        echo "[raw_backup] ERROR: mirror incomplete, still differing:" >&2
        echo "$diff" | head -20 >&2
        return 1
    fi

    _backup_report_group "$host" "$dest_base" "$name" "$backup_group" raw_backup

    echo "[raw_backup] complete and verified: ${host}:${dest}"
}

# Allow direct execution: `bash scripts/backup_raw_run.sh [run] ...`
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    raw_novaseqx_backup "$@"
fi
