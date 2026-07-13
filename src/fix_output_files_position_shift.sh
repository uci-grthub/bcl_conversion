#!/bin/bash
# Fix output file position shifts caused by upstream lane changes
# Corrects files in lanes 2-4 when lane1 samples are removed/added

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Change to project directory
cd "$PROJECT_DIR"

# Display help
show_help() {
    cat << EOF
Fix output file position shifts caused by upstream lane changes

Usage:
    $(basename "$0") [options]

Options:
    --dry-run       Show what would be changed without making changes
    --verbose       Show detailed information about each file
    --help          Show this help message

Examples:
    $(basename "$0") --dry-run            # Preview changes without applying
    $(basename "$0")                      # Apply all changes
    $(basename "$0") --dry-run --verbose  # Detailed preview

Description:
    When samples are removed from lane1 (e.g., M24_VDJ/GEX removed, 12->10 samples),
    the regenerated renaming maps shift all lane2+ positions down by that offset.
    
    This script corrects output files that were renamed using the old maps by:
    1. Analyzing position mismatches
    2. Detecting consistent offsets
    3. Renaming files to match new renaming maps

For more information, see: docs/position_shift_fixer_README.md
EOF
    exit 0
}

# Check for help flag
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
fi

# Verify we're in the correct directory
if [[ ! -f "snakemake_config_project.yaml" ]]; then
    echo "Error: Not in project root directory"
    echo "Expected to find: snakemake_config_project.yaml"
    exit 1
fi

echo "Position Shift Fixer for FASTQ Files"
echo "====================================="
echo ""

# Check if dry-run mode
if [[ "$*" == *"--dry-run"* ]]; then
    echo "Mode: DRY RUN (no files will be changed)"
else
    echo "Mode: LIVE (files will be renamed)"
    echo "Use --dry-run to preview changes first"
fi
echo ""

# Verify output directories exist
if [[ ! -d "output" ]]; then
    echo "Error: output/ directory not found"
    exit 1
fi

# Verify renaming maps exist
MISSING_MAPS=0
for lane in 2 3 4; do
    if [[ ! -f "results/renaming_map_lane${lane}.csv" ]]; then
        echo "Warning: renaming_map_lane${lane}.csv not found"
        MISSING_MAPS=$((MISSING_MAPS + 1))
    fi
done

if [[ $MISSING_MAPS -eq 3 ]]; then
    echo "Error: No renaming maps found. Cannot proceed."
    exit 1
fi

echo "Running position shift fixer..."
echo ""

# Prefer the pixi-provisioned environment; fall back to system Python.
# Resolve pixi even under a minimal PATH (e.g. cron) via the default install location.
PIXI="$(command -v pixi 2>/dev/null || true)"
[ -z "$PIXI" ] && [ -x "$HOME/.pixi/bin/pixi" ] && PIXI="$HOME/.pixi/bin/pixi"
if [ -n "$PIXI" ]; then
    echo "Using pixi environment"
    "$PIXI" run python3 src/fix_output_files_position_shift.py "$@"
else
    echo "Using system Python"
    python3 src/fix_output_files_position_shift.py "$@"
fi

EXIT_CODE=$?

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Script completed successfully"
else
    echo "Script exited with error code: $EXIT_CODE"
    exit $EXIT_CODE
fi
