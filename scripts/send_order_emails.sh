#!/bin/bash
# Force every order email: the Snakefile generates one send_order_email rule per
# order (send_order_email_<order_id>, plus an unranked send_order_email fallback)
# so each can carry its reverse-sample-sheet priority. `--forcerun
# send_order_email` therefore forces only the fallback; this forces them all.
#
#   send_order_emails.sh [snakemake args...]          # e.g. -n, -d sweeps/x
#   send_order_emails.sh --list [snakemake args...]   # print the rule names only
#
# Orders that still have Reports/order_<id>/.email_receipt are NOT re-sent --
# delete the receipts you want to go out again first:
#   rm Reports/order_*/.email_receipt && pixi run send-emails
set -euo pipefail

list_only=0
if [[ "${1:-}" == "--list" ]]; then
    list_only=1
    shift
fi

mapfile -t rules < <(snakemake "$@" --list-rules 2>/dev/null | grep -E '^send_order_email(_|$)' || true)
if (( ${#rules[@]} == 0 )); then
    echo "ERROR: no send_order_email rules found (snakemake $* --list-rules)" >&2
    exit 1
fi

if (( list_only )); then
    printf '%s\n' "${rules[@]}"
    exit 0
fi

# --forcerun takes every following word, so it goes last.
exec snakemake "$@" --forcerun "${rules[@]}"
