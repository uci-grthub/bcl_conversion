# Flexbar barcode FASTA leader bug (KY26SPI inline libraries)

## Summary

The flexbar barcode FASTA was built with a hardcoded **5 bp `N` leader**
(`NNNNN<barcode>NNNN`), which tells flexbar (LTAIL matching, `--barcode-error-rate 0`)
to look for the 6 bp inline index at R1 positions **6–11**. For the `YokoK_KY26SPI`
libraries the index actually sits at R1 positions **1–6**, so almost no reads matched
in *either* index orientation. Assignment was ~0.14% when it should be ~10%.

## Symptom

`logs/lane8/flexbar_lane8.log` showed both orientations assigning a tiny fraction of
reads, which triggered the reverse-complement orientation retry to no effect:

```
Primary (forward) orientation: total assigned=462957, max per-barcode=144063
No primary sample exceeds 1000000 reads; trying the opposite index orientation.
Alt (RC) orientation: total assigned=332452, max per-barcode=165019
Neither orientation exceeds 1000000 reads; retaining primary forward orientation.
```

462,957 assigned out of ~327M reads ≈ 0.14%.

## Root cause

The barcode FASTA construction in the `flexbar_per_config` rule hardcoded the pattern:

```awk
print ">" name
print "NNNNN" barcode "NNNN"
```

The 5 leading `N`s model a 5 bp leader (e.g. a UMI) before the inline barcode. This was
correct for the older PAREseq libraries whose read structure is `U5I6Y*` (5 bp UMI then
6 bp inline barcode) — but those libraries were migrated off flexbar to BCL Convert
inline extraction (see `docs/MIGRATION_SUMMARY.md`).

The currently active flexbar libraries do **not** have a leader:

| Lane | Group | Order | Project | Index | Masking |
|------|-------|-------|---------|-------|---------|
| 6 | 14 | 0526I-43 | YokoK_KY26SPI_1 | inline | R1:151, I1:6, I2:0, R2:151 |
| 8 | 3  | 0526I-43 | YokoK_KY26SPI_2 | inline | R1:151, I1:6, I2:0, R2:151 |

There is no `U` (UMI) token in the masking — the 6 bp index is at R1 position 1.

## Evidence

Sampling the first 200,000 R1 reads of each lane's `Undetermined` file and counting
where each barcode occurs:

| | at pos 1 | at pos 6 (background) |
|---|---|---|
| lane8 `AGTCAA` | 3,463 | 78 |
| lane8 `AGTTCC` | 2,841 | 64 |
| lane8 `ATGTCA` | 4,104 | 91 |
| lane8 `CCGTCC` | 4,825 | 24 |
| lane8 `GTAGAG` | 5,548 | 56 |
| lane6 (all 5)  | 1,800–2,700 each | 20–68 |

~10.4% of lane8 reads begin with a barcode at position 1; matches at position 6 are at
the random-6mer background rate (~200000/4096 ≈ 49). The bases immediately following the
barcode are a **constant** sequence (not a random UMI), so the trailing `NNNN` was also
unjustified and only over-trimmed real sequence.

## Fix

In the `flexbar_per_config` rule (`Snakefile`):

- The leader length is now driven by `config.flexbar_barcode_leader_n`, **defaulting to 0**
  (barcode at the read start). The trailing `NNNN` was removed.
- A `barcode_leader` param was added and threaded into the FASTA-building awk:

```awk
leader = ""
for (i = 0; i < lead + 0; i++) leader = leader "N"
print ">" name
print leader barcode
```

The reverse-complement orientation logic is unchanged and still acts as a safety net.

### Re-enabling a leader for a future U5-style library

If a PAREseq-style `U5I6` library returns to the flexbar path, set in config:

```yaml
flexbar_barcode_leader_n: 5
```

## Expected impact

Scaling the 200k-read sample to ~327M reads/lane: assignment rises from ~463k (0.14%)
to ~34M (~10.4%), and every sample clears ~5–9M reads — above the 1,000,000-read retry
threshold, so the RC-orientation retry no longer triggers for these libraries.

## Applying the change

Applying the fix requires `flexbar_per_config` to **re-run** for lane6 and lane8 (a full
re-demux of ~327M reads each; CPU-heavy). Validate on a subsample first if desired by
running flexbar on the first ~1M reads of a lane's R1 with the corrected single-barcode
FASTA and confirming assignment jumps to ~10%.
