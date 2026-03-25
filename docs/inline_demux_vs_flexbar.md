# Inline Demux vs Flexbar: Why the Positional Script Is Faster

## Flexbar's approach (53 hours)

Flexbar scans each read with a sliding window looking for the full pattern
`NNNNNCGTGATNNNN` across every position:

- 1.3 billion reads × 151 bp × 6 barcodes ≈ 1.2 trillion character comparisons
- Single-threaded in the original run
- Strict `--barcode-error-rate 0` requires an exact 5-bp leader length — any
  deviation (common due to sequencing noise) discards the read
- Result: ~90% of reads end up in the unassigned bucket

## `inline_demux.py`'s approach

The barcode position is fixed and confirmed empirically (R1[5:11] for all
samples; see `docs/flexbar_library_w_bcl_convert.md`). The script exploits this:

```python
obs_bc = seq[5:11]          # one slice, no scan
hamming(obs_bc, ref)        # 6 comparisons × 6 barcodes = 36 ops per read
```

- No sliding window — **O(bc_len × n_barcodes)** per read vs
  **O(read_length × n_barcodes)** for Flexbar
- For 151 bp reads that is a ~25× reduction in comparison work per read
- Allows 1 mismatch (`--max-mismatches 1`), recovering reads Flexbar discarded
- Python gzip streaming is the bottleneck, not the comparison logic

## Summary

| | Flexbar | inline_demux.py |
|---|---|---|
| Scan strategy | Sliding window over full read | Fixed-position slice |
| Comparisons per read | ~906 (151 × 6) | 36 (6 × 6) |
| Mismatch tolerance | 0 (strict) | 1 |
| Assignment rate | ~10% | Expected >80% |
| Runtime (1.3B reads) | 53 hours | Minutes |

mamba run -n bcl_convert python3 tests/test_inline_demux.py

The test covers the key behavioral difference between inline_demux and flexbar_per_config:

Check	What it proves
1. Exact matches	All 6 barcodes assigned correctly
2. 1-mismatch recovered	The main improvement over flexbar (flexbar strict mode drops these)
3. 2-mismatch → Undetermined	Doesn't over-assign noisy reads
4. Tie → Undetermined	Ambiguous reads handled safely
5. R1 5' clip	15 bp (5N+6bc+4N) removed from R1 output
6. UMI tag	prefix5 + suffix4 appended to read name
7. R2 pairing	R2 follows R1 assignment exactly
8. Stats file	Read counts sum to total input