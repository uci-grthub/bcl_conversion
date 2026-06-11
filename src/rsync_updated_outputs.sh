#!/bin/bash
# Rsync outputs for one or more (config_id, project) pairs to a mirrored
# directory structure, including the order-level report for every affected order.
#
# Shares the same scope arguments as purge_project_outputs.sh.
# Run purge → snakemake → rsync to push only the regenerated outputs.
#
# Modes:
#   --lane <N>                               all projects on lane N
#   --lane <N> --group <G>                   one project on lane N / group G
#   --order-id <ORDER_ID>                    all projects for an order (all lanes)
#   --order-id <ORDER_ID> --lane <N>         order projects on a specific lane
#   --order-id <ORDER_ID> --lane <N> --group <G>  narrow to one project
#   <config_id> [project]                    direct specification (no metadata lookup)
#
# In every mode the order-level Reports/order_*/ directory is also synced for
# each order_id that is affected (discovered from the metadata).
#
# --dest defaults to external_drive_path/<library_name> from snakemake_config*.yaml.
# --dry-run passes -n to rsync.

set -euo pipefail

LANE=""
GROUP=""
ORDER_ID=""
CONFIG_ID=""
PROJECT=""
DEST=""
DRY_RUN=false

ARGS=("$@")
i=0
POSITIONAL=()
while [[ $i -lt ${#ARGS[@]} ]]; do
    arg="${ARGS[$i]}"
    case "$arg" in
        --lane)      i=$((i+1)); LANE="${ARGS[$i]}" ;;
        --group)     i=$((i+1)); GROUP="${ARGS[$i]}" ;;
        --order-id)  i=$((i+1)); ORDER_ID="${ARGS[$i]}" ;;
        --dest)      i=$((i+1)); DEST="${ARGS[$i]}" ;;
        --dry-run)   DRY_RUN=true ;;
        *) POSITIONAL+=("$arg") ;;
    esac
    i=$((i+1))
done

CONFIG_ID="${POSITIONAL[0]:-}"
PROJECT="${POSITIONAL[1]:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Resolve destination from config if not provided
if [[ -z "$DEST" ]]; then
    DEST="$(python3 - <<'PYEOF'
import sys, os
for cfg in ("snakemake_config_project.yaml", "snakemake_config.yaml"):
    if os.path.exists(cfg):
        import yaml as _yaml
        with open(cfg) as f:
            data = _yaml.safe_load(f)
        ext = data.get("external_drive_path", "").rstrip("/")
        lib = data.get("library_name", "")
        if ext and lib:
            print(f"{ext}/{lib}")
            sys.exit(0)
print("", end="")
PYEOF
)"
    if [[ -z "$DEST" ]]; then
        echo "ERROR: --dest not given and external_drive_path/library_name not set in config" >&2
        exit 1
    fi
fi

echo "Destination: $DEST"

if [[ ! -d "$DEST" ]]; then
    echo "ERROR: destination directory does not exist: $DEST" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve (config_id, group, order_id) triples via metadata + renaming maps.
# The actual output directory is found from the filesystem using the group
# number (_G{N} suffix) rather than the Sample_Project name, because the
# pipeline renames project directories to {LabID}_{OrderID}_{Library}_L{N}_G{N}.
# ---------------------------------------------------------------------------
TRIPLES=()

if [[ -n "$LANE" || -n "$ORDER_ID" ]]; then
    while IFS= read -r line; do
        TRIPLES+=("$line")
    done < <(python3 - "$LANE" "$GROUP" "$ORDER_ID" <<'PYEOF'
import sys, os, glob, csv, re

lane_filter     = sys.argv[1] if len(sys.argv) > 1 else ""
group_filter    = sys.argv[2] if len(sys.argv) > 2 else ""
order_id_filter = sys.argv[3] if len(sys.argv) > 3 else ""

ORDER_ID_LOOKUP = {}

metadata_file = ""
for cfg in ("snakemake_config_project.yaml", "snakemake_config.yaml"):
    if os.path.exists(cfg):
        try:
            import yaml as _yaml
            with open(cfg) as f:
                data = _yaml.safe_load(f)
            metadata_file = data.get("metadata", "")
        except Exception:
            pass
        break

if metadata_file and os.path.exists(metadata_file):
    try:
        import pandas as pd
        xl = pd.ExcelFile(metadata_file)
        if "Summary" in xl.sheet_names:
            df = pd.read_excel(metadata_file, sheet_name="Summary", header=2)
            for _, row in df.iterrows():
                try:
                    l   = int(float(row.get("Lane", "")))
                    g   = int(float(row.get("Gr",   "")))
                    oid = str(row.get("Order ID", "")).strip().replace(" ", "_").replace("i", "I")
                    if oid and oid.lower() != "nan":
                        ORDER_ID_LOOKUP[(l, g)] = oid
                except Exception:
                    pass
    except Exception as e:
        print(f"WARNING: could not read metadata ({metadata_file}): {e}", file=sys.stderr)

maps = sorted(glob.glob("results/lane*/renaming_map_lane*.csv"))
if not maps:
    print("ERROR: no renaming maps found in results/", file=sys.stderr)
    sys.exit(1)

seen = set()
for map_path in maps:
    config_id   = os.path.basename(map_path).replace("renaming_map_", "").replace(".csv", "")
    m           = re.match(r"lane(\d+)", config_id)
    config_lane = int(m.group(1)) if m else 0

    if lane_filter and str(config_lane) != str(lane_filter):
        continue

    with open(map_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                g = int(float(row.get("Group", "")))
            except (ValueError, TypeError):
                continue

            if group_filter and str(g) != str(group_filter):
                continue

            oid = ORDER_ID_LOOKUP.get((config_lane, g), "")

            if order_id_filter and oid != order_id_filter:
                continue

            key = (config_id, g)
            if key not in seen:
                seen.add(key)
                print(f"{config_id}\t{g}\t{oid}")

if not seen:
    filters = []
    if lane_filter:     filters.append(f"lane={lane_filter}")
    if group_filter:    filters.append(f"group={group_filter}")
    if order_id_filter: filters.append(f"order_id={order_id_filter}")
    print(f"ERROR: no projects found for {', '.join(filters)}", file=sys.stderr)
    sys.exit(1)
PYEOF
    )
    if [[ ${#TRIPLES[@]} -eq 0 ]]; then
        exit 1
    fi
elif [[ -n "$CONFIG_ID" ]]; then
    # Direct mode: no group lookup needed; project dir name provided directly
    TRIPLES+=("${CONFIG_ID}"$'\t'"__direct__"$'\t'"")
else
    echo "Usage: $0 --lane <N> [--group <G>] [--order-id <ORDER_ID>] [--dest <PATH>] [--dry-run]"
    echo "       $0 --order-id <ORDER_ID> [--lane <N>] [--group <G>] [--dest <PATH>] [--dry-run]"
    echo "       $0 <config_id> [project] [--dest <PATH>] [--dry-run]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Collect source paths and track order_ids
# ---------------------------------------------------------------------------
# FASTQ_PATHS: large output/{config_id}/{project}/ dirs synced with --ignore-existing
#              so already-transferred FASTQs are never re-sent.
# META_PATHS:  everything else (sample sheets, renaming maps, sentinels, results,
#              DRAGEN metadata) synced without --ignore-existing so updated files
#              overwrite stale copies on the destination.
# ---------------------------------------------------------------------------
FASTQ_PATHS=()
META_PATHS=()
SHEET_PATHS=()    # sample sheets + renaming maps: force-overwrite via checksum
SEEN_ORDERS=()
SEEN_CONFIGS=()
PROJECT_DIRS=()   # tracks (config_id, project) pairs for results/ syncing

for triple in "${TRIPLES[@]}"; do
    IFS=$'\t' read -r CID GRP OID <<< "$triple"

    if [[ "$GRP" == "__direct__" ]]; then
        # Direct config_id [project] mode
        if [[ -n "$PROJECT" ]]; then
            dir="output/$CID/$PROJECT"
            [[ -d "$dir" ]] && FASTQ_PATHS+=("./$dir")
            PROJECT_DIRS+=("$CID/$PROJECT")
        else
            while IFS= read -r -d '' d; do
                proj="$(basename "$d")"
                [[ "$proj" == "Reports" || "$proj" == "Logs" || "$proj" == "flexbar" ]] && continue
                FASTQ_PATHS+=("./$d")
                PROJECT_DIRS+=("$CID/$proj")
            done < <(find "output/$CID" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
        fi
    elif [[ -n "$GRP" ]]; then
        # Find the actual project directory for this group (ends with _G{GRP})
        echo "--- config_id='$CID' group='$GRP'${OID:+ order_id='$OID'} ---"
        found=false
        while IFS= read -r -d '' d; do
            FASTQ_PATHS+=("./$d")
            PROJECT_DIRS+=("$CID/$(basename "$d")")
            found=true
        done < <(find "output/$CID" -mindepth 1 -maxdepth 1 -type d -name "*_G${GRP}" -print0 2>/dev/null)
        if ! $found; then
            echo "  WARNING: no output directory found matching output/$CID/*_G${GRP}" >&2
        fi
    else
        # No group filter — sync all non-system project dirs for this config_id
        echo "--- config_id='$CID' (all projects)${OID:+ order_id='$OID'} ---"
        while IFS= read -r -d '' d; do
            proj="$(basename "$d")"
            [[ "$proj" == "Reports" || "$proj" == "Logs" || "$proj" == "flexbar" ]] && continue
            FASTQ_PATHS+=("./$d")
            PROJECT_DIRS+=("$CID/$proj")
        done < <(find "output/$CID" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    if [[ -n "$OID" ]]; then
        already_seen=false
        for seen in "${SEEN_ORDERS[@]:-}"; do
            [[ "$seen" == "$OID" ]] && already_seen=true && break
        done
        $already_seen || SEEN_ORDERS+=("$OID")
    fi

    # Per-config-id files: sentinels, DRAGEN metadata, DRAGEN Logs/Reports dirs,
    # and generated sample sheets / renaming maps.
    # Added once per unique config_id regardless of how many groups are in the triple list.
    already_seen_config=false
    for seen_cid in "${SEEN_CONFIGS[@]:-}"; do
        [[ "$seen_cid" == "$CID" ]] && already_seen_config=true && break
    done
    if ! $already_seen_config; then
        SEEN_CONFIGS+=("$CID")
        # Sentinel files
        [[ -f ".output/$CID/.done" ]]    && META_PATHS+=("./.output/$CID/.done")
        [[ -f ".output_rc/$CID/.done" ]] && META_PATHS+=("./.output_rc/$CID/.done")
        while IFS= read -r -d '' f; do
            META_PATHS+=("./$f")
        done < <(find "logs/$CID" -name "*.done" -print0 2>/dev/null)
        # orientation_decision JSON (input to analyze_undetermined_rc)
        [[ -f "logs/$CID/orientation_decision_${CID}.json" ]] && META_PATHS+=("./logs/$CID/orientation_decision_${CID}.json")
        # Hidden DRAGEN output Reports dirs (contain Top_Unknown_Barcodes.csv read by analyze_undetermined rules)
        [[ -d ".output/$CID/Reports" ]]    && META_PATHS+=("./.output/$CID/Reports")
        [[ -d ".output_rc/$CID/Reports" ]] && META_PATHS+=("./.output_rc/$CID/Reports")
        # analyze_undetermined output CSVs
        [[ -f "results/undetermined_indices/$CID.csv" ]]      && META_PATHS+=("./results/undetermined_indices/$CID.csv")
        [[ -f "results/undetermined_indices/${CID}_rc.csv" ]] && META_PATHS+=("./results/undetermined_indices/${CID}_rc.csv")
        # DRAGEN per-lane Logs and Reports directories (visible output/)
        [[ -d "output/$CID/Logs" ]]    && META_PATHS+=("./output/$CID/Logs")
        [[ -d "output/$CID/Reports" ]] && META_PATHS+=("./output/$CID/Reports")
        # DRAGEN per-lane metadata files
        for f in "output/$CID/dragen-replay.json" "output/$CID/dragen.metrics.json" "output/$CID/dragen.time_metrics.csv"; do
            [[ -f "$f" ]] && META_PATHS+=("./$f")
        done
        # Generated sample sheets and renaming map — copied with cp -f to force
        # overwrite regardless of timestamp or size (destination can appear newer
        # after a prior rsync when index assignments have changed).
        while IFS= read -r -d '' f; do
            SHEET_PATHS+=("./$f")
        done < <(find "results/$CID" -maxdepth 1 \( -name "SampleSheet_*.csv" -o -name "renaming_map_*.csv" \) -print0 2>/dev/null)
    fi
done

# Per-project fastp results directories (updated when FASTQs are reprocessed)
for cid_proj in "${PROJECT_DIRS[@]:-}"; do
    IFS='/' read -r CID PROJ <<< "$cid_proj"
    [[ -d "results/$CID/$PROJ" ]] && META_PATHS+=("./results/$CID/$PROJ")
done


if [[ ${#FASTQ_PATHS[@]} -eq 0 && ${#META_PATHS[@]} -eq 0 ]]; then
    echo "No output directories found to sync."
    exit 0
fi

echo ""
echo "Syncing to: $DEST"

if [[ ${#FASTQ_PATHS[@]} -gt 0 ]]; then
    FASTQ_OPTS=(-av --relative --ignore-existing)
    $DRY_RUN && FASTQ_OPTS+=(-n)
    echo ""
    echo "FASTQs (--ignore-existing):"
    for p in "${FASTQ_PATHS[@]}"; do echo "  $p"; done
    echo ""
    rsync "${FASTQ_OPTS[@]}" "${FASTQ_PATHS[@]}" "$DEST/"
fi

if [[ ${#META_PATHS[@]} -gt 0 ]]; then
    META_OPTS=(-av --relative)
    $DRY_RUN && META_OPTS+=(-n)
    echo ""
    echo "Metadata / results (overwrite):"
    for p in "${META_PATHS[@]}"; do echo "  $p"; done
    echo ""
    rsync "${META_OPTS[@]}" "${META_PATHS[@]}" "$DEST/"
fi

if [[ ${#SHEET_PATHS[@]} -gt 0 ]]; then
    echo ""
    echo "Sample sheets / renaming maps (force overwrite):"
    for p in "${SHEET_PATHS[@]}"; do
        rel="${p#./}"
        dst="$DEST/$rel"
        echo "  $rel"
        if ! $DRY_RUN; then
            mkdir -p "$(dirname "$dst")"
            cp -f "$rel" "$dst"
        fi
    done
fi
