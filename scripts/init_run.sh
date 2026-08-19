#!/bin/bash
# One-time per-run setup. Run once after cloning into a run-named directory:
#   pixi run init                      # sequencer inferred from the path
#   pixi run init --sequencer novaseqx # or: --sequencer miseqi100
#
# Idempotent: safe to re-run. It:
#   1. copies the newest .xlsx from ../SampleSheets into metadata/ (if present),
#   2. creates snakemake_config_project.yaml from the base config (if missing),
#   3. prefills metadata / library_name / data_dir in that project config.
# Review the result and fill .env (secrets) before running the workflow.

set -euo pipefail

# --- parse --sequencer ------------------------------------------------------
sequencer=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sequencer) sequencer="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Infer sequencer from working directory path if not provided
if [ -z "$sequencer" ]; then
    case "$(pwd)" in
        *MiSeqi100*|*Miseqi100*|*miseqi100*) sequencer="miseqi100" ;;
        *NovaSeq*|*Novaseq*|*novaseq*)       sequencer="novaseqx" ;;
    esac
fi

if [ -z "$sequencer" ]; then
    echo "ERROR: Could not determine sequencer type from path. Run with:"
    echo "  pixi run init --sequencer miseqi100"
    echo "  pixi run init --sequencer novaseqx"
    exit 1
fi

case "$sequencer" in
    miseqi100) staging_dir="/staging/nextcloud/Miseqi100" ;;
    novaseqx)  staging_dir="/staging/nextcloud/NovaseqX" ;;
    *)
        echo "ERROR: Unknown sequencer '$sequencer'. Use 'miseqi100' or 'novaseqx'."
        exit 1
        ;;
esac

# --- copy newest samplesheet from ../SampleSheets --------------------------
source_xlsx=$( { find ../SampleSheets -maxdepth 1 -name "*.xlsx" -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-; } || true)
if [ -n "$source_xlsx" ]; then
    mkdir -p metadata
    cp "$source_xlsx" metadata/
    echo "  Copied $source_xlsx --> metadata/"
else
    echo "  WARNING: No .xlsx found in ../SampleSheets"
fi

metadata_file=$( { find metadata/ -maxdepth 1 -name "*.xlsx" ! -name "metadata_validation*" 2>/dev/null | head -1; } || true)

# --- create project config from base (if missing) --------------------------
if [ ! -f snakemake_config_project.yaml ]; then
    cp snakemake_config.yaml snakemake_config_project.yaml
fi

# --- prefill metadata / library_name / data_dir ----------------------------
if [ -n "$metadata_file" ]; then
    sed -i "s|^metadata:.*|metadata: \"$metadata_file\"|" snakemake_config_project.yaml
    echo "  metadata --> $metadata_file"

    library_name=$(basename "$metadata_file" .xlsx | grep -oE '[ix]R[0-9]+' || true)
    if [ -n "$library_name" ]; then
        sed -i "s|^library_name:.*|library_name: \"$library_name\"|" snakemake_config_project.yaml
        echo "  library_name --> $library_name"
    else
        echo "  WARNING: Could not infer library_name from $metadata_file — set it manually."
    fi
else
    echo "  WARNING: No .xlsx found in metadata/ — set metadata and library_name manually."
fi

data_dir=$( { find "$staging_dir" -maxdepth 1 -mindepth 1 -type d -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-; } || true)
if [ -n "$data_dir" ]; then
    sed -i "s|^data_dir:.*|data_dir: \"$data_dir\"|" snakemake_config_project.yaml
    echo "  data_dir --> $data_dir"
else
    echo "  WARNING: Could not find newest dir in $staging_dir — set data_dir manually."
fi

echo "Ready: snakemake_config_project.yaml created/updated. Review it, then fill .env (cp .env.example .env)."
