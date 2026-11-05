#!/usr/bin/env bash
# Delete a processed run dir from staging once every copy of it is confirmed.
#
#   delete_staged_run.sh <run_dir> <usb_base>
#   e.g. delete_staged_run.sh /staging/nextcloud/testing_illumina/NovaSeqX/xR125 /mnt/extusb3
#
# Deletes <run_dir> only when ALL of these hold; otherwise logs why and exits 0,
# so the next cron tick tries again:
#   - <run_dir> is /staging/nextcloud/testing_illumina/<instrument>/xR<digits>
#   - run_and_backup_when_ready.sh finished every step: .published_ok,
#     .post_raw_backup.done, .post_processed_backup.done, .post_usb_sync.done
#   - nothing is still running in it (.auto_launch.lock, .post_publish.lock free;
#     both stay held through the delete)
#   - scripts/verify_mirror.py passes for the JBOD mirror and the USB copy
#     (every FASTQ in md5sums.txt present, sizes match the staging source)
#   - <usb_base> is a mountpoint
# Before deleting it writes <instrument dir>/.<run_id>.deleted (a tombstone the
# next run's cron gate can check) and keeps a copy of logs/cron_run.log as
# <instrument dir>/.<run_id>.cron_run.log.
#
# Only the processed run dir is deleted. The raw run dir under
# /staging/nextcloud/NovaseqX stays a manual delete (see notify_staging_deletable.sh).
#
# Test-only overrides: STAGING_ROOT, JBOD_BASE, SKIP_MOUNT_CHECK=1.

set -uo pipefail

STAGING_ROOT="${STAGING_ROOT:-/staging/nextcloud/testing_illumina}"
JBOD_BASE="${JBOD_BASE:-/mnt/jbod_localdisk/nextshare/bcl_convert}"

log() { echo "$(date) [delete_staged_run] $*"; }

arg_dir="${1:-}"
usb_base="${2:-}"
if [ -z "$arg_dir" ] || [ -z "$usb_base" ]; then
  log "usage: delete_staged_run.sh <run_dir> <usb_base>"; exit 2
fi

# Missing dir: already deleted (tombstone written) or never existed. Nothing to do.
if [ ! -d "$arg_dir" ]; then
  exit 0
fi

run_dir="$(realpath -e -- "$arg_dir")" || { log "cannot resolve $arg_dir"; exit 2; }
root="$(realpath -e -- "$STAGING_ROOT")" || { log "cannot resolve $STAGING_ROOT"; exit 2; }
run_id="$(basename "$run_dir")"
inst_dir="$(dirname "$run_dir")"
instrument="$(basename "$inst_dir")"

# Path guard: exactly <root>/<instrument>/xR<digits>, nothing else.
if [ "$(dirname "$inst_dir")" != "$root" ] || ! [[ "$run_id" =~ ^xR[0-9]+$ ]] || [ -z "$instrument" ]; then
  log "REFUSING: $run_dir is not $root/<instrument>/xR<digits>"; exit 2
fi

for m in .published_ok .post_raw_backup.done .post_processed_backup.done .post_usb_sync.done; do
  if [ ! -f "$run_dir/$m" ]; then
    log "$run_id: missing $m; not deleting yet"; exit 0
  fi
done

exec 8>>"$run_dir/.auto_launch.lock"
exec 9>>"$run_dir/.post_publish.lock"
if ! flock -n 8 || ! flock -n 9; then
  log "$run_id: a run/backup step still holds its lock; not deleting yet"; exit 0
fi

if [ "${SKIP_MOUNT_CHECK:-0}" != 1 ] && ! mountpoint -q -- "$usb_base"; then
  log "$run_id: $usb_base is not mounted; cannot verify USB copy; not deleting"; exit 0
fi

verifier="$run_dir/scripts/verify_mirror.py"
[ -f "$verifier" ] || { log "$run_id: $verifier missing; not deleting"; exit 0; }

jbod_mirror="$JBOD_BASE/$instrument/$run_id"
usb_mirror="$usb_base/$instrument/$run_id"
for mirror in "$jbod_mirror" "$usb_mirror"; do
  if [ ! -d "$mirror" ]; then
    log "$run_id: mirror $mirror not found; not deleting"; exit 0
  fi
  if ! python3 -I "$verifier" "$mirror" --src "$run_dir"; then
    log "$run_id: verify_mirror FAILED for $mirror; not deleting"; exit 0
  fi
  log "$run_id: verified $mirror"
done

tomb="$inst_dir/.$run_id.deleted"
{
  echo "deleted: $(date)"
  echo "source: $run_dir"
  echo "jbod_mirror: $jbod_mirror"
  echo "usb_mirror: $usb_mirror"
} > "$tomb" || { log "$run_id: cannot write $tomb; not deleting"; exit 0; }
[ -f "$run_dir/logs/cron_run.log" ] && cp -p "$run_dir/logs/cron_run.log" "$inst_dir/.$run_id.cron_run.log"

log "$run_id: all checks passed; deleting $run_dir"
if rm -rf -- "$run_dir"; then
  log "$run_id: deleted"
else
  log "$run_id: rm -rf reported errors; check $run_dir"
fi
