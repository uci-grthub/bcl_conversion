#!/bin/bash

# Wrapper script to rename FASTQs using the python script
# Usage: ./src/run_rename.sh <config_id> <output_dir> <map_file>

CONFIG_ID=$1
OUTPUT_DIR=$2
MAP_FILE=$3

# Determine the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
RENAME_SCRIPT="${SCRIPT_DIR}/rename_fastqs.py"

if [ -z "$CONFIG_ID" ] || [ -z "$OUTPUT_DIR" ] || [ -z "$MAP_FILE" ]; then
    echo "Usage: $0 <config_id> <output_dir> <map_file>"
    exit 1
fi

if [ ! -f "$RENAME_SCRIPT" ]; then
    echo "Error: $RENAME_SCRIPT not found."
    exit 1
fi

# Check if map file exists
if [ ! -f "$MAP_FILE" ]; then
    echo "Map file $MAP_FILE not found. Skipping renaming."
    exit 0
fi

echo "Running renaming logic for config $CONFIG_ID..."
python3 "$RENAME_SCRIPT" "$CONFIG_ID" "$OUTPUT_DIR" "$MAP_FILE"

# Also rename downstream results (fastp outputs and plots) to match conventions
PIPELINE_RENAME_SCRIPT="${SCRIPT_DIR}/rename_pipeline_outputs.py"
if [ -f "$PIPELINE_RENAME_SCRIPT" ]; then
    echo "Renaming downstream outputs for config $CONFIG_ID..."
    python3 "$PIPELINE_RENAME_SCRIPT" "$CONFIG_ID" "$OUTPUT_DIR" "$MAP_FILE" --results-base results || true
fi
