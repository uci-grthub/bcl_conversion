#!/bin/bash
# Cron entry: run_when_ready.sh (wait for CopyComplete.txt, then `pixi run all`
# and `pixi run publish`, exactly once), followed by the run's backups:
#   1. HPC3 raw backup        (scripts/backup_raw_run.sh)
#   2. HPC3 processed backup  (scripts/backup_processed_run.sh <run_id>)
#   3. sync_run to a USB/local drive, only when a destination is given
#
#   run_and_backup_when_ready.sh [usb_dest_base] [parallel]
#     usb_dest_base  e.g. /mnt/extusb3; omit to skip the USB sync
#     parallel       sync_run's parallel flag (default false: right for a single
#                    USB drive, see scripts/sync_run.sh)
#
# The run dir is the directory this script lives in; instrument and run ID are
# taken from its path (.../<instrument>/<run_id>). The backup scripts open their
# own hpc3 SSH connection by key auth, so no interactive login is needed.
#
# The backups and sync run only after all + publish succeeded in some tick: that
# tick writes .published_ok. A failed all/publish leaves .auto_launched without
# .published_ok, so nothing is backed up from an unpublished run. Each step gets
# its own .post_<step>.done marker: a failed step is retried on the next tick,
# finished steps are skipped, and a failed backup never blocks the sync.
set -uo pipefail

RUN_DIR="$(realpath "$(dirname "$0")")"
cd "$RUN_DIR" || exit 1
RUN_ID="$(basename "$RUN_DIR")"
INSTRUMENT="$(basename "$(dirname "$RUN_DIR")")"
USB_DEST="${1:-}"
USB_PARALLEL="${2:-false}"

if [ ! -f .auto_launched ]; then
  ./run_when_ready.sh || { echo "$(date) run_when_ready.sh failed; backups skipped"; exit 1; }
  [ -f .auto_launched ] || exit 0   # still waiting for CopyComplete.txt
  touch .published_ok
fi
[ -f .published_ok ] || exit 0

# One copy at a time: the transfers outlast the 30-minute cron interval.
exec 8>.post_publish.lock
flock -n 8 || exit 0

run_step() {
  local name="$1"; shift
  [ -f ".post_${name}.done" ] && return 0
  echo "$(date) [$name] starting: $*"
  if "$@"; then
    touch ".post_${name}.done"
    echo "$(date) [$name] done"
  else
    echo "$(date) [$name] FAILED (exit $?); will retry next tick"
  fi
}

run_step raw_backup       bash scripts/backup_raw_run.sh
run_step processed_backup bash scripts/backup_processed_run.sh "$RUN_ID"
if [ -n "$USB_DEST" ]; then
  run_step usb_sync bash scripts/sync_run.sh "$INSTRUMENT" "$RUN_ID" "$USB_DEST" "$USB_PARALLEL"
fi
