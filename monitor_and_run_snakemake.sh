#!/bin/bash
# Script to monitor a directory for CopyComplete.txt and trigger Snakemake
# Reads the directory path from snakemake_config_project.yaml (key: data_dir)

set -e

CONFIG_FILE="snakemake_config_project.yaml"
MONITOR_DIR=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE')).get('data_dir', ''))" 2>/dev/null)

if [ -z "$MONITOR_DIR" ]; then
  echo "data_dir not set in $CONFIG_FILE. Exiting."
  exit 1
fi

TARGET_FILE="$MONITOR_DIR/CopyComplete.txt"

if [ -f "$TARGET_FILE" ]; then
  echo "Found $TARGET_FILE. Triggering Snakemake in tmux session."
  cd "$(dirname "$0")"
  LIBRARY=$(python3 -c "import yaml; print(yaml.safe_load(open('snakemake_config_project.yaml')).get('library_name', 'snakemake'))")
  # Check if tmux session already exists
  if tmux has-session -t "$LIBRARY" 2>/dev/null; then
    echo "tmux session $LIBRARY already exists. Not starting a new one."
  else
    # Create a temporary rcfile that activates perl_env for the tmux shell
    RCFILE=$(mktemp)
    echo "source $(conda info --base)/etc/profile.d/conda.sh && conda activate perl_env" > "$RCFILE"
    # Start tmux session: source .env, activate perl_env, run snakemake, then start bash with rcfile
    tmux new-session -d -c "$(pwd)" -s "$LIBRARY" "if [ -f ../.env ]; then source ../.env; fi; source $(conda info --base)/etc/profile.d/conda.sh && conda activate perl_env && snakemake --profile default -np; exec bash --rcfile $RCFILE"
    if [ $? -ne 0 ]; then
      echo "Failed to start tmux session $LIBRARY."
      rm -f "$RCFILE"
    else
      echo "Started tmux session $LIBRARY."
      # Optionally, clean up the rcfile after tmux session ends (advanced: not implemented here)
    fi
    if [ $? -ne 0 ]; then
      echo "Failed to start tmux session $LIBRARY."
    else
      echo "Started tmux session $LIBRARY."
    fi
  fi
else
  echo "$TARGET_FILE not found. No action taken."
fi