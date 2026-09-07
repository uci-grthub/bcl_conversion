#!/bin/bash
# Wrapper for the full workflow run, used by the `all` pixi task.
#
# Snakemake's own log (.snakemake/log/) records rule-level events, but a spawned
# job's Python traceback goes to the driver's stderr and never reaches that file:
# when a `run:` directive raises, the log shows only SpawnedJobError with no clue
# which statement failed. monitor_and_run_snakemake.sh launches the driver inside
# tmux, so that traceback lives in pane scrollback and dies with the session.
# Tee the driver's own output to a file so the exception text survives.
#
# pipefail is load-bearing: without it the exit status is tee's (always 0) and a
# failed workflow would look successful to cron and to the tmux session.
set -o pipefail

log_dir="logs/driver"
mkdir -p "$log_dir"
log_file="$log_dir/snakemake_$(date +%Y-%m-%dT%H%M%S).log"

echo "Driver output tee'd to: $log_file"
snakemake --cores 8 "$@" 2>&1 | tee -a "$log_file"
