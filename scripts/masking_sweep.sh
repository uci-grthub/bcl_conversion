#!/usr/bin/env bash
# Build one complete deliverable set per masking variant for a single lane/group,
# without re-running DRAGEN for each one.
#
# Why this works: the variants for this run differ only in the R2 Y-length
# (Y28;I10;I10;Y{n}N{91-n}). R1/I1/I2 and the demultiplex are identical, so a
# shorter-R2 FASTQ is an exact prefix of the long-R2 FASTQ already produced by
# the main run. Each variant therefore reuses the main run's reads with R2
# truncated by seqtk, and runs the unmodified pipeline in its own working
# directory (snakemake -d) for QC, plots, md5s, links and the order report.
#
# Those reads come from .output/<lane> while they are still there, and from the
# delivered output/<lane>/<renamed project> folders once bcl_project_done has
# moved them -- which it has, by the time the main run is finished enough for
# this script to be allowed to start. See resolve_fastq_sources.
#
# Usage (after the main run has finished the lane):
#     pixi run masking-sweep              # variants 39 22 17
#     pixi run masking-sweep 39 22        # explicit list of R2 lengths
#
# Env overrides:
#     SWEEP_LANE=8 SWEEP_GROUP=1 SWEEP_CORES=8
#     SWEEP_EMAIL=you@uci.edu   recipient/cc for variant runs (never the customer)
#     SWEEP_FORCE=1             rebuild a variant whose report already exists
#     SWEEP_STOP_AFTER_SEED=1   build + seed, skip the full pipeline run

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

LANE="${SWEEP_LANE:-8}"
GROUP="${SWEEP_GROUP:-1}"
CORES="${SWEEP_CORES:-8}"
SWEEP_EMAIL="${SWEEP_EMAIL:-kstachel@uci.edu}"
CONFIG_ID="lane${LANE}"

if [ "$#" -gt 0 ]; then
    VARIANTS=("$@")
else
    VARIANTS=(39 22 17)
fi

PROJECT_CONFIG="snakemake_config_project.yaml"
[ -f "$PROJECT_CONFIG" ] || { echo "ERROR: $PROJECT_CONFIG not found in $REPO"; exit 1; }

# Everything below assumes the pixi environment (snakemake, seqtk, pigz, python
# with pyyaml/openpyxl). Run this as `pixi run masking-sweep`.
for tool in snakemake seqtk pigz python rsync; do
    command -v "$tool" > /dev/null || {
        echo "ERROR: $tool not on PATH — run this via 'pixi run masking-sweep'"; exit 1; }
done

read_cfg() {
    python -c "import yaml,sys; print(yaml.safe_load(open('$PROJECT_CONFIG')).get('$1','') or '')"
}

BASE_METADATA="$(read_cfg metadata)"
LIBRARY="$(read_cfg library_name)"
DATA_DIR="$(read_cfg data_dir)"

[ -f "$BASE_METADATA" ] || { echo "ERROR: metadata workbook not found: $BASE_METADATA"; exit 1; }
[ -n "$LIBRARY" ] || { echo "ERROR: library_name is empty in $PROJECT_CONFIG"; exit 1; }

MAIN_OUT="$REPO/.output/$CONFIG_ID"
MAIN_RC_OUT="$REPO/.output_rc/$CONFIG_ID"

# Locate the FASTQs belonging to one conversion tree, emitting
# "<absolute source path>\t<path relative to the tree root>" per file.
#
# The staging tree is only the FIRST place to look. bcl_project_done MOVES
# .output/<lane>/<Sample_Project> into output/<lane>/<renamed project>, so once
# the main run has finished the lane -- which is exactly the precondition this
# script enforces -- .output/<lane> holds Reports/, Logs/ and the dragen JSONs
# and not one read. Fall back to the delivered folders and rebuild the
# pre-rename layout, because that is the layout the variant's own
# bcl_project_done will go looking for.
resolve_fastq_sources() {
    local src="$1" orientation="$2"
    python - "$REPO" "$CONFIG_ID" "$src" "$orientation" <<'PY'
import csv, json, os, re, sys

repo, config_id, src, want = sys.argv[1:5]

FQ = re.compile(r'^(?P<sample>.+)_S\d+_L\d+_[RI][12]_001\.fastq\.gz$')

def emit(pairs):
    for path, rel in pairs:
        print(f"{path}\t{rel}")

# 1. The staging tree still has its projects (main run not yet past
#    bcl_project_done, or a hand-staged tree). Use it verbatim.
staged = []
for root, _dirs, files in os.walk(src):
    for name in files:
        if name.endswith('.fastq.gz'):
            full = os.path.join(root, name)
            staged.append((full, os.path.relpath(full, src)))
if staged:
    emit(sorted(staged))
    raise SystemExit(0)

# 2. Recover them from the delivered folders instead. The delivered folder name
#    is the renamed one, so map each FASTQ back to its Sample_Project through the
#    main run's renaming map rather than trying to invert the rename here.
mapping_path = os.path.join(repo, 'results', config_id, f'renaming_map_{config_id}.csv')
if not os.path.exists(mapping_path):
    sys.exit(f"FAIL: {src} holds no FASTQs and {mapping_path} is missing, so the "
             f"delivered folders cannot be mapped back to their Sample_Project.")

sample_project = {}
with open(mapping_path, newline='') as fh:
    for row in csv.DictReader(fh):
        sample = (row.get('Sample_ID') or '').strip()
        project = (row.get('Sample_Project') or '').strip().replace(' ', '_')
        if sample and project:
            sample_project[sample] = project

# A delivered folder carries whichever orientation won for its project, so it is
# only a legitimate source for the seed of that same orientation. Seeding an RC
# folder into .output (or the reverse) would silently hand the variant reads with
# flipped indexes.
try:
    with open(os.path.join(repo, 'logs', config_id,
                           f'orientation_decision_{config_id}.json')) as fh:
        decision = json.load(fh) or {}
except (OSError, ValueError):
    decision = {}

def won(*names):
    for name in names:
        value = decision.get(name)
        if value:
            return 'rc' if str(value).startswith('rc') else 'original'
    return 'original'

delivered_root = os.path.join(repo, 'output', config_id)
recovered, skipped = [], set()
for folder in sorted(os.listdir(delivered_root) if os.path.isdir(delivered_root) else []):
    folder_path = os.path.join(delivered_root, folder)
    if not os.path.isdir(folder_path):
        continue
    for name in sorted(os.listdir(folder_path)):
        if not name.endswith('.fastq.gz'):
            continue
        match = FQ.match(name)
        if not match:
            sys.exit(f"FAIL: cannot parse a Sample_ID out of "
                     f"{os.path.join(folder_path, name)}")
        project = sample_project.get(match.group('sample'))
        if not project:
            sys.exit(f"FAIL: {match.group('sample')} ({name}) is not listed in "
                     f"{mapping_path}, so its Sample_Project is unknown.")
        if won(project, folder) != want:
            skipped.add(folder)
            continue
        recovered.append((os.path.join(folder_path, name),
                          os.path.join(project, name)))

if not recovered:
    detail = (f" ({len(skipped)} delivered folder(s) hold the other orientation: "
              f"{', '.join(sorted(skipped))})" if skipped else "")
    sys.exit(f"FAIL: found no {want}-orientation FASTQs in {src} or under "
             f"{delivered_root}{detail}.")

emit(recovered)
PY
}

# Copy one finished DRAGEN output tree into a variant, truncating R2 to $3 bases.
# R2 at a shorter mask is an exact prefix of the long-mask R2, so this reproduces
# what DRAGEN would have written for that OverrideCycles. R1/I1/I2 are unchanged
# and hardlinked when the filesystem allows it. $4 is the orientation this tree
# represents ("original" for .output, "rc" for .output_rc).
seed_conversion_dir() {
    local src="$1" dst="$2" keep="$3" orientation="${4:-original}"
    mkdir -p "$dst"
    rsync -a --delete --exclude '*.fastq.gz' --exclude '.done' "$src/" "$dst/"
    echo "Seeding $(basename "$(dirname "$dst")")/$(basename "$dst") (R2 -> ${keep} bp)..."
    local seeded=0
    while IFS=$'\t' read -r fq rel; do
        [ -n "$fq" ] || continue
        local out="$dst/$rel"
        mkdir -p "$(dirname "$out")"
        rm -f "$out"
        case "$rel" in
            *_R2_001.fastq.gz)
                seqtk trimfq -L "$keep" "$fq" | pigz -p "$CORES" > "$out"
                ;;
            *)
                # R1/I1/I2 are byte-identical across variants, so hardlink them.
                # Under the delivery fallback that link points at a customer file;
                # safe because nothing in the workflow rewrites a FASTQ in place
                # (normalize_project_fastq_names renames, and no-ops for 10x).
                ln "$fq" "$out" 2>/dev/null || cp -p "$fq" "$out"
                ;;
        esac
        seeded=$((seeded + 1))
    done < <(resolve_fastq_sources "$src" "$orientation")

    # An empty seed is the worst possible outcome, and the quietest: `touch .done`
    # right below tells snakemake the conversion is complete, so the variant runs
    # the whole workflow against no reads, creates an empty delivery folder, mails
    # an order report, and only falls over at fastp 20 jobs later.
    if [ "$seeded" -eq 0 ]; then
        echo "ERROR: seeded no FASTQs into $dst — refusing to mark the conversion done." >&2
        exit 1
    fi
    echo "  seeded $seeded FASTQ file(s)."
}

if [ ! -f "$MAIN_OUT/.done" ]; then
    echo "ERROR: $MAIN_OUT/.done missing — the main run has not finished $CONFIG_ID yet."
    echo "       The sweep reuses that conversion; run it after the main run."
    exit 1
fi

# The reads themselves may live in either tree by now, so require that at least
# one of them actually has some before building anything.
if [ "$(find "$MAIN_OUT" "$REPO/output/$CONFIG_ID" -name '*.fastq.gz' -print -quit 2>/dev/null | wc -l)" -eq 0 ]; then
    echo "ERROR: no FASTQs under $MAIN_OUT or $REPO/output/$CONFIG_ID."
    echo "       Nothing to seed the variants from."
    exit 1
fi

# Physical R2 cycle count, read from the normalized RunInfo (last non-index read).
R2_PHYSICAL="$(python - "$DATA_DIR/RunInfo.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
reads = [r for r in ET.parse(sys.argv[1]).getroot().iter("Read")
         if r.get("IsIndexedRead") == "N"]
print(reads[-1].get("NumCycles"))
PY
)"
echo "Physical R2 cycles: $R2_PHYSICAL"

mkdir -p sweeps
[ -f sweeps/.gitignore ] || printf '*\n!.gitignore\n' > sweeps/.gitignore

for N in "${VARIANTS[@]}"; do
    if [ "$N" -gt "$R2_PHYSICAL" ]; then
        echo "ERROR: requested R2:$N exceeds the physical $R2_PHYSICAL cycles"; exit 1
    fi

    TAG="R2-${N}"
    WORK="$REPO/sweeps/${LIBRARY}_L${LANE}_${TAG}"
    VARIANT_XLSX_NAME="$(basename "${BASE_METADATA%.xlsx}")_L${LANE}_${TAG}.xlsx"

    echo
    echo "=================================================================="
    echo "variant $TAG  ->  $WORK"
    echo "=================================================================="

    if [ -z "${SWEEP_FORCE:-}" ] && compgen -G "$WORK/Reports/order_*/index.html" > /dev/null; then
        echo "already built (order report present); set SWEEP_FORCE=1 to rebuild. Skipping."
        continue
    fi

    # ---- workdir skeleton -------------------------------------------------
    mkdir -p "$WORK"/{metadata,results,output,.output,Reports,logs,benchmarks}
    for item in Snakefile src scripts profiles pixi.toml pixi.lock snakemake_config.yaml .env; do
        [ -e "$REPO/$item" ] && ln -sfn "$REPO/$item" "$WORK/$item"
    done

    # ---- variant workbook -------------------------------------------------
    # The Lab ID suffix is what makes the delivered folder unique:
    # {Lab ID}_{Order ID}_{library}_L{lane}_G{group}.
    # --set-r2 rewrites only the R2 term, so R1/I1/I2 stay exactly as the run
    # specified them for this lane/group.
    python src/make_masking_variant_xlsx.py \
        --base "$BASE_METADATA" \
        --out "$WORK/metadata/$VARIANT_XLSX_NAME" \
        --lane "$LANE" --group "$GROUP" \
        --set-r2 "$N" \
        --lab-id-suffix "$TAG"

    # ---- variant config ---------------------------------------------------
    # Restricted to this lane, and addressed to the operator: three extra runs
    # must never mail the customer. Config beats the EMAIL_* env vars from .env.
    python - "$PROJECT_CONFIG" "$WORK/snakemake_config_project.yaml" \
             "metadata/$VARIANT_XLSX_NAME" "$LANE" "$SWEEP_EMAIL" <<'PY'
import sys, yaml
src, dst, metadata, lane, email = sys.argv[1:6]
cfg = yaml.safe_load(open(src)) or {}
cfg["metadata"] = metadata
cfg["lanes"] = [int(lane)]
cfg["bcl_convert_order"] = [f"lane{int(lane)}"]
cfg["email_recipient"] = email
cfg["email_cc"] = email
if not str(cfg.get("email_sender") or "").strip():
    cfg["email_sender"] = email
with open(dst, "w") as fh:
    yaml.safe_dump(cfg, fh, sort_keys=False, default_flow_style=False)
PY

    # ---- 1. samplesheets only --------------------------------------------
    # Must happen BEFORE .done is touched: the profile pins rerun-triggers=mtime,
    # so .done has to end up newer than every bcl_convert input.
    snakemake -d "$WORK" --cores "$CORES" \
        "results/$CONFIG_ID/SampleSheet_${CONFIG_ID}_validated.csv" \
        "results/$CONFIG_ID/renaming_map_${CONFIG_ID}.csv"

    python - "$WORK/results/$CONFIG_ID/SampleSheet_${CONFIG_ID}_validated.csv" "$N" <<'PY'
import csv, sys
path, n = sys.argv[1], int(sys.argv[2])
with open(path) as fh:
    lines = fh.read().splitlines()
start = next(i for i, l in enumerate(lines)
             if l.startswith("[BCLConvert_Data]") or l.startswith("[Data]"))
rows = list(csv.DictReader(lines[start + 1:]))
cycles = {}
for r in rows:
    oc = (r.get("OverrideCycles") or "").strip()
    if oc:
        cycles[oc] = cycles.get(oc, 0) + 1
if not cycles:
    sys.exit(f"FAIL: no OverrideCycles column in {path}")
# A lane can carry several masking groups; only the variant's own group has to
# have moved to Y{n}. Everything else must be left alone.
matched = {oc: c for oc, c in cycles.items() if oc.split(";")[-1].startswith(f"Y{n}")}
if not matched:
    sys.exit(f"FAIL: no OverrideCycles in {path} ends in a Y{n} R2 segment: {sorted(cycles)}")
for oc, count in sorted(cycles.items()):
    mark = "<- variant" if oc in matched else ""
    print(f"OverrideCycles: {oc}  ({count} samples) {mark}")
PY

    # ---- 2. seed .output from the main run, truncating R2 ------------------
    SEED="$WORK/.output/$CONFIG_ID"
    seed_conversion_dir "$MAIN_OUT" "$SEED" "$N" original

    # ---- 3. mark the conversion complete ----------------------------------
    touch "$SEED/.done"

    # ---- 4. the RC (reverse-complement index) pass ------------------------
    # analyze_undetermined -> detect_rc_candidates run off the seeded .output, so
    # the variant reaches the same verdict as the main run. Build the RC sheet and
    # candidate list first, then seed .output_rc and touch its .done last, so
    # bcl_convert_rc has nothing newer to react to. Orientation is decided by the
    # indexes, which no masking variant changes.
    snakemake -d "$WORK" --cores "$CORES" \
        "logs/$CONFIG_ID/rc_candidates_${CONFIG_ID}.json" \
        "results/$CONFIG_ID/SampleSheet_${CONFIG_ID}_rc_validated.csv"

    RC_SEED="$WORK/.output_rc/$CONFIG_ID"
    if python -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1])) else 1)" \
            "$WORK/logs/$CONFIG_ID/rc_candidates_${CONFIG_ID}.json"; then
        # Suspects exist, so bcl_convert_rc would launch DRAGEN again. Reuse the
        # main run's RC conversion instead.
        if [ ! -f "$MAIN_RC_OUT/.done" ]; then
            echo "ERROR: RC candidates found for $CONFIG_ID but $MAIN_RC_OUT/.done is missing."
            echo "       Let the main run finish its RC pass first; otherwise this variant"
            echo "       would re-run DRAGEN on the FPGA."
            exit 1
        fi
        echo "RC suspects present; seeding .output_rc from the main run."
        seed_conversion_dir "$MAIN_RC_OUT" "$RC_SEED" "$N" rc
    else
        # No suspects: bcl_convert_rc creates the directory and returns without
        # touching DRAGEN. Nothing to copy.
        echo "No RC suspects for $CONFIG_ID."
        mkdir -p "$RC_SEED"
    fi
    touch "$RC_SEED/.done"

    # ---- 5. prove DRAGEN will not re-run ----------------------------------
    DRY="$(snakemake -d "$WORK" -n 2>&1)"
    if grep -qE '^rule bcl_convert(_rc)?:' <<< "$DRY"; then
        echo "ERROR: a bcl_convert job is still scheduled for $TAG:"
        grep -E '^rule bcl_convert(_rc)?:' <<< "$DRY"
        echo "       A .done file is older than one of its inputs. Re-touch"
        echo "       $SEED/.done and $RC_SEED/.done, then re-check."
        exit 1
    fi

    if [ -n "${SWEEP_STOP_AFTER_SEED:-}" ]; then
        echo "SWEEP_STOP_AFTER_SEED set; stopping before the pipeline run for $TAG."
        continue
    fi

    # ---- 6. full pipeline for this variant --------------------------------
    snakemake -d "$WORK" --cores "$CORES"
    echo "variant $TAG complete: $WORK"
done

echo
echo "Sweep done. Baseline (R2:90) is the main run's own $CONFIG_ID output."
echo "Compare with: bash scripts/masking_sweep_report.sh"
