#!/bin/bash
# Publish a completed run: mirror it to the NFS/JBOD share, then (re)send the
# per-order download emails. Run from the run directory after `pixi run all`:
#   pixi run publish                                            # instrument/run_id from cwd
#   pixi run publish NovaSeqx xR101
#   PARALLEL=4 pixi run publish NovaSeqx xR101 /mnt/usb false   # extra sync_run args pass through
#
# Steps 3-6 run IN THE MIRROR, not in the source run dir:
#   1. sync_run <instrument> <run_id> [dest] [parallel]  -- rsync mirror to share
#   2. verify_mirror.py              -- every FASTQ in the mirror's md5sums.txt is
#                                       present and matches the source size
#   3. dedupe_mirror.py --apply      -- hardlink byte-identical FASTQs together
#   4. snakemake --touch all         -- mark outputs current (rsync bumps mtimes)
#   5. snakemake --forcerun send_order_email  -- re-send the per-order emails
#   6. the same, once per masking-sweep variant under sweeps/
#
# Step 2 exists because step 4 is dangerous on an incomplete mirror: --touch
# stamps outputs current WITHOUT reading them, so a dropped or truncated transfer
# is blessed as good, the per-project md5sums.txt is never recomputed, and the
# share link points at a short FASTQ. Verify before touching, never after.
# Set VERIFY_MD5=1 to re-verify every checksum instead of just sizes (slow).
#
# Step 4 is required: rsync -a preserves mtimes but the mirror's own .snakemake
# metadata is from an earlier run (.snakemake is excluded from the sync), so the
# DAG in the mirror is not complete -- without --touch, snakemake would re-run
# fastp/md5/plots for every sample. --touch only stamps outputs that exist; the
# deliberately unsynced ones (Reports/, logs/*link*) just warn and stay pending,
# so project_link/report_order_id/send_order_email still rebuild against the
# Jbod2 share. Step 6 does the same --touch inside each sweep variant, for the
# same reason.
#
# Step 3 runs after step 2, never before: it rewrites directory entries, and there
# is no point doing that to a mirror that has not been shown to be complete. It is
# the counterpart to the -H rsync only gets in sync_run's sequential pass -- that
# keeps a masking sweep's variants linked to each other, and this links them to the
# delivery they were seeded from, which arrives in a different rsync invocation.
# Set SKIP_DEDUPE=1 to leave the mirror expanded.
#
# Steps 5 and 6 really send. Step 5 covers the run's own orders; it does NOT
# reach the sweeps, because each variant is a separate snakemake workdir and the
# root Snakefile has no knowledge of sweeps/. Step 6 walks them explicitly.
# Set SKIP_SWEEP_EMAILS=1 to publish the variants' data without mailing them.
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

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "step 1/6: rsync mirror to share"
say "args: $*"
say "PARALLEL=${PARALLEL:-2}"
t0=$(date +%s)
SYNC_RUN_DEST=""
SYNC_RUN_SRC=""
sync_run "$@"
t1=$(date +%s)
say "step 1/6 done in $(elapsed "$t0" "$t1")"

if [[ -z "$SYNC_RUN_DEST" || ! -d "$SYNC_RUN_DEST" ]]; then
    echo "ERROR: sync_run did not report a destination directory" >&2
    exit 1
fi

step "step 2/6: verify mirror against source (in $SYNC_RUN_DEST)"
say "checks every FASTQ listed in the mirror's md5sums.txt files; must pass BEFORE --touch"
t0=$(date +%s)
VERIFY_ARGS=("$SYNC_RUN_DEST")
if [[ -n "$SYNC_RUN_SRC" && -d "$SYNC_RUN_SRC" ]]; then
    VERIFY_ARGS+=(--src "$SYNC_RUN_SRC")
else
    say "WARNING: source dir unknown; falling back to an existence/non-empty check only"
fi
if [[ "${VERIFY_MD5:-0}" == "1" ]]; then
    say "VERIFY_MD5=1: re-verifying every checksum (this reads all the data)"
    VERIFY_ARGS+=(--md5)
fi
python3 "$REPO_DIR/scripts/verify_mirror.py" "${VERIFY_ARGS[@]}"
t1=$(date +%s)
say "step 2/6 done in $(elapsed "$t0" "$t1")"

# Already inside the pixi env (snakemake + SNAKEMAKE_PROFILE on PATH/env);
# SNAKEMAKE_PROFILE is relative, so it resolves to the mirror's own profile.
cd "$SYNC_RUN_DEST"
say "mirror size: $(du -sh . 2>/dev/null | cut -f1)"

step "step 3/6: hardlink byte-identical FASTQs (in $SYNC_RUN_DEST)"
if [[ "${SKIP_DEDUPE:-0}" == "1" ]]; then
    say "SKIP_DEDUPE=1: leaving the mirror expanded"
else
    say "uses the md5sums.txt already in each delivered project; reads no FASTQ data"
    t0=$(date +%s)
    # Not fatal: a mirror that failed to deduplicate is merely larger than it needs
    # to be, and the emails in step 5 are the part the customer is waiting on.
    if ! python3 "$REPO_DIR/scripts/dedupe_mirror.py" "$SYNC_RUN_DEST" --apply --quiet; then
        say "WARNING: dedupe reported problems (see above); mirror is intact but not fully linked"
    fi
    t1=$(date +%s)
    say "step 3/6 done in $(elapsed "$t0" "$t1")"
    say "mirror size after dedupe: $(du -sh . 2>/dev/null | cut -f1)"
fi

step "step 4/6: snakemake --touch all (in $SYNC_RUN_DEST)"
say "stamps synced outputs current; unsynced ones (Reports/, logs/*link*) warn and stay pending"
t0=$(date +%s)
snakemake --touch --show-failed-logs all
t1=$(date +%s)
say "step 4/6 done in $(elapsed "$t0" "$t1")"

step "step 5/6: snakemake --forcerun send_order_email (in $SYNC_RUN_DEST)"
# send_order_email short-circuits on Reports/order_*/.email_receipt. That receipt
# exists so a bare `snakemake` on a finished run stops re-mailing every order:
# the rule sits behind the pick_orientation checkpoint and is scheduled on every
# DAG build whether or not it has anything to do, and mail is not idempotent.
# Publishing is the deliberate case, so clear the receipts first -- otherwise
# --forcerun would run the rule and the rule would decline to send. Step 6 clears
# each variant's for the same reason.
say "clearing email receipts so --forcerun really sends"
rm -f Reports/order_*/.email_receipt
say "pending work after touch:"
snakemake -n --quiet rules --forcerun send_order_email 2>&1 | sed 's/^/    /'
t0=$(date +%s)
snakemake -p --show-failed-logs --forcerun send_order_email
t1=$(date +%s)
say "step 5/6 done in $(elapsed "$t0" "$t1")"

step "step 6/6: order emails for masking-sweep variants (in $SYNC_RUN_DEST)"
shopt -s nullglob
sweep_dirs=(sweeps/*/)
shopt -u nullglob
if [[ "${SKIP_SWEEP_EMAILS:-0}" == "1" ]]; then
    say "SKIP_SWEEP_EMAILS=1: not mailing the ${#sweep_dirs[@]} variant(s)"
elif [[ ${#sweep_dirs[@]} -eq 0 ]]; then
    say "no sweeps/ variants in this run"
else
    say "${#sweep_dirs[@]} variant(s); each is its own snakemake workdir (-d)"
    t0=$(date +%s)
    for sweep in "${sweep_dirs[@]}"; do
        sweep="${sweep%/}"
        say "--- $sweep"
        # Reports/ and .snakemake are both excluded from the mirror, so a variant
        # here has neither sentinels nor DAG metadata. Without --touch first, the
        # forcerun below decides fastp, the plots and the md5sums are all out of
        # date and rebuilds the variant from its FASTQs.
        if ! snakemake -d "$sweep" --touch --show-failed-logs all; then
            say "WARNING: --touch failed for $sweep; skipping its email"
            continue
        fi
        rm -f "$sweep"/Reports/order_*/.email_receipt
        # report_order_id is forced alongside the email: --touch above stamps an
        # existing index.html current, so without this a variant whose report was
        # built from incomplete data would simply be re-mailed unchanged.
        if ! snakemake -d "$sweep" -p --show-failed-logs \
                --forcerun report_order_id send_order_email; then
            say "WARNING: send_order_email failed for $sweep"
        fi
    done
    t1=$(date +%s)
    say "step 6/6 done in $(elapsed "$t0" "$t1")"
fi

say "emails sent this run:"
find Reports sweeps/*/Reports -name email_sent.done -newermt "@$PUBLISH_START" \
    -printf '    %p\n' 2>/dev/null | sort

say "PUBLISH COMPLETE in $(elapsed "$PUBLISH_START" "$(date +%s)")  mirror: $SYNC_RUN_DEST"
say "log: $PUBLISH_LOG"
