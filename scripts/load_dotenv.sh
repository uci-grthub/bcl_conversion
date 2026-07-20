#!/bin/bash
# Sourced by pixi as an activation script (see [activation] in pixi.toml).
# Loads the required secrets so every `pixi run ...` has them — no manual
# `set -a; source .env; set +a`, and normally no per-run .env at all.
#
# Search order (later wins), all optional:
#   1. ../.env  — shared per-platform secrets (NovaSeqX/.env, MiSeqi100/.env).
#                 This is the normal source; a fresh clone needs no local .env.
#   2. ~/.env   — user-specific secrets (own NEXTCLOUD_PASSWORD, etc.); overrides
#                 the shared file so each operator runs under their own account.
#   3. ./.env   — per-run override, for one-off credentials in this run dir.
#
# Runs at the pixi manifest root (the run directory). If none exists the
# Snakefile still fails fast with a clear "required environment variable(s) not
# set" message.
set -a
[ -f ../.env ]      && . ../.env
[ -f "$HOME/.env" ] && . "$HOME/.env"
[ -f ./.env ]       && . ./.env
set +a

# Re-pin the workflow profile regardless of anything a sourced .env set. A
# shared ../.env may export SNAKEMAKE_PROFILE pointing at a personal global
# profile; the repo's profiles/default is the one that serializes DRAGEN and
# pins rerun-triggers, and it must win for every operator.
export SNAKEMAKE_PROFILE="profiles/default"
