#!/bin/bash
# Direct-to-share setup: make this run dir's bulk data dirs symlinks into the
# Nextcloud share, so FASTQs are written there from the start and the links the
# pipeline emails are already final (no `pixi run publish` copy afterwards).
#
# Run from the run dir (.../<instrument>/<run_id>), after `pixi run init`:
#   pixi run link-share                          # share root /mnt/jbod2_main/nextshare/bcl_convert
#   pixi run link-share /some/other/nextshare/bcl_convert
#
# For each of output/ .output/ .output_rc/ sweeps/ it creates
# <root>/<instrument>/<run_id>/<dir> and replaces the local dir with a symlink to
# it. .output* sit beside output on purpose: bcl_project_done moves projects from
# .output into output, which is only a rename on one filesystem. sweeps/ goes too,
# so masking_sweep.sh can hardlink FASTQs out of output/ instead of copying them.
#
# It then sets share_output_root and the Nextcloud mapping (Jbod2 / nextshare) in
# snakemake_config_project.yaml. The Snakefile refuses to start if share_output_root
# is set but the links are missing or point elsewhere.
#
# Idempotent: links that already point at the right place are left alone. It will
# not replace a local dir that already holds data -- move that by hand first.
#
# CAUTION once linked: `rm -rf output` removes only the link, but
# `rm -rf output/` (trailing slash) deletes the data on the share.
set -euo pipefail
umask 0002  # share dirs are group-shared (grthcloud)

DATA_DIRS=(output .output .output_rc sweeps)  # keep in sync with src/share_paths.py
CONFIG=snakemake_config_project.yaml

share_root="${1:-/mnt/jbod2_main/nextshare/bcl_convert}"
nc_dir_name="${NC_DIR_NAME:-Jbod2}"
nc_dir_path="${NC_DIR_PATH:-nextshare}"

run_dir="$PWD"
run_id="$(basename "$run_dir")"
instrument="$(basename "$(dirname "$run_dir")")"
dest="${share_root%/}/${instrument}/${run_id}"

say() { printf '[link-share] %s\n' "$*"; }
die() { printf '[link-share] ERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$run_dir/Snakefile" ]] || die "run from the run dir (no Snakefile in $run_dir)"
[[ -f "$CONFIG" ]] || die "$CONFIG missing -- run \`pixi run init\` first"
case "$share_root/" in
    */"$nc_dir_path"/*) ;;
    *) die "share root $share_root is not under a /$nc_dir_path/ dir, so share links could not be mapped to /$nc_dir_name/ (set NC_DIR_PATH/NC_DIR_NAME)" ;;
esac
# The /<nc_dir_path> dir itself must already exist: it is the mount point Nextcloud
# serves. Anything below it (e.g. bcl_convert/) is created here on first use. This
# keeps an unmounted share from silently filling the empty mount-point dir.
share_mount="${share_root%%/"$nc_dir_path"/*}/$nc_dir_path"
[[ -d "$share_mount" ]] || die "$share_mount does not exist (share not mounted?)"
mkdir -p "$share_root" || die "cannot create $share_root"
[[ -w "$share_root" ]] || die "share root $share_root is not writable by $(whoami)"

say "run:  $instrument/$run_id"
say "dest: $dest"

# Validate every dir before changing any, so a refusal leaves the run dir as it was.
declare -a todo=()
for d in "${DATA_DIRS[@]}"; do
    target="$dest/$d"
    if [[ -L "$d" ]]; then
        current="$(readlink -f "$d" || true)"
        if [[ "$current" == "$(readlink -m "$target")" ]]; then
            say "ok    $d -> $target"
            continue
        fi
        die "$d is already a symlink to ${current:-<dangling>}, not $target"
    fi
    if [[ -e "$d" && ! -d "$d" ]]; then
        die "$d exists and is not a directory"
    fi
    if [[ -d "$d" ]] && [[ -n "$(find "$d" -mindepth 1 ! -name .gitignore -print -quit)" ]]; then
        die "$d already holds data; move it to $target by hand, then re-run"
    fi
    todo+=("$d")
done

for d in "${todo[@]}"; do
    target="$dest/$d"
    mkdir -p "$target"
    if [[ -d "$d" ]]; then
        # The tracked placeholder .gitignore goes with the data, so the share
        # dir ignores its contents the same way the repo dir did.
        [[ -f "$d/.gitignore" && ! -e "$target/.gitignore" ]] && cp -p "$d/.gitignore" "$target/.gitignore"
        rm -f "$d/.gitignore"
        rmdir "$d"
    fi
    ln -s "$target" "$d"
    say "link  $d -> $target"
done

# output/.gitignore and sweeps/.gitignore are tracked; behind a symlink git reports
# them deleted. skip-worktree keeps `git status` clean without touching the index.
if git -C "$run_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    mapfile -t tracked < <(git -C "$run_dir" ls-files -- "${DATA_DIRS[@]/%//.gitignore}" 2>/dev/null || true)
    if (( ${#tracked[@]} )); then
        git -C "$run_dir" update-index --skip-worktree -- "${tracked[@]}"
        say "git skip-worktree: ${tracked[*]}"
    fi
fi

set_key() {
    local key="$1" value="$2"
    if grep -q "^${key}:" "$CONFIG"; then
        sed -i "s|^${key}:.*|${key}: \"${value}\"|" "$CONFIG"
    else
        printf '%s: "%s"\n' "$key" "$value" >> "$CONFIG"
    fi
    say "config ${key}: \"${value}\""
}
set_key share_output_root "${share_root%/}"
set_key nextcloud_dir_name "$nc_dir_name"
set_key nextcloud_dir_path "$nc_dir_path"

say "done. Data dirs now live under $dest"
say "share links will resolve to /$nc_dir_name/${dest#*/"$nc_dir_path"/}/output/..."
say "publish is not needed for this run; resend emails with \`pixi run send-emails\`."
