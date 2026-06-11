#!/bin/bash
# Purge downstream outputs for one or more (config_id, project) pairs,
# plus the order-level report outputs for every affected order.
#
# Modes:
#   --lane <N>                               all projects on lane N
#   --lane <N> --group <G>                   one project on lane N / group G
#   --order-id <ORDER_ID>                    all projects for an order (all lanes)
#   --order-id <ORDER_ID> --lane <N>         order projects on a specific lane
#   --order-id <ORDER_ID> --lane <N> --group <G>  narrow to one project
#   --old-metadata <OLD> --new-metadata <NEW>  only (lane,group) pairs whose samples differ
#   <config_id> [project]                    direct specification (no metadata lookup)
#
# In every mode the order-level report outputs are also purged for each
# order_id that is affected (discovered from the metadata).
#
# By default runs in dry-run mode. Pass --delete to actually remove files.
#
# Per-project files removed:
#   output/{config_id}/{project}/*.fastq.gz
#   output/{config_id}/{project}/md5sums.txt
#   output/{config_id}/{project}/.project_done
#   output/{config_id}/{project}/.fastq_names_done
#   results/fastp/{config_id}/{project}/
#   results/fastp_plots/{config_id}/{project}/
#   logs/fastp_sample/{config_id}/{project}/
#   logs/fastp_plots_sample/{config_id}/{project}/
#   logs/project_link_{config_id}---{project}.log
#   logs/nextcloud_scan_{config_id}---{project}.done
#   benchmarks/fastp_*, project_link_*, calculate_md5sums_*
#
# Per-config files removed (once per unique config_id):
#   .output/{config_id}/.done
#   .output_rc/{config_id}/.done
#   results/fastp_plots_{config_id}.done
#   results/fastp_plots_summary_lane{N}.done
#   results/{config_id}/renaming_map_{config_id}.csv
#   results/{config_id}/SampleSheet_{config_id}.csv
#   results/{config_id}/SampleSheet_{config_id}_validated.csv
#
# Per-order files removed (once per unique order_id):
#   Reports/order_{order_id}/index.html
#   Reports/order_{order_id}/md5sums.txt
#   Reports/order_{order_id}/Download_Instructions.pdf
#   Reports/order_{order_id}/email_sent.done
#   logs/report_order_{order_id}.log
#   logs/send_order_email_{order_id}.log
#   benchmarks/report_order_id_{order_id}.bench
#   benchmarks/send_order_email_{order_id}.bench
#
# Global:
#   .snakemake/iocache/latest.pkl

set -euo pipefail

LANE=""
GROUP=""
ORDER_ID=""
CONFIG_ID=""
PROJECT=""
OLD_METADATA=""
NEW_METADATA=""
DELETE=false
REMOVE_SENTINELS=false

ARGS=("$@")
i=0
POSITIONAL=()
while [[ $i -lt ${#ARGS[@]} ]]; do
    arg="${ARGS[$i]}"
    case "$arg" in
        --lane)          i=$((i+1)); LANE="${ARGS[$i]}" ;;
        --group)         i=$((i+1)); GROUP="${ARGS[$i]}" ;;
        --order-id)      i=$((i+1)); ORDER_ID="${ARGS[$i]}" ;;
        --old-metadata)  i=$((i+1)); OLD_METADATA="${ARGS[$i]}" ;;
        --new-metadata)  i=$((i+1)); NEW_METADATA="${ARGS[$i]}" ;;
        --delete)            DELETE=true ;;
        --remove-sentinels)  REMOVE_SENTINELS=true ;;
        *) POSITIONAL+=("$arg") ;;
    esac
    i=$((i+1))
done

CONFIG_ID="${POSITIONAL[0]:-}"
PROJECT="${POSITIONAL[1]:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# ---------------------------------------------------------------------------
# Resolve (config_id, project, order_id) triples
# ---------------------------------------------------------------------------
# Each element of TRIPLES is "config_id\tproject\torder_id"
# (order_id may be empty for direct config_id invocations without metadata)
TRIPLES=()

if [[ -n "$LANE" || -n "$ORDER_ID" ]]; then
    while IFS= read -r line; do
        TRIPLES+=("$line")
    done < <(python3 - "$LANE" "$GROUP" "$ORDER_ID" <<'PYEOF'
import sys, os, glob, csv, re

lane_filter     = sys.argv[1] if len(sys.argv) > 1 else ""
group_filter    = sys.argv[2] if len(sys.argv) > 2 else ""
order_id_filter = sys.argv[3] if len(sys.argv) > 3 else ""

# ---- read metadata to build ORDER_ID_LOOKUP: (lane, group) -> order_id ----
ORDER_ID_LOOKUP  = {}   # (lane_int, group_int) -> order_id
PROJECT_ORDER_ID = {}   # (project, lane_int)   -> order_id

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
                    l    = int(float(row.get("Lane", "")))
                    g    = int(float(row.get("Gr",   "")))
                    oid  = str(row.get("Order ID",     "")).strip().replace(" ", "_").replace("i", "I")
                    proj = str(row.get("Project Name", "")).strip().replace(" ", "_")
                    if oid and oid.lower() != "nan":
                        ORDER_ID_LOOKUP[(l, g)] = oid
                        if proj and proj.lower() != "nan":
                            PROJECT_ORDER_ID[(proj, l)] = oid
                except Exception:
                    pass

        if "Barcode List" in xl.sheet_names:
            df_b = pd.read_excel(metadata_file, sheet_name="Barcode List", header=1)
            for _, row in df_b.iterrows():
                try:
                    proj = str(row.get("Project name", "")).strip().replace(" ", "_")
                    oid  = str(row.get("Order ID",     "")).strip().replace(" ", "_").replace("i", "I")
                    lv   = row.get("Lane", None)
                    if proj and proj.lower() != "nan" and oid and oid.lower() != "nan":
                        try:
                            li = int(float(lv))
                        except (ValueError, TypeError):
                            li = 0
                        if (proj, li) not in PROJECT_ORDER_ID:
                            PROJECT_ORDER_ID[(proj, li)] = oid
                except Exception:
                    pass
    except Exception as e:
        print(f"WARNING: could not read metadata ({metadata_file}): {e}", file=sys.stderr)

# ---- scan renaming maps and emit matching triples --------------------------
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
            proj = row.get("Sample_Project", "").strip()
            if not proj or proj.lower() == "nan":
                continue

            try:
                g = int(float(row.get("Group", "")))
            except (ValueError, TypeError):
                g = None

            if group_filter and (g is None or str(g) != str(group_filter)):
                continue

            # look up order_id for this (config_lane, group) pair
            oid = ""
            if g is not None:
                oid = ORDER_ID_LOOKUP.get((config_lane, g), "")
            if not oid:
                oid = PROJECT_ORDER_ID.get((proj, config_lane), "")

            if order_id_filter and oid != order_id_filter:
                continue

            if g is None:
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
elif [[ -n "$OLD_METADATA" && -n "$NEW_METADATA" ]]; then
    # Diff mode: find (lane, group) pairs whose samples differ between two metadata files
    while IFS= read -r line; do
        TRIPLES+=("$line")
    done < <(python3 - "$OLD_METADATA" "$NEW_METADATA" <<'PYEOF'
import sys, os, re, tempfile
import pandas as pd

old_file = sys.argv[1]
new_file = sys.argv[2]

# Use metadata_validation so the comparison reflects what the pipeline actually sees
sys.path.insert(0, os.path.join(os.path.abspath("."), "src"))
from metadata_validation import validate_metadata_and_write_report

SKIP_SHEETS = {"recommended_changes", "rc_orientation"}

def load_normalized(filepath):
    """Run validation on filepath, write to a temp xlsx, then read back.
    Returns (summary_df, {sheet_lower: df}) with normalized/forward-filled data."""
    with tempfile.NamedTemporaryFile(suffix=".xlsx", delete=False) as tf:
        norm_path = tf.name
    try:
        validate_metadata_and_write_report(filepath, out_xlsx=norm_path)
        xl = pd.ExcelFile(norm_path)
        summary = None
        tabs = {}
        for sheet in xl.sheet_names:
            if sheet.lower() in SKIP_SHEETS:
                continue
            df = pd.read_excel(norm_path, sheet_name=sheet)
            if "summary" in sheet.lower():
                summary = df
            else:
                tabs[sheet.lower()] = df
        return summary, tabs
    finally:
        try:
            os.unlink(norm_path)
        except Exception:
            pass

old_summary, old_tabs = load_normalized(old_file)
new_summary, new_tabs = load_normalized(new_file)

if old_summary is None or new_summary is None:
    print("ERROR: could not read Summary sheet from normalized metadata", file=sys.stderr)
    sys.exit(1)

# Build ORDER_ID_LOOKUP and (lane, tab_name_lower) -> group from old Summary
ORDER_ID_LOOKUP = {}
lane_tab_group = {}   # (lane_int, tab_lower) -> group_int
for _, row in old_summary.iterrows():
    try:
        lane = int(float(row.get("Lane", "")))
        gr   = int(float(row.get("Gr", row.get("Group", ""))))
        oid  = str(row.get("Order ID", "")).strip().replace(" ", "_").replace("i", "I")
        tab  = str(row.get("Sample sheet tab", "")).strip().lower()
        if oid and oid.lower() not in ("nan", "none", ""):
            ORDER_ID_LOOKUP[(lane, gr)] = oid
        if tab and tab not in ("nan", "none", ""):
            lane_tab_group[(lane, tab)] = gr
    except Exception:
        pass

# Also pick up any new groups from new Summary (e.g. if a sample moved lanes)
for _, row in new_summary.iterrows():
    try:
        lane = int(float(row.get("Lane", "")))
        gr   = int(float(row.get("Gr", row.get("Group", ""))))
        oid  = str(row.get("Order ID", "")).strip().replace(" ", "_").replace("i", "I")
        tab  = str(row.get("Sample sheet tab", "")).strip().lower()
        if oid and oid.lower() not in ("nan", "none", ""):
            ORDER_ID_LOOKUP.setdefault((lane, gr), oid)
        if tab and tab not in ("nan", "none", ""):
            lane_tab_group.setdefault((lane, tab), gr)
    except Exception:
        pass

# After validation, normalized project name is in 'Project'; fall back to 'Sample_Project'
COMPARE_COLS = ["index", "index2", "Lane", "Sample_Name", "Project", "Sample_Project"]

affected = set()  # (config_id, group, order_id)
changed_barcodes = {}  # (config_id, group, order_id) -> set of "old_index-old_index2" patterns

def _get_barcode_pat(row):
    idx  = str(row.get("index",  "")).strip()
    idx2 = str(row.get("index2", "")).strip()
    if not idx or idx.lower() in ("nan", "none", ""):
        return None
    if idx2 and idx2.lower() not in ("nan", "none", ""):
        return f"{idx}-{idx2}"
    return idx

all_tabs = set(old_tabs) | set(new_tabs)
for tab in all_tabs:
    old_data = old_tabs.get(tab, pd.DataFrame())
    new_data = new_tabs.get(tab, pd.DataFrame())

    key = "Sample_ID"
    if key not in getattr(old_data, "columns", []) and key not in getattr(new_data, "columns", []):
        continue

    old_by_id = old_data.set_index(key) if key in getattr(old_data, "columns", []) else pd.DataFrame()
    new_by_id = new_data.set_index(key) if key in getattr(new_data, "columns", []) else pd.DataFrame()

    changed_lanes = set()
    lane_old_barcodes = {}  # lane -> set of old barcode patterns whose FASTQs must be deleted

    for sid in set(list(old_by_id.index) + list(new_by_id.index)):
        in_old = sid in old_by_id.index
        in_new = sid in new_by_id.index
        if in_old and not in_new:
            # Sample removed: its old FASTQ (named after old barcode) will not be recreated
            try:
                old_row = old_by_id.loc[sid]
                lane = int(float(old_row["Lane"]))
                changed_lanes.add(lane)
                pat = _get_barcode_pat(old_row)
                if pat:
                    lane_old_barcodes.setdefault(lane, set()).add(pat)
            except Exception: pass
        elif in_new and not in_old:
            # New sample: no old FASTQ to delete
            try: changed_lanes.add(int(float(new_by_id.loc[sid, "Lane"])))
            except Exception: pass
        else:
            old_row = old_by_id.loc[sid]
            new_row = new_by_id.loc[sid]
            for col in COMPARE_COLS:
                ov = str(old_row.get(col, "")) if col in old_row.index else ""
                nv = str(new_row.get(col, "")) if col in new_row.index else ""
                if ov != nv:
                    try: changed_lanes.add(int(float(old_row["Lane"])))
                    except Exception: pass
                    try: changed_lanes.add(int(float(new_row["Lane"])))
                    except Exception: pass
                    # Only the old FASTQ needs deletion when its barcode changed;
                    # for non-barcode changes (Sample_Name, Project, etc.) BCL Convert
                    # would produce identical FASTQ content so no deletion needed.
                    if col in ("index", "index2"):
                        try:
                            lane = int(float(old_row["Lane"]))
                            pat = _get_barcode_pat(old_row)
                            if pat:
                                lane_old_barcodes.setdefault(lane, set()).add(pat)
                        except Exception: pass
                    break

    for lane in changed_lanes:
        gr = lane_tab_group.get((lane, tab))
        if gr is None:
            # Fall back: any group on this lane
            for (l, t), g in lane_tab_group.items():
                if l == lane:
                    gr = g
                    break
        if gr is not None:
            oid = ORDER_ID_LOOKUP.get((lane, gr), "")
            key_tup = (f"lane{lane}", gr, oid)
            affected.add(key_tup)
            changed_barcodes.setdefault(key_tup, set()).update(
                lane_old_barcodes.get(lane, set())
            )

if not affected:
    print("INFO: no differing samples found between the two metadata files", file=sys.stderr)
    sys.exit(0)

for config_id, gr, oid in sorted(affected):
    patterns = " ".join(sorted(changed_barcodes.get((config_id, gr, oid), set())))
    print(f"{config_id}\t{gr}\t{oid}\t{patterns}")
PYEOF
    )
    if [[ ${#TRIPLES[@]} -eq 0 ]]; then
        exit 0
    fi
elif [[ -n "$CONFIG_ID" ]]; then
    TRIPLES+=("${CONFIG_ID}"$'\t'"__direct__"$'\t'"")
else
    echo "Usage: $0 --lane <N> [--group <G>] [--order-id <ORDER_ID>] [--delete]"
    echo "       $0 --order-id <ORDER_ID> [--lane <N>] [--group <G>] [--delete]"
    echo "       $0 --old-metadata <OLD.xlsx> --new-metadata <NEW.xlsx> [--delete]"
    echo "       $0 <config_id> [project] [--delete]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Collect files to delete
# ---------------------------------------------------------------------------
TO_DELETE=()

collect_glob() {
    local pattern="$1"
    while IFS= read -r -d '' f; do
        TO_DELETE+=("$f")
    done < <(find . -path "./$pattern" -print0 2>/dev/null || true)
}

collect_path() {
    [[ -e "$1" ]] && TO_DELETE+=("$1")
    return 0
}

SEEN_CONFIGS=()
SEEN_ORDERS=()

for triple in "${TRIPLES[@]}"; do
    IFS=$'\t' read -r CID GRP OID FASTQ_PATTERNS <<< "$triple"

    echo "--- config_id='$CID'${GRP:+ group='$GRP'}${OID:+ order_id='$OID'} ---"

    # Determine which project directories to process
    PROJECTS=()
    if [[ "$GRP" == "__direct__" ]]; then
        # Direct mode: use PROJECT positional arg or enumerate all
        if [[ -n "$PROJECT" ]]; then
            PROJECTS=("$PROJECT")
        elif [[ -d "output/$CID" ]]; then
            while IFS= read -r -d '' d; do
                proj="$(basename "$d")"
                [[ "$proj" == "Reports" || "$proj" == "Logs" || "$proj" == "flexbar" ]] && continue
                PROJECTS+=("$proj")
            done < <(find "output/$CID" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
        fi
    elif [[ -n "$GRP" ]]; then
        # Group-based: find actual renamed project dirs matching *_G{GRP}
        while IFS= read -r -d '' d; do
            PROJECTS+=("$(basename "$d")")
        done < <(find "output/$CID" -mindepth 1 -maxdepth 1 -type d -name "*_G${GRP}" -print0 2>/dev/null)
        if [[ ${#PROJECTS[@]} -eq 0 ]]; then
            echo "  WARNING: no output directory found matching output/$CID/*_G${GRP}" >&2
        fi
    else
        # No group: enumerate all non-system project dirs
        if [[ -d "output/$CID" ]]; then
            while IFS= read -r -d '' d; do
                proj="$(basename "$d")"
                [[ "$proj" == "Reports" || "$proj" == "Logs" || "$proj" == "flexbar" ]] && continue
                PROJECTS+=("$proj")
            done < <(find "output/$CID" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
        fi
    fi

    # Per-project outputs
    for proj in "${PROJECTS[@]}"; do
        collect_path "output/$CID/$proj/md5sums.txt"
        if $REMOVE_SENTINELS; then
            collect_path "output/$CID/$proj/.project_done"
            collect_path "output/$CID/$proj/.fastq_names_done"
        fi
        # Diff mode: only delete FASTQs whose barcode changed (FASTQ_PATTERNS is set by
        # the Python diff block to the space-separated old "{index}-{index2}" patterns).
        # Regular mode (FASTQ_PATTERNS unset): delete all FASTQs in the project dir.
        if [[ -n "$OLD_METADATA" ]]; then
            for pat in $FASTQ_PATTERNS; do
                collect_glob "output/$CID/$proj/*${pat}*.fastq.gz"
            done
        else
            collect_glob "output/$CID/$proj/*.fastq.gz"
        fi
        # fastp outputs: results/{config_id}/{project}/
        [[ -d "results/$CID/$proj"                              ]] && TO_DELETE+=("results/$CID/$proj")
        # logs: logs/{config_id}/fastp_sample/{config_id}/{project}/
        [[ -d "logs/$CID/fastp_sample/$CID/$proj"               ]] && TO_DELETE+=("logs/$CID/fastp_sample/$CID/$proj")
        [[ -d "logs/$CID/fastp_plots_sample/$CID/$proj"         ]] && TO_DELETE+=("logs/$CID/fastp_plots_sample/$CID/$proj")
        if $REMOVE_SENTINELS; then
            collect_path "logs/nextcloud_scan_${CID}---${proj}.done"
        fi
        collect_path "logs/project_link_${CID}---${proj}.log"
        collect_glob "benchmarks/fastp_sample_${CID}_${proj}*.bench"
        collect_glob "benchmarks/fastp_plots_sample_${CID}_${proj}*.bench"
        collect_path "benchmarks/project_link_${CID}---${proj}.bench"
        collect_path "benchmarks/calculate_md5sums_${CID}_${proj}.bench"
    done

    # Per-config outputs (once per unique config_id)
    already_seen=false
    for seen in "${SEEN_CONFIGS[@]:-}"; do
        [[ "$seen" == "$CID" ]] && already_seen=true && break
    done
    if ! $already_seen; then
        if $REMOVE_SENTINELS; then
            collect_path ".output/${CID}/.done"
            collect_path ".output_rc/${CID}/.done"
            collect_path "results/${CID}/fastp_plots_${CID}.done"
            lane_num=$(echo "$CID" | sed 's/lane\([0-9]*\).*/\1/')
            [[ -n "$lane_num" ]] && collect_path "results/${CID}/fastp_plots_summary_lane${lane_num}.done"
        fi
        collect_path "results/${CID}/renaming_map_${CID}.csv"
        collect_path "results/${CID}/SampleSheet_${CID}.csv"
        collect_path "results/${CID}/SampleSheet_${CID}_validated.csv"
        SEEN_CONFIGS+=("$CID")
    fi

    # Track order_ids for order-level purge below
    if [[ -n "$OID" ]]; then
        already_seen=false
        for seen in "${SEEN_ORDERS[@]:-}"; do
            [[ "$seen" == "$OID" ]] && already_seen=true && break
        done
        $already_seen || SEEN_ORDERS+=("$OID")
    fi
done

# Per-order outputs (once per unique order_id discovered above)
for oid in "${SEEN_ORDERS[@]:-}"; do
    echo "--- order_id='$oid' (report outputs) ---"
    collect_path "Reports/order_${oid}/index.html"
    collect_path "Reports/order_${oid}/md5sums.txt"
    collect_path "Reports/order_${oid}/Download_Instructions.pdf"
    if $REMOVE_SENTINELS; then
        collect_path "Reports/order_${oid}/email_sent.done"
    fi
    collect_path "logs/report_order_${oid}.log"
    collect_path "logs/send_order_email_${oid}.log"
    collect_path "benchmarks/report_order_id_${oid}.bench"
    collect_path "benchmarks/send_order_email_${oid}.bench"
done

# Global
if $REMOVE_SENTINELS; then
    collect_path ".snakemake/iocache/latest.pkl"
fi

# ---------------------------------------------------------------------------
# Report / execute
# ---------------------------------------------------------------------------
if [[ ${#TO_DELETE[@]} -eq 0 ]]; then
    echo "No files found."
    exit 0
fi

echo ""
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
