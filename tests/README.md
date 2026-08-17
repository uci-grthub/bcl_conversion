# Tests

Covers the reverse-complement (RC) barcode naming path: when the i5 (or i7) a
client submitted does not match the index reads, DRAGEN re-demultiplexes against
the reverse complement, and the delivered FASTQ name has to carry the sequence
actually observed — not the one on the submission sheet.

## Running

```bash
pixi run test                  # everything
pixi run test backfill         # only tests/test_backfill*.py
pixi run test restem effective # several filters
```

pytest is not in `pixi.toml`, so `tests/run_tests.py` runs the suite in the
pipeline's own environment. The tests are plain pytest functions using only
`assert` and `tmp_path`, so `pytest tests/` works unchanged if pytest is ever
added.

## Layout

| File | Covers |
|---|---|
| `test_effective_map.py` | `apply_orientation_to_map` — workbook barcodes to delivered barcodes |
| `test_restem_by_position.py` | `restem_by_position` — renaming delivered files onto the new barcode |
| `test_rc_notice.py` | `rc_orientation_summary` rule body and the `rc_orientation_tag` subject tag |
| `test_backfill.py` | `scripts/backfill_rc_barcode_names.py` end to end |
| `_helpers.py` | Loads pipeline code that is not importable (see below) |
| `fixtures/renaming_map_lane5.csv` | Synthetic 5-sample renaming map |

## Two things worth knowing

**The tests exec the shipped source.** `src/workflow_defs.smk` is a Snakemake
include and the summary logic lives inside a rule body; neither is importable.
`_helpers.py` extracts that exact source and execs it rather than restating the
logic here, so a test cannot keep passing after the real code changes.

**The fixture encodes the reported bug.** `fixtures/renaming_map_lane5.csv` uses
the i5 pair from the xR106 L5G1 report this work came from — index 505,
submitted as `AGGCGAAG`, actually present as `CTTCGCCT`. `test_effective_map.py::test_reported_case_is_reproduced`
asserts the delivered name is exactly
`xR106-L5-G1-P001-CGCTCATT-CTTCGCCT-R1.fastq.gz`.

The fixture also carries a single-index project (blank i5) so the
"reverse-complementing an empty string must not invent a barcode" case stays
covered, and a lab_id that deliberately does *not* share a prefix with the
project name — a heuristic that assumed it did was a real defect this suite
caught.

## Invariants these tests defend

- A re-stem matches on `{run}-L{lane}-G{group}-{position}`, never on the
  barcode, so it can only rename a sample onto itself. Reads must never move
  between samples.
- A run with no RC decision must pass every barcode through untouched.
- `rc_i5` touches `index2` only; `rc_i7` touches `index` only.
- Backfill must not change md5 checksums — file contents do not change, only
  names — and must leave no stale stem in a client-facing artifact.
- Everything is idempotent: a second pass renames nothing.

`test_effective_map.py` additionally re-checks the passthrough invariant against
whatever real run directory happens to be present, and skips silently when there
is none.
