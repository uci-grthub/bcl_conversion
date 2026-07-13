# Why lane2 group 7 (LiuC) is not an i7 reverse-complement candidate

**Run:** xR098 · **Lane/group:** lane2 G7 · **Project:** `LiuC_0626I-38_xR098_L2_G7` (`LiuC_2stepPCR_Pool`, 48 samples)
**Date of analysis:** 2026-07-13

## Summary

`LiuC_2stepPCR_Pool` demultiplexed **zero reads across all 48 samples** — the only project on
lane2 that flatlined. A zero-read project is exactly what an index-orientation bug looks like,
so an i7 reverse-complement (RC) rerun is the obvious thing to reach for.

It is not the answer here. The pipeline's RC detector correctly emitted no candidates for
lane2, and the underlying data agrees: **LiuC's indexes are not present in the undetermined
reads in any orientation.** Reverse-complementing i7 would not recover a single sample.

The zero reads have some other cause — most likely the library never made it into the pool, or
the index bases are not where the sample sheet says they are. Investigate the library prep and
the actual i7 oligos before touching the demultiplexing config.

## What the pipeline decided

| Artifact | Value |
| --- | --- |
| `logs/lane2/rc_candidates_lane2.json` | `[]` |
| `logs/lane2/orientation_decision_lane2.json` | `{}` |
| `rc_candidates` for every other lane (1, 3–8) | `[]` |

No RC candidates were found anywhere in the run, so the RC pass was a no-op for lane2 and the
`.output` (original orientation) FASTQs were published.

## The i7-only case is supported — it just did not fire

This is worth stating explicitly, because "the tool can't express it" would be a different
(and more worrying) explanation. It can:

- `scripts/check_index_rc_swap.py` classifies each match with per-index RC flags and maps
  `(True, False) -> 'i7_rc'` (i7 flipped, i5 as listed).
- `rule generate_rc_samplesheet` in the `Snakefile` reverse-complements **i7** for suspect
  projects.

So an i7-only flip is representable end to end. The detector scored LiuC and found nothing.

## The evidence

### 1. No undetermined read matches any lane2 index pair, in any orientation

The detector compares undetermined barcodes against every expected pair, testing exact, i7-RC,
i5-RC, both-RC, and swapped-order forms. Across the top 1,000 undetermined sequences on lane2
(285,501,380 reads, out of 545,943,580 undetermined total):

```
undetermined matching ANY lane2 expected pair, ANY orientation:  0
```

`project_scores` came back empty — not "below threshold", but **no scored pairs at all**. There
was nothing for the RC heuristic to act on.

### 2. LiuC's i7 never appears as listed

Searching the undetermined reads for LiuC's 48 i7 sequences (i5 ignored entirely):

```
LiuC i7, exact orientation:  0 reads
LiuC i7, reverse-complement: 450,904 reads
```

The RC number looks like a smoking gun. It is not — see below.

### 3. The apparent i7-RC signal is background noise

Those 450,904 reads break down as:

- Only **9 distinct sequences** carry an i7 matching `rc(expected)`.
- The i5 matches the expected i5 in **0 of 9** — neither as listed nor reverse-complemented.
- The hits concentrate on 2–3 samples, not across the 48-sample pool.
- The partner i5s are a family of one-base variants of each other
  (`ATTAACAAGG`, `ATTAAAAAGG`, `CTTAACAAGG`, `ATTAACAAGN`, `ATTCACAAGG`) — sequencing-error
  noise, not a real index.
- 450,904 reads is **0.083%** of lane2's undetermined pool.

This is what random 8-mer collision against a 48-barcode set looks like. A genuine i7-only flip
produces the opposite picture: many distinct samples, each with i7 = `rc(expected)` **and**
i5 = expected exactly, at high counts. The i5 never lines up here, which is precisely why the
pair-based detector scored nothing — and it was right to.

### 4. The index mask is not the problem

LiuC uses `OverrideCycles: Y151;I8N2;I8N2;Y151` with 8 bp indexes — the barcode is the first 8
of the 10 sequenced index bases, so the detector's left-truncation of observed 10-mers to 8-mers
is correct. Five other lane2 projects share the identical mask and demultiplexed normally.

## Conclusion

Do **not** add lane2 / LiuC to an i7-RC rerun. A mis-oriented library still deposits its
barcodes somewhere in the undetermined pool; LiuC's do not appear at all. The reads are not
mis-assigned — they are absent.

Next steps belong upstream of demultiplexing:

1. Confirm the LiuC pool was actually loaded and at what molarity.
2. Verify the i7 oligo sequences actually used against those in the sample sheet.
3. Given `2stepPCR`, confirm the second PCR added the indexes as expected.

## Known limitation surfaced by this investigation

`classify_observed()` in `scripts/check_index_rc_swap.py` requires **both** indexes to match
before it scores a pair. A real single-index flip in which the *other* index is garbage or
unreadable would therefore score zero and never be flagged. That did not cause a wrong call
here — LiuC's i7 is absent in the forward orientation too, so there is no flip to find — but the
blind spot is real and worth closing independently.

## Reproducing

```bash
pixi run python scripts/check_index_rc_swap.py \
  --samples results/lane2/SampleSheet_lane2.csv \
  --undetermined results/undetermined_indices/lane2.csv \
  --format json
```

Relevant inputs: `results/lane2/SampleSheet_lane2.csv`,
`results/undetermined_indices/lane2.csv`, `output/lane2/Reports/Demultiplex_Stats.csv`.
