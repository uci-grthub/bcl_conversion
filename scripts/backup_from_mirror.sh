#!/usr/bin/env bash
# Finish a run's backups from its JBOD mirror after the staging copy is deleted.
#
#   backup_from_mirror.sh <mirror_dir> <usb_base>
#   e.g. backup_from_mirror.sh /mnt/jbod_localdisk/nextshare/bcl_convert/NovaSeqX/xR125 /mnt/extusb3
#
# Same steps and markers as run_and_backup_when_ready.sh, but run inside the
# mirror (which is a full run dir: scripts/, snakemake_config_project.yaml):
#   1. raw_backup        scripts/backup_raw_run.sh (data_dir from the mirror's config;
#                        resumes a partial HPC3 copy via --append-verify)
#   2. processed_backup  scripts/backup_processed_run.sh <mirror_dir> (HPC3 dest is
#                        still NSProcessed/<run_id>)
#   3. usb_sync          scripts/sync_run.sh <instrument> <run_id> <usb_base> false,
#                        only while <usb_base> is mounted. sync_run resolves the
#                        staging copy first, so this refuses to run if one exists.
# Each step writes <mirror>/.post_<step>.done; a failed step retries next tick.
# When all three are done it emails once (.backup_done_notified) that the raw run
# dir can be deleted by hand.
#
# Cron:
#   */30 * 6-15 11 * /staging/nextcloud/testing_illumina/.src/backup_from_mirror.sh <mirror_dir> /mnt/extusb3 >> /staging/nextcloud/testing_illumina/.src/backup_from_mirror.log 2>&1

set -uo pipefail

STAGING_ROOT="/staging/nextcloud/testing_illumina"
SEND_EMAIL_PY="$STAGING_ROOT/.src/send_email.py"
ENV_FILE="$STAGING_ROOT/.env"
SENDER="kstachel@uci.edu"
RECIPIENT="kstachel@uci.edu"

mirror="${1:?usage: backup_from_mirror.sh <mirror_dir> <usb_base>}"
usb_base="${2:?usage: backup_from_mirror.sh <mirror_dir> <usb_base>}"
mirror="$(realpath -e -- "$mirror")" || exit 1
cd "$mirror" || exit 1
run_id="$(basename "$mirror")"
instrument="$(basename "$(dirname "$mirror")")"

log() { echo "$(date) [$run_id] $*"; }

if [ -d "$STAGING_ROOT/$instrument/$run_id" ]; then
  log "staging copy $STAGING_ROOT/$instrument/$run_id still exists; not backing up from the mirror"
  exit 0
fi

exec 8>>.post_publish.lock
flock -n 8 || exit 0

run_step() {
  local name="$1"; shift
  [ -f ".post_${name}.done" ] && return 0
  log "[$name] starting: $*"
  local rc=0
  "$@" || rc=$?
  if [ "$rc" -eq 0 ]; then
    touch ".post_${name}.done"
    log "[$name] done"
  else
    log "[$name] FAILED (exit $rc); will retry next tick"
  fi
}

run_step raw_backup       bash scripts/backup_raw_run.sh
run_step processed_backup bash scripts/backup_processed_run.sh "$mirror"
if mountpoint -q -- "$usb_base"; then
  run_step usb_sync bash scripts/sync_run.sh "$instrument" "$run_id" "$usb_base" false
elif [ ! -f .post_usb_sync.done ]; then
  log "[usb_sync] $usb_base not mounted; will retry next tick"
fi

for s in raw_backup processed_backup usb_sync; do
  [ -f ".post_${s}.done" ] || exit 0
done
[ -f .backup_done_notified ] && exit 0

raw_dir="$(sed -n 's/^data_dir:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' snakemake_config_project.yaml | head -1)"
raw_size="n/a"
[ -n "$raw_dir" ] && [ -d "$raw_dir" ] && raw_size="$(du -sh "$raw_dir" 2>/dev/null | cut -f1)"
# Secrets: the shared $ENV_FILE has no GMAIL_APP_PASSWORD; it lives in ~/.env,
# the same per-user file scripts/load_dotenv.sh reads for the pipeline. Load both
# (~/.env wins) and export everything, so send_email.py sees the password.
set -a
for f in "$ENV_FILE" "$HOME/.env"; do [ -f "$f" ] && . "$f"; done
set +a
body="$(mktemp /tmp/backup_from_mirror_XXXXXX.html)"
cat > "$body" <<HTML
<html><body style="font-family:Arial,sans-serif;font-size:14px">
<p><b>${run_id}</b> is fully backed up from its JBOD mirror <code>${mirror}</code>:
HPC3 raw, HPC3 processed, and USB (<code>${usb_base}</code>).</p>
<p>Its raw run dir can be deleted by hand (${raw_size}):</p>
<pre>rm -rf ${raw_dir:-&lt;raw dir&gt;}</pre>
</body></html>
HTML
if python3 "$SEND_EMAIL_PY" "$SENDER" "$RECIPIENT" "[BCL Convert] ${run_id} backups done; raw dir ready to delete" "$body"; then
  touch .backup_done_notified
  log "all backups done; email sent"
else
  log "all backups done; email FAILED, will retry next tick"
fi
rm -f "$body"
