#!/bin/bash
# Script to monitor a directory for CopyComplete.txt and trigger Snakemake
# Reads the directory path from snakemake_config_project.yaml (key: data_dir)

set -e

# Resolve the pixi binary. cron runs with a minimal PATH, so fall back to the
# default install location under $HOME when pixi is not already on PATH.
PIXI="$(command -v pixi 2>/dev/null || true)"
[ -z "$PIXI" ] && PIXI="$HOME/.pixi/bin/pixi"

cd "$(realpath "$(dirname "$0")")"

CONFIG_FILE="snakemake_config_project.yaml"
MONITOR_DIR=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE')).get('data_dir', ''))" 2>/dev/null)

if [ -z "$MONITOR_DIR" ]; then
  echo "data_dir not set in $CONFIG_FILE. Exiting."
  exit 1
fi

TARGET_FILE="$MONITOR_DIR/CopyComplete.txt"

if [ -f "$TARGET_FILE" ]; then
  echo "Found $TARGET_FILE. Triggering Snakemake in tmux session."
  LIBRARY=$(python3 -c "import yaml; print(yaml.safe_load(open('snakemake_config_project.yaml')).get('library_name', 'snakemake'))")
  # Check if tmux session already exists
  if tmux has-session -t "$LIBRARY" 2>/dev/null; then
    echo "tmux session $LIBRARY already exists. Not starting a new one."
  else
    # Start tmux session: source .env, run snakemake under pixi, then drop into an activated shell
    tmux new-session -d -c "$(pwd)" -s "$LIBRARY" "if [ -f ../.env ]; then source ../.env; fi; $PIXI run snakemake --profile default -p; exec $PIXI run bash"
    if [ $? -ne 0 ]; then
      echo "Failed to start tmux session $LIBRARY."
    else
      echo "Started tmux session $LIBRARY."
    fi
  fi
else
  echo "$TARGET_FILE not found. No action taken."
fi