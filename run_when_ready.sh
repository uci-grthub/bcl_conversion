#!/bin/bash
# Cron entry: wait for CopyComplete.txt in data_dir, then run `pixi run all`
# followed by `pixi run publish`, exactly once.
#
# The .auto_launched sentinel is load-bearing: publish clears the email receipts
# and re-sends every order email, so a second launch would re-mail customers.
# Delete it only to deliberately re-run the whole thing.
set -euo pipefail

# cron runs with a minimal PATH; fall back to the default pixi install location.
PIXI="$(command -v pixi 2>/dev/null || echo "$HOME/.pixi/bin/pixi")"

cd "$(realpath "$(dirname "$0")")"

# Read the config with the project's pixi Python, not whatever python3 is first on
# PATH: an interactive shell can put a python3 without PyYAML (e.g. miniforge)
# ahead of /usr/bin/python3, and the launch then dies before it starts.
DATA_DIR=$("$PIXI" run --frozen python -c "import yaml; print(yaml.safe_load(open('snakemake_config_project.yaml')).get('data_dir', ''))")
if [ -z "$DATA_DIR" ]; then
  echo "$(date) data_dir not set in snakemake_config_project.yaml. Exiting."
  exit 1
fi

if [ -f .auto_launched ]; then
  exit 0
fi
if [ ! -f "$DATA_DIR/CopyComplete.txt" ]; then
  echo "$(date) waiting for $DATA_DIR/CopyComplete.txt"
  exit 0
fi

# Keep a later hourly tick from starting a second copy while this one runs.
exec 9>.auto_launch.lock
flock -n 9 || exit 0

# Run order: WAIT_FOR=<previous run dir> (set in the crontab line) holds this run
# until that run's `pixi run all` has succeeded (.all_ok). A failed predecessor
# never writes .all_ok, so its successors wait until someone fixes it.
if [ -n "${WAIT_FOR:-}" ] && [ ! -f "$WAIT_FOR/.all_ok" ]; then
  echo "$(date) waiting for $WAIT_FOR to finish pixi run all"
  exit 0
fi

# One `pixi run all` per host at a time, across all run dirs. Held only for
# `all`: it is released before publish, so the next run can start converting
# while this one publishes and backs up.
PIPELINE_LOCK="${PIPELINE_LOCK:-/staging/nextcloud/testing_illumina/.pipeline_all.lock}"
touch "$PIPELINE_LOCK" 2>/dev/null && chmod a+rw "$PIPELINE_LOCK" 2>/dev/null || true
exec 7<"$PIPELINE_LOCK"
if ! flock -n 7; then
  echo "$(date) another run holds $PIPELINE_LOCK (pixi run all in progress); waiting"
  exit 0
fi

touch .auto_launched
echo "$(date) CopyComplete.txt found; running pixi run all"
"$PIXI" run all
touch .all_ok
flock -u 7
exec 7<&-
echo "$(date) all succeeded; running pixi run publish"
"$PIXI" run publish
echo "$(date) publish finished"
