#!/bin/bash
# Repoint a mirrored run's symlinks at the mirror itself.
#
# A masking sweep's workdir is a thin clone of the run: Snakefile, src, scripts,
# profiles, pixi.toml/lock and snakemake_config.yaml are absolute symlinks back to
# the run directory it was created in. rsync copies a symlink verbatim -- target
# string and all -- so in the mirror those still point into /staging, and they
# dangle the moment the staging run is cleared.
#
# The delivered FASTQs are real files and are unaffected; what breaks is re-running
# snakemake inside a mirrored variant, and any tool that follows the links.
#
#   bash scripts/relink_mirror.sh <mirror_dir>           # dry run
#   bash scripts/relink_mirror.sh <mirror_dir> --apply
#
# New links are written RELATIVE (../../Snakefile), not absolute, so the share
# stays self-contained if it is ever moved, remounted at another path, or copied
# to a USB disk. Idempotent: a link already pointing inside the mirror is rewritten
# to the same relative target.
set -euo pipefail

MIRROR="${1:-}"
if [[ -z "$MIRROR" || "$MIRROR" == --* ]]; then
    echo "Usage: relink_mirror.sh <mirror_dir> [--apply]" >&2
    exit 1
fi
shift
APPLY=0
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 1 ;;
    esac
done

[[ -d "$MIRROR" ]] || { echo "not a directory: $MIRROR" >&2; exit 1; }
MIRROR="$(cd "$MIRROR" && pwd)"

# The run is identified by the last two path components (<instrument>/<run_id>),
# which are identical in the source and in the mirror. Any absolute symlink whose
# target contains that pair belongs to this run and can be mapped across.
RUN_ID="$(basename "$MIRROR")"
INSTRUMENT="$(basename "$(dirname "$MIRROR")")"
MARKER="/${INSTRUMENT}/${RUN_ID}/"

echo "mirror: $MIRROR"
echo "run:    ${INSTRUMENT}/${RUN_ID}"
echo "mode:   $([[ $APPLY == 1 ]] && echo APPLY || echo 'dry run')"
echo

# maxdepth 3 reaches the run root and sweeps/<variant>/<link> without descending
# into output/<lane>/<project>/, which holds tens of thousands of FASTQs and no
# symlinks. Walking the whole mirror over NFS takes minutes; this takes a second.
changed=0
scanned=0
while IFS= read -r -d '' link; do
    scanned=$((scanned + 1))
    target="$(readlink "$link")"
    case "$target" in
        /*"$MARKER"*) ;;
        *) continue ;;
    esac

    # Everything after <instrument>/<run_id>/ is the path within the run, and it
    # names the same file in the mirror.
    suffix="${target#*"$MARKER"}"
    absolute="$MIRROR/$suffix"
    relative="$(realpath -m --relative-to="$(dirname "$link")" "$absolute")"

    if [[ "$target" == "$relative" ]]; then
        continue
    fi
    if [[ ! -e "$absolute" ]]; then
        echo "  SKIP ${link#"$MIRROR"/}: $absolute does not exist in the mirror" >&2
        continue
    fi

    echo "  ${link#"$MIRROR"/}"
    echo "      was $target"
    echo "      now $relative"
    changed=$((changed + 1))
    if [[ $APPLY == 1 ]]; then
        ln -sfn "$relative" "$link"
    fi
done < <(find "$MIRROR" -maxdepth 3 -type l -print0 2>/dev/null)

echo
echo "scanned $scanned symlink(s); $([[ $APPLY == 1 ]] && echo repointed || echo 'would repoint') $changed"
if [[ $APPLY == 0 && $changed -gt 0 ]]; then
    echo "Dry run: nothing was modified. Re-run with --apply."
fi
