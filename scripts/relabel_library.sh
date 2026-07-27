#!/bin/bash
# relabel_library -- fix a run whose artifacts were produced under the wrong
# library_name (e.g. the project config still said xR102 while the run is xR103).
#
# Renames every path containing <old> to <new> and rewrites <old> inside the
# text files that reference those paths (md5sums.txt, report HTML, link YAMLs,
# samplesheets, count CSVs). FASTQ payloads are renamed, never rewritten --
# their md5s are unchanged by a rename, so md5sums.txt stays valid once the
# filenames listed in it are updated.
#
#   bash scripts/relabel_library.sh xR102 xR103            # dry run (default)
#   bash scripts/relabel_library.sh xR102 xR103 --apply    # do it
#   bash scripts/relabel_library.sh xR102 xR103 --apply /mnt/.../xR103   # other dir
#
# After --apply, re-stamp the workflow so snakemake sees the new paths as done:
#   pixi run snakemake --touch all
#
# NOT touched: .snakemake/ metadata (keyed on the old paths; stale entries only
# cost "missing provenance" warnings) and .pixi/.
set -euo pipefail

OLD="${1:?Usage: relabel_library.sh <old_library> <new_library> [--apply] [target_dir]}"
NEW="${2:?Usage: relabel_library.sh <old_library> <new_library> [--apply] [target_dir]}"
APPLY=false
TARGET="$PWD"
shift 2
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=true ;;
        *) TARGET="$arg" ;;
    esac
done

[[ -d "$TARGET" ]] || { echo "ERROR: no such directory: $TARGET" >&2; exit 1; }
cd "$TARGET"

say() { printf '[relabel %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
run() { if [[ "$APPLY" == true ]]; then "$@"; else printf '    WOULD: %s\n' "$*"; fi; }

say "target:  $TARGET"
say "rename:  $OLD -> $NEW"
say "mode:    $([[ "$APPLY" == true ]] && echo APPLY || echo 'DRY RUN (pass --apply to execute)')"

# Guard: the config must already declare the new name, otherwise the workflow
# would immediately disagree with the freshly renamed files.
cfg_lib=$(grep -E '^library_name:' snakemake_config_project.yaml 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' || true)
if [[ "$cfg_lib" != "$NEW" ]]; then
    echo "ERROR: snakemake_config_project.yaml has library_name='$cfg_lib', expected '$NEW'." >&2
    echo "       Set it first -- renaming files to a name the workflow does not use makes it worse." >&2
    exit 1
fi
say "config check: library_name='$cfg_lib' OK"

PRUNE=( -path ./.pixi -prune -o -path ./.snakemake -prune -o )

# --- 1. paths ---------------------------------------------------------------
# -depth so children are renamed before their parent directory moves.
mapfile -t paths < <(find . "${PRUNE[@]}" -depth -name "*${OLD}*" -print)
n_dirs=$(find . "${PRUNE[@]}" -depth -name "*${OLD}*" -type d -print | wc -l)
n_files=$(find . "${PRUNE[@]}" -depth -name "*${OLD}*" -type f -print | wc -l)
say "paths to rename: ${#paths[@]} (${n_dirs} dirs, ${n_files} files)"

renamed=0
for p in "${paths[@]}"; do
    dir=$(dirname "$p")
    base=$(basename "$p")
    newbase="${base//$OLD/$NEW}"
    [[ "$base" == "$newbase" ]] && continue
    if [[ -e "$dir/$newbase" ]]; then
        echo "ERROR: target already exists, refusing to clobber: $dir/$newbase" >&2
        exit 1
    fi
    if [[ "$APPLY" == true ]]; then
        mv -n "$p" "$dir/$newbase"
    elif (( renamed < 5 )); then
        printf '    WOULD: mv %s -> %s\n' "$p" "$dir/$newbase"
    fi
    renamed=$((renamed + 1))
done
[[ "$APPLY" == true ]] && say "renamed $renamed paths" || say "would rename $renamed paths (first 5 shown)"

# --- 2. file contents -------------------------------------------------------
# Only the small text artifacts that embed the run/sample names. FASTQ payloads
# are excluded by extension so a multi-GB .gz is never opened.
say "scanning text artifacts for '$OLD' ..."
mapfile -t textfiles < <(
    find . "${PRUNE[@]}" -type f \
        \( -name '*.txt' -o -name '*.html' -o -name '*.yaml' -o -name '*.yml' \
           -o -name '*.csv' -o -name '*.tsv' -o -name '*.json' -o -name '*.log' \
           -o -name '*.bench' -o -name '*.md' \) -print0 \
    | xargs -0 -r grep -l --binary-files=without-match "$OLD" 2>/dev/null || true
)
say "text files containing '$OLD': ${#textfiles[@]}"
if (( ${#textfiles[@]} > 0 )); then
    if [[ "$APPLY" == true ]]; then
        printf '%s\0' "${textfiles[@]}" | xargs -0 -r sed -i "s/${OLD}/${NEW}/g"
        say "rewrote ${#textfiles[@]} files"
    else
        printf '    WOULD: sed -i s/%s/%s/g on %d files, e.g.\n' "$OLD" "$NEW" "${#textfiles[@]}"
        printf '        %s\n' "${textfiles[@]:0:5}"
    fi
fi

# --- 3. leftovers -----------------------------------------------------------
if [[ "$APPLY" == true ]]; then
    left_paths=$(find . "${PRUNE[@]}" -name "*${OLD}*" -print | wc -l)
    say "remaining paths containing '$OLD': $left_paths (expect 0)"
    say "DONE. Next: pixi run snakemake --touch all   (re-stamp the new paths)"
else
    say "DRY RUN complete -- nothing changed. Re-run with --apply."
fi
