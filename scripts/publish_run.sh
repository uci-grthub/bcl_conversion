#!/bin/bash
# Publish a completed run: mirror it to the NFS/JBOD share, then (re)send the
# per-order download emails. Run from the run directory after `pixi run all`:
#   pixi run publish                                            # instrument/run_id from cwd
#   pixi run publish NovaSeqx xR101
#   PARALLEL=4 pixi run publish NovaSeqx xR101 /mnt/usb false   # extra sync_run args pass through
#
# Steps (2 and 3 run IN THE MIRROR, not in the source run dir):
#   1. sync_run <instrument> <run_id> [dest] [parallel]  -- rsync mirror to share
#   2. snakemake --touch all         -- mark outputs current (rsync bumps mtimes)
#   3. snakemake -n --forcerun send_order_email  -- preview the re-send
#
# Step 2 is required: rsync -a preserves mtimes but the mirror's own .snakemake
# metadata is from an earlier run (.snakemake is excluded from the sync), so the
# DAG in the mirror is not complete -- without --touch, snakemake would re-run
# fastp/md5/plots for every sample. --touch only stamps outputs that exist; the
# deliberately unsynced ones (Reports/, logs/*link*) just warn and stay pending,
# so project_link/report_order_id/send_order_email still rebuild against the
# Jbod2 share.
#
# Step 3 is a dry run on purpose: emails are irreversible. Review the plan, then
# run the real send from the mirror:
#   cd <dest> && snakemake --cores 8 --forcerun send_order_email
set -euo pipefail

# Everything below is echoed to the terminal AND appended to a publish log in
# the source run dir, so a long parallel rsync can be reviewed after the fact.
PUBLISH_LOG="${PUBLISH_LOG:-$PWD/logs/publish_$(date +%Y%m%dT%H%M%S).log}"
mkdir -p "$(dirname "$PUBLISH_LOG")"
exec > >(tee -a "$PUBLISH_LOG") 2>&1

say() { printf '[publish %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
step() { printf '\n[publish %s] ===== %s =====\n' "$(date +%H:%M:%S)" "$*"; }
elapsed() { printf '%dm%02ds' $(( ($2 - $1) / 60 )) $(( ($2 - $1) % 60 )); }

PUBLISH_START=$(date +%s)
say "log: $PUBLISH_LOG"
say "host: $(hostname)  user: $(whoami)"
say "snakemake: $(snakemake --version 2>/dev/null || echo 'NOT ON PATH')  profile: ${SNAKEMAKE_PROFILE:-<unset>}"

# sync_run is a shell function, not on PATH -- source the in-repo copy.
# shellcheck source=scripts/sync_run.sh
source "$(dirname "${BASH_SOURCE[0]}")/sync_run.sh"

# No instrument/run_id given: derive them from the run dir we were invoked in
# (.../<instrument>/<run_id>), so a bare `pixi run publish` works. Any extra
# args (dest_base, parallel) still pass through after the derived pair.
if [[ $# -eq 1 ]]; then
    echo "ERROR: got one arg ($1) -- pass both <instrument> <run_id>, or neither" >&2
    exit 1
fi
if [[ $# -eq 0 ]]; then
    run_dir="$PWD"
    derived_run_id="$(basename "$run_dir")"
    derived_instrument="$(basename "$(dirname "$run_dir")")"
    if [[ -z "$derived_instrument" || "$derived_instrument" == "/" || -z "$derived_run_id" ]]; then
        echo "ERROR: cannot derive instrument/run_id from $run_dir -- pass them explicitly" >&2
        exit 1
    fi
    say "no run given; using instrument=$derived_instrument run_id=$derived_run_id (from $run_dir)"
    set -- "$derived_instrument" "$derived_run_id" "$@"
fi

step "step 1/3: rsync mirror to share"
say "args: $*"
say "PARALLEL=${PARALLEL:-2}"
t0=$(date +%s)
SYNC_RUN_DEST=""
sync_run "$@"
t1=$(date +%s)
say "step 1/3 done in $(elapsed "$t0" "$t1")"

if [[ -z "$SYNC_RUN_DEST" || ! -d "$SYNC_RUN_DEST" ]]; then
    echo "ERROR: sync_run did not report a destination directory" >&2
    exit 1
fi

# Already inside the pixi env (snakemake + SNAKEMAKE_PROFILE on PATH/env);
# SNAKEMAKE_PROFILE is relative, so it resolves to the mirror's own profile.
cd "$SYNC_RUN_DEST"
say "mirror size: $(du -sh . 2>/dev/null | cut -f1)"

step "step 2/3: snakemake --touch all (in $SYNC_RUN_DEST)"
say "stamps synced outputs current; unsynced ones (Reports/, logs/*link*) warn and stay pending"
t0=$(date +%s)
snakemake --touch --show-failed-logs all
t1=$(date +%s)
say "step 2/3 done in $(elapsed "$t0" "$t1")"

step "step 3/3: snakemake --forcerun send_order_email (in $SYNC_RUN_DEST)"
say "pending work after touch:"
snakemake -n --quiet rules --forcerun send_order_email 2>&1 | sed 's/^/    /'
t0=$(date +%s)
snakemake -p --show-failed-logs --forcerun send_order_email
t1=$(date +%s)
say "step 3/3 done in $(elapsed "$t0" "$t1")"

say "emails sent this run:"
find Reports -name email_sent.done -newermt "@$PUBLISH_START" -printf '    %p\n' 2>/dev/null | sort

say "PUBLISH COMPLETE in $(elapsed "$PUBLISH_START" "$(date +%s)")  mirror: $SYNC_RUN_DEST"
say "log: $PUBLISH_LOG"
