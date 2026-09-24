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

DATA_DIR=$(python3 -c "import yaml; print(yaml.safe_load(open('snakemake_config_project.yaml')).get('data_dir', ''))")
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

touch .auto_launched
echo "$(date) CopyComplete.txt found; running pixi run all"
"$PIXI" run all
echo "$(date) all succeeded; running pixi run publish"
"$PIXI" run publish
echo "$(date) publish finished"
