# Bug: partial BarcodeMismatchesIndex fix broke bcl-convert sample sheets

## Symptom

`bcl_convert` failed for lane6 with:

```
ERROR: Sample Sheet Error: Samples 11 & 13 match barcode in column 'index', but have different values in 'BarcodeMismatchesIndex1' (same barcodes must have matching tolerance)
ERROR: Sample Sheet Error: Samples 12 & 13 match barcode in column 'index', but have different values in 'BarcodeMismatchesIndex1' (same barcodes must have matching tolerance)
ERROR: Sample Sheet Error: Samples 13 & 14 match barcode in column 'index', but have different values in 'BarcodeMismatchesIndex1' (same barcodes must have matching tolerance)
```

bcl-convert requires every row sharing an identical `index` (i7) value to carry
the same `BarcodeMismatchesIndex1`. Same rule applies to `index2` (i5) and
`BarcodeMismatchesIndex2`.

## Root cause

`scripts/validate_barcode_hamming_distance.py --fix` resolves Hamming-distance
conflicts between barcode pairs by setting `BarcodeMismatchesIndex` to `0` for
the rows involved (`fix_sheet_conflicts()`). It only touched rows literally
present in the detected conflict pair.

In lane6, samples `11_IP`, `12_IP`, `13_IP`, `14_IP` all share i7 index
`GAATTCGT` (differentiated by i5 only). `13_IP` was flagged in a
Hamming-distance conflict against another sample and got its tolerance forced
to `0`, but `11_IP`, `12_IP`, `14_IP` — which share the exact same i7 barcode —
were never touched and stayed at `1`. bcl-convert rejects that mismatch since
it treats identical index values as one group that must share one tolerance
value.

The generating rule (`validate_barcode_hamming_distances`) also declared the
script only as a `params`, not an `input`, so editing the script did not
invalidate the already-produced `SampleSheet_{config_id}_validated.csv`. The
first fix attempt therefore required manually forcing a rerun of that rule —
Snakemake had no way to know the fix logic itself had changed.

## Fix

`fix_sheet_conflicts()` in `scripts/validate_barcode_hamming_distance.py` now
expands each conflict fix to every row sharing that same `(Lane, index)` value
before writing `BarcodeMismatchesIndex1 = 0`, and likewise for `index2` /
`BarcodeMismatchesIndex2`. This guarantees all rows with an identical barcode
value end up with matching tolerance, satisfying bcl-convert's per-index
consistency requirement.

## Second fix: make the script an input

`scripts/validate_barcode_hamming_distance.py` is now an `input:` of both
`validate_barcode_hamming_distances` and `validate_barcode_hamming_distances_rc`
rather than a `params:`. The profile sets `rerun-triggers: mtime`, so with the
script as a declared input, editing the fix logic invalidates every
`SampleSheet_{config_id}_validated.csv` and Snakemake regenerates them on its own.

Before this change, a fix to the fixer left every stale validated sheet in place
and the operator had to know to delete them (or pass
`-R validate_barcode_hamming_distances`) — which is exactly what went wrong the
first time this bug was fixed.
