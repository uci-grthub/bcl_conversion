#!/bin/bash
# Purge downstream outputs for a config_id (and optionally a specific project)
# when indexes in the renaming map need to change.
#
# Usage (by config_id):
#   src/purge_project_outputs.sh <config_id> [project] [--delete]
#
# Usage (by lane/group from metadata):
#   src/purge_project_outputs.sh --lane <N> [--group <G>] [--delete]
#
# By default runs in dry-run mode (lists files that would be deleted).
# Pass --delete to actually remove them.
#
# Files removed:
#   output/{config_id}/{project}/md5sums.txt
#   results/fastp/{config_id}/{project}/
#   results/fastp_plots/{config_id}/{project}/
#   logs/fastp_sample/{config_id}/{project}/
#   logs/fastp_plots_sample/{config_id}/{project}/
#   logs/project_link_{config_id}---{project}.log
#   benchmarks/ entries for the above rules
#   .output/{config_id}/.done                     (forces bcl-convert re-run)
#   results/renaming_map_{config_id}.csv          (forces regeneration)
#   results/SampleSheet_{config_id}.csv           (forces regeneration)
#   results/SampleSheet_{config_id}_validated.csv (forces re-validation)
#   .snakemake/iocache/latest.pkl                 (clears stale IOCache)

set -euo pipefail

LANE=""
GROUP=""
CONFIG_ID=""
PROJECT=""
DELETE=false

# Parse all flags
ARGS=("$@")
i=0
POSITIONAL=()
while [[ $i -lt ${#ARGS[@]} ]]; do
    arg="${ARGS[$i]}"
    case "$arg" in
        --lane)         i=$((i+1)); LANE="${ARGS[$i]}" ;;
        --group)        i=$((i+1)); GROUP="${ARGS[$i]}" ;;
        --delete)       DELETE=true ;;
        *) POSITIONAL+=("$arg") ;;
    esac
    i=$((i+1))
done

CONFIG_ID="${POSITIONAL[0]:-}"
PROJECT="${POSITIONAL[1]:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Build list of (config_id, project) pairs to process
# Each element is "config_id\tproject" (project may be empty)
PAIRS=()

if [[ -n "$LANE" ]]; then
    # Resolve config_id(s) and project from --lane / --group via renaming maps
    while IFS= read -r line; do
        PAIRS+=("$line")
    done < <(python3 - "$LANE" "$GROUP" <<'PYEOF'
import sys, os, glob, csv

lane = sys.argv[1]
group = sys.argv[2] if len(sys.argv) > 2 else ""

pattern = f"results/renaming_map_lane{lane}*.csv"
maps = glob.glob(pattern)
if not maps:
    print(f"ERROR: no renaming maps found matching {pattern}", file=sys.stderr)
    sys.exit(1)

for map_path in sorted(maps):
    config_id = os.path.basename(map_path).replace("renaming_map_", "").replace(".csv", "")
    if not group:
        print(f"{config_id}\t")
        continue
    with open(map_path) as f:
        reader = csv.DictReader(f)
        projects = set()
        for row in reader:
            try:
                row_group = str(int(float(row.get("Group", ""))))
            except (ValueError, TypeError):
                row_group = str(row.get("Group", "")).strip()
            if row_group == str(group):
                proj = row.get("Sample_Project", "").strip()
                if proj and proj.lower() != "nan":
                    projects.add(proj)
    for proj in sorted(projects):
        print(f"{config_id}\t{proj}")
PYEOF
    )
    if [[ ${#PAIRS[@]} -eq 0 ]]; then
        echo "ERROR: no project found for lane=${LANE}${GROUP:+ group=${GROUP}}" >&2
        exit 1
    fi
elif [[ -n "$CONFIG_ID" ]]; then
    PAIRS+=("${CONFIG_ID}"$'\t'"${PROJECT}")
else
    echo "Usage: $0 <config_id> [project] [--delete]"
    echo "       $0 --lane <N> [--group <G>] [--delete]"
    exit 1
fi

# Build list of targets to delete
TO_DELETE=()

collect_files() {
    local pattern="$1"
    # Use find/glob; suppress errors for missing dirs
    while IFS= read -r -d '' f; do
        TO_DELETE+=("$f")
    done < <(find . -path "./$pattern" -print0 2>/dev/null || true)
}

collect_path() {
    local p="$1"
    [[ -e "$p" ]] && TO_DELETE+=("$p")
    return 0
}

SEEN_CONFIGS=()

for pair in "${PAIRS[@]}"; do
    IFS=$'\t' read -r CONFIG_ID PROJECT <<< "$pair"

    echo "--- config_id='$CONFIG_ID'${PROJECT:+ project='$PROJECT'} ---"

    if [[ -n "$PROJECT" ]]; then
        PROJECTS=("$PROJECT")
    else
        # Gather all projects present under this config_id
        PROJECTS=()
        if [[ -d "output/$CONFIG_ID" ]]; then
            while IFS= read -r -d '' d; do
                proj="$(basename "$d")"
                [[ "$proj" == "Reports" || "$proj" == "Logs" || "$proj" == "flexbar" ]] && continue
                [[ -d "$d" ]] && PROJECTS+=("$proj")
            done < <(find "output/$CONFIG_ID" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
        fi
    fi

    for proj in "${PROJECTS[@]}"; do
        collect_path "output/$CONFIG_ID/$proj/md5sums.txt"

        # fastp results
        [[ -d "results/fastp/$CONFIG_ID/$proj" ]] && TO_DELETE+=("results/fastp/$CONFIG_ID/$proj")

        # fastp plot results
        [[ -d "results/fastp_plots/$CONFIG_ID/$proj" ]] && TO_DELETE+=("results/fastp_plots/$CONFIG_ID/$proj")

        # fastp logs
        [[ -d "logs/fastp_sample/$CONFIG_ID/$proj" ]] && TO_DELETE+=("logs/fastp_sample/$CONFIG_ID/$proj")
        [[ -d "logs/fastp_plots_sample/$CONFIG_ID/$proj" ]] && TO_DELETE+=("logs/fastp_plots_sample/$CONFIG_ID/$proj")

        # per-project bcl_convert validation sentinel
        collect_path "output/$CONFIG_ID/$proj/.project_done"

        # project_link log
        collect_path "logs/project_link_${CONFIG_ID}---${proj}.log"

        # benchmarks
        collect_files "benchmarks/fastp_sample_${CONFIG_ID}_${proj}*.bench"
        collect_files "benchmarks/fastp_plots_sample_${CONFIG_ID}_${proj}*.bench"
        collect_path "benchmarks/project_link_${CONFIG_ID}---${proj}.bench"
        collect_path "benchmarks/calculate_md5sums_${CONFIG_ID}_${proj}.bench"
    done

    # Renaming map and SampleSheet — once per unique config_id
    already_seen=false
    for seen in "${SEEN_CONFIGS[@]:-}"; do
        [[ "$seen" == "$CONFIG_ID" ]] && already_seen=true && break
    done
    if ! $already_seen; then
        collect_path ".output/${CONFIG_ID}/.done"
        collect_path "results/renaming_map_${CONFIG_ID}.csv"
        collect_path "results/SampleSheet_${CONFIG_ID}.csv"
        collect_path "results/SampleSheet_${CONFIG_ID}_validated.csv"
        SEEN_CONFIGS+=("$CONFIG_ID")
    fi
done

# IOCache (once, global)
collect_path ".snakemake/iocache/latest.pkl"

if [[ ${#TO_DELETE[@]} -eq 0 ]]; then
    echo "No files found."
    exit 0
fi

echo "Files to be deleted:"
for f in "${TO_DELETE[@]}"; do
    echo "  $f"
done

if $DELETE; then
    echo ""
    echo "Deleting..."
    for f in "${TO_DELETE[@]}"; do
        if [[ -d "$f" ]]; then
            rm -rf "$f" && echo "  removed dir: $f"
        elif [[ -f "$f" ]]; then
            rm -f "$f" && echo "  removed: $f"
        fi
    done
    echo "Done."
else
    echo ""
    echo "Dry run — pass --delete to remove these files."
fi
