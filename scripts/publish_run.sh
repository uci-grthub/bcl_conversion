#!/bin/bash
# Publish a completed run: mirror it to the NFS/JBOD share, then (re)send the
# per-order download emails. Run from the run directory after `pixi run all`:
#   pixi run publish NovaSeqx xR101
#   PARALLEL=4 pixi run publish NovaSeqx xR101 /mnt/usb false   # extra sync_run args pass through
#
# Steps:
#   1. sync_run <instrument> <run_id> [dest] [parallel]  -- rsync mirror to share
#   2. snakemake --touch all         -- mark outputs current (rsync bumps mtimes)
#   3. snakemake --forcerun send_order_email  -- re-emit emails after data is on share
set -euo pipefail

# sync_run is a shell function, not on PATH -- source the in-repo copy.
# shellcheck source=scripts/sync_run.sh
source "$(dirname "${BASH_SOURCE[0]}")/sync_run.sh"

sync_run "$@"

# Already inside the pixi env (snakemake + SNAKEMAKE_PROFILE on PATH/env).
snakemake --touch all
snakemake --forcerun send_order_email
