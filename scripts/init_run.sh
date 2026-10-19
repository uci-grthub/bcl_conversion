#!/bin/bash
# One-time per-run setup. Run once after cloning into a run-named directory:
#   pixi run init                      # sequencer inferred from the path
#   pixi run init --sequencer novaseqx # or: --sequencer miseqi100 / miseq
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
        # after miseqi100: "Miseq" is a prefix of "Miseqi100"
        *MiSeq*|*Miseq*|*miseq*)             sequencer="miseq" ;;
    esac
fi

if [ -z "$sequencer" ]; then
    echo "ERROR: Could not determine sequencer type from path. Run with:"
    echo "  pixi run init --sequencer miseqi100"
    echo "  pixi run init --sequencer novaseqx"
    echo "  pixi run init --sequencer miseq"
    exit 1
fi

case "$sequencer" in
    miseqi100) staging_dir="/staging/nextcloud/Miseqi100" ;;
    novaseqx)  staging_dir="/staging/nextcloud/NovaseqX" ;;
    miseq)     staging_dir="/staging/nextcloud/Miseq" ;;
    *)
        echo "ERROR: Unknown sequencer '$sequencer'. Use 'miseqi100', 'novaseqx' or 'miseq'."
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

    # Sheets spell it inconsistently (MR496, mr496); fall back to the run dir name.
    library_name=$(basename "$metadata_file" .xlsx | grep -oiE '[ixm]R[0-9]+' | head -1 || true)
    if [ -z "$library_name" ]; then
        library_name=$(basename "$(pwd)" | grep -oiE '^[ixm]R[0-9]+$' || true)
    fi
    if [ -n "$library_name" ]; then
        # canonical form: lowercase instrument letter + "R" + digits, e.g. mR496
        library_name="$(echo "${library_name:0:1}" | tr '[:upper:]' '[:lower:]')R${library_name:2}"
        sed -i "s|^library_name:.*|library_name: \"$library_name\"|" snakemake_config_project.yaml
        echo "  library_name --> $library_name"
    else
        echo "  WARNING: Could not infer library_name from $metadata_file — set it manually."
    fi
else
    echo "  WARNING: No .xlsx found in metadata/ — set metadata and library_name manually."
fi

# Newest raw run = newest dir holding a RunInfo.xml. Project clones (e.g. Miseq/mR496)
# can sit beside the raw runs, so "newest dir" alone would pick this checkout.
data_dir=$( { find "$staging_dir" -mindepth 2 -maxdepth 2 -name RunInfo.xml -printf "%T@ %h\n" 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-; } || true)
if [ -n "$data_dir" ]; then
    sed -i "s|^data_dir:.*|data_dir: \"$data_dir\"|" snakemake_config_project.yaml
    echo "  data_dir --> $data_dir"
else
    echo "  WARNING: Could not find newest run (RunInfo.xml) in $staging_dir — set data_dir manually."
fi

echo "Ready: snakemake_config_project.yaml created/updated. Review it, then fill .env (cp .env.example .env)."
