# Flexbar-Demultiplexed Library: Migrating to BCL Convert

## 1. The Problem: Flexbar Bottleneck

Processing with Flexbar v3.5.0 identified two critical issues:

- **Extreme runtime**: 1.3 billion reads on a single thread took 53 hours and 2 minutes.
- **High data loss**: ~90% of reads (1.2 billion) were assigned to the unassigned bucket.

**Root cause**: Strict pattern matching (`NNNNNCGTGATNNNN`) with `--barcode-error-rate 0`.
Any deviation in the 5 bp leader length or a single sequencing error in the 6 bp index
caused the read to be rejected.

---

## 2. Library Structure

Each R1 read begins with an inline barcode region, empirically confirmed by scanning
100,000 Undetermined reads ([`src/find_location_of_flexbar_indexes.py`](../src/find_location_of_flexbar_indexes.py)):

```
[pos 0–4]  5 bp UMI prefix  (Ns)
[pos 5–10] 6 bp RC barcode  ← peak position confirmed at pos 5 for all barcodes
[pos 11–14] 4 bp UMI suffix (Ns)
[pos 15+]  Insert sequence
```

Each barcode hit ≥77% of sampled reads at exactly position 5 (vs. background noise
at all other positions), confirming the structure is consistent.

---

## 3. Solution: BCL Convert with Inline Barcode Demultiplexing

Transitioning to DRAGEN BCL Convert moves demultiplexing from post-processing (on FASTQs)
to the initial conversion step (on BCLs).

**Key advantages:**

- **Speed**: FPGA/multi-threaded acceleration reduces the 53-hour runtime to ~1 hour.
- **Recovery**: Tolerates 1 mismatch in the index (`BarcodeMismatchesIndex1,1`), recovering
  reads that Flexbar rejected with `--barcode-error-rate 0`.
- **Integration**: Handles UMI extraction, demultiplexing, and adapter trimming in one pass.

---

## 4. BCL Convert Configuration

### OverrideCycles logic

`U5I6Y*` applied to each sample:

| Code | Cycles | Meaning |
|------|--------|---------|
| `U5` | 1–5    | Extract as UMI; appended to read name (not in read sequence) |
| `I6` | 6–11   | Use as index for demultiplexing (not in read sequence) |
| `Y*` | 12+    | Genomic read → output in R1 FASTQ (starts with 4 bp UMI suffix) |

> **Note**: `U` means UMI extraction, not skip/mask. The 5 bp prefix is retained in the
> read header. The R1 output read therefore begins at position 11 of the original read
> (the 4 bp UMI suffix `NNNN` followed by the insert).

### SampleSheet.csv

```csv
[Header]
FileFormatVersion,2

[BCLConvert_Settings]
BarcodeMismatchesIndex1,1
AdapterRead1,AGATCGGAAGAGCGGTTCAG

[BCLConvert_Data]
Sample_ID,Index,OverrideCycles
Barcode1,CGTGAT,U5I6Y*
Barcode2,ACATCG,U5I6Y*
Barcode3,GCCTAA,U5I6Y*
Barcode4,TGGTCA,U5I6Y*
Barcode5,CACTGT,U5I6Y*
Barcode6,ATTGGC,U5I6Y*
```

> Indexes are the reverse complement of the original barcode sequences in the TSV,
> matching what is embedded in R1.

---

## 5. Post-Demultiplexing Trimming

After BCL Convert, R1 reads begin with the 4 bp UMI suffix (`NNNN` at original positions
11–14) before the insert. The `U5I6` prefix has already been consumed by BCL Convert.

### Equivalent cutadapt settings

```bash
cutadapt \
  -u 4 \                           # hard-clip 4 bp from 5' (the NNNN UMI suffix)
  -a AGATCGGAAGAGCGGTTCAG \        # TruSeq Read 2 adapter, 3' end
  -e 0.1 \                         # 10% error rate
  -O 1 \                           # min overlap = 1 bp
  -m 15 \                          # discard reads < 15 bp
  -o output.fastq.gz input.fastq.gz
```

### UMI note

The original flexbar workflow tagged both the 5 bp prefix and 4 bp suffix as UMIs via
`--umi-tags`. With BCL Convert:

- **5 bp UMI** (`U5`): extracted to the read header automatically.
- **4 bp UMI** (the `NNNN` suffix in Y*): trimmed off by `-u 4` above; extract before
  trimming (e.g. with `umi_tools extract`) if downstream deduplication requires it.

### What flexbar was doing (for reference)

Without BCL Convert, flexbar processed the full original reads. The equivalent
post-flexbar trim would have been:

```bash
cutadapt \
  -u 15 \                          # hard-clip 15 bp (5N UMI + 6bp barcode + 4N UMI)
  -a AGATCGGAAGAGCGGTTCAG \
  -e 0.1 \
  -O 1 \
  -m 15 \
  -o output.fastq.gz input.fastq.gz
```

---

## 6. Execution & Validation

### Test run (single tile)

```bash
bcl-convert \
  --bcl-input-directory /path/to/RunFolder \
  --output-directory ./bcl_test_output \
  --sample-sheet SampleSheet.csv \
  --first-tile-only true
```

### Validation

Check `Reports/Demultiplex_Stats.csv` in the output directory. A successful configuration
should show the majority of reads assigned to named barcodes rather than "Undetermined".
The Flexbar run assigned ~10% of reads successfully; BCL Convert with 1 mismatch allowed
should recover significantly more.
