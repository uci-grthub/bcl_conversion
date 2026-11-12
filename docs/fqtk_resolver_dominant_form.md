# fqtk resolver: dominant form can belong to another library

## What happened (xR128, lane 5)

LuptA_Combined_Pool (order 1026I-58) uses 6bp NextFlex single indexes on a lane whose
other projects use 8bp dual indexes. Pool_9's `GTAGAG` is a prefix of MartJ_BGS10's
i7 `GTAGAGGA`. DRAGEN can't separate those, so the pipeline routes LuptA to post-hoc
fqtk demux from Undetermined.

fqtk matches 8 bases, so `scripts/resolve_fqtk_barcodes.py` extends each 6bp barcode
to 8bp using the data. For every short barcode it counts the Undetermined I1 reads
that start with it and keeps the most common full-length form. For Pool_9, in the
first 4M reads:

| I1 form | reads | what it is |
|---|---|---|
| `GTAGAGGA` | 78,521 | MartJ_BGS10 reads DRAGEN left in Undetermined (i5 didn't match) |
| `GTAGAGAT` | 5,962 | Pool_9 itself |

The resolver picked `GTAGAGGA`. That is identical to a sheet index, so it stopped
`fqtk_per_config` with:

```
ERROR: Pool_9: resolved barcode GTAGAGGA is identical to sheet index GTAGAGGA; no rule can separate these two libraries -- they need different indexes
```

The message is wrong for this case. The two libraries *can* be separated: Pool_9's
real form `GTAGAGAT` is 2 mismatches from `GTAGAGGA`. The other 42 pools all
resolved to their 6bp barcode plus `AT` (the adapter bases after a NextFlex index).

## Quick fix used for xR128

A hand-set barcode in `snakemake_config_project.yaml`:

```yaml
fqtk_barcode_overrides:
  lane5:
    Pool_9: GTAGAGAT
```

`fqtk_per_config` passes each entry to the resolver as `--override SAMPLE=BARCODE`.
An override must be target-length and extend the sheet barcode. The resolver doesn't
measure that sample, but the identical-index check and the threshold calculation still
apply to it. For xR128 lane 5 the closest pair came out at 2 mismatches, so fqtk ran
with `--max-mismatches 1 --min-mismatch-delta 2`.

The override has to live in config. Editing `metadata/fqtk_barcodes_<lane>.tsv` does
nothing: `generate_lane_samplesheets` rewrites that file on every Snakemake parse.

## Proper fix (not done yet)

Make the resolver skip candidates that belong to a DRAGEN library instead of failing
on them.

### 1. Exclude sheet indexes before picking the dominant form

In `main()`, after `observed_forms(...)`, drop every candidate whose first
`target_length` bases equal a sheet index (`sheet_indexes`, already loaded):

```python
sheet_8 = {s[: args.target_length] for s in sheet_indexes if len(s) >= args.target_length}
claimed = {seq: n for seq, n in counts.items() if seq[: args.target_length] in sheet_8}
own = Counter({seq: n for seq, n in counts.items() if seq not in claimed})
```

Pick the dominant form from `own`. Compute the `--min-fraction` share against
`sum(own.values())` so the other library's reads don't push a real sample under the
threshold. Log `claimed` so the reason is visible:

```
Pool_9: GTAGAG -> GTAGAGAT (5,962/6,962 own reads, 85.6%); ignored sheet-index forms: GTAGAGGA:78,521
```

The existing "identical to sheet index" error stays for the case where it is true:
nothing is left in `own`, or the only real form is a sheet index.

### 2. Cross-check against the lane's common suffix (optional)

Libraries from one kit share the bases after the index (`AT` for NextFlex here). After
resolving everything, find the most common suffix (`resolved[len(prefix):]`). Warn when
a sample's suffix differs and its own counts contain a prefix+common-suffix form above
some floor. That warns, it doesn't override. It would have flagged this case even
without step 1, and it catches a short barcode whose dominant form comes from index
hopping rather than a sheet index.

### 3. Tests

Extend `tests/test_resolve_fqtk_barcodes.py`:

- dominant form equals a sheet index, a minority form doesn't: resolves to the
  minority form, exit 0. This is the xR128 Pool_9 shape. It replaces
  `test_dominant_form_matching_a_sheet_index_fails` once the behavior changes.
- every form equals a sheet index: still fails with the identical-index error.
- `--min-fraction` is measured against own reads only.
- `--override` keeps working and wins over measurement.

### 4. Rollout

- Keep `--override` and `fqtk_barcode_overrides` as an escape hatch for libraries the
  heuristic still gets wrong.
- Delete the xR128 `fqtk_barcode_overrides` entry only if lane 5 ever gets re-run with
  the new resolver; the result should be the same barcode.
- Reword the remaining error so it says which reads were considered.

## Related issue

The fqtk barcode TSV is rewritten (new mtime) on every parse. Under
`rerun-triggers: mtime` that makes `fqtk_per_config` look stale after any new parse.
Worth writing the file only when its content changes, the same way the validation
workbook is regenerated only when needed.
