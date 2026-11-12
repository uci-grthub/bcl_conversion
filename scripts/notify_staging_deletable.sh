#!/usr/bin/env bash
# Email once per run when its staging copies are safe to delete by hand.
#
# A run dir (/staging/nextcloud/testing_illumina/<instrument>/<run_id>) qualifies
# when run_and_backup_when_ready.sh has finished everything:
#   .published_ok               all + publish succeeded (processed run mirrored to JBOD)
#   .post_raw_backup.done       raw BCL run copied to HPC3
#   .post_processed_backup.done processed run copied to HPC3
# The email lists the processed run dir and the raw run dir (data_dir from the
# run's snakemake_config_project.yaml), with sizes and the rm commands. Nothing is
# deleted here. .delete_notified in the run dir stops repeat emails; remove it to
# get the email again.
#
# Cron (hourly):
#   50 * * * * /staging/nextcloud/testing_illumina/.src/notify_staging_deletable.sh >> /staging/nextcloud/testing_illumina/.src/notify_staging_deletable.log 2>&1

set -uo pipefail

STAGING_ROOT="/staging/nextcloud/testing_illumina"
SEND_EMAIL_PY="$STAGING_ROOT/.src/send_email.py"
ENV_FILE="$STAGING_ROOT/.env"
SENDER="kstachel@uci.edu"
RECIPIENT="kstachel@uci.edu"

# Secrets: the shared $ENV_FILE has no GMAIL_APP_PASSWORD; it lives in ~/.env,
# the same per-user file scripts/load_dotenv.sh reads for the pipeline. Load both
# (~/.env wins) and export everything, so send_email.py sees the password.
set -a
for f in "$ENV_FILE" "$HOME/.env"; do [ -f "$f" ] && . "$f"; done
set +a

shopt -s nullglob
for run_dir in "$STAGING_ROOT"/*/xR*/; do
  run_dir="${run_dir%/}"
  [ -f "$run_dir/.published_ok" ] || continue
  [ -f "$run_dir/.post_raw_backup.done" ] || continue
  [ -f "$run_dir/.post_processed_backup.done" ] || continue
  [ -f "$run_dir/.delete_notified" ] && continue

  run_id="$(basename "$run_dir")"
  raw_dir="$(sed -n 's/^data_dir:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' \
    "$run_dir/snakemake_config_project.yaml" 2>/dev/null | head -1)"

  proc_size="$(du -sh "$run_dir" 2>/dev/null | cut -f1)"
  raw_size="n/a"
  [ -n "$raw_dir" ] && [ -d "$raw_dir" ] && raw_size="$(du -sh "$raw_dir" 2>/dev/null | cut -f1)"
  read -r df_size df_used df_avail df_pct < <(df -h /staging | awk 'NR==2 {print $2, $3, $4, $5}')

  body="$(mktemp /tmp/staging_deletable_XXXXXX.html)"
  cat > "$body" <<HTML
<html><body style="font-family:Arial,sans-serif;font-size:14px">
<p><b>${run_id}</b> is published to the JBOD and backed up to HPC3 (raw + processed).
Its staging copies can be deleted by hand.</p>
<p>/staging: ${df_used} used of ${df_size}, ${df_avail} free (${df_pct})</p>
<table border="1" cellpadding="6" style="border-collapse:collapse">
<tr><th>What</th><th>Path</th><th>Size</th></tr>
<tr><td>Processed run</td><td><code>${run_dir}</code></td><td>${proc_size}</td></tr>
<tr><td>Raw run</td><td><code>${raw_dir:-not found}</code></td><td>${raw_size}</td></tr>
</table>
<p>Check the JBOD copy, then:</p>
<pre>rm -rf ${run_dir}
rm -rf ${raw_dir:-&lt;raw dir&gt;}</pre>
</body></html>
HTML

  if python3 "$SEND_EMAIL_PY" "$SENDER" "$RECIPIENT" "[BCL Convert] ${run_id} staging copies ready to delete" "$body"; then
    touch "$run_dir/.delete_notified"
    echo "$(date) notified ${run_id}"
  else
    echo "$(date) email FAILED for ${run_id}; will retry next tick"
  fi
  rm -f "$body"
done
