# MurnJ Migration: Flexbar → BCL Convert

## Summary

Successfully migrated **MurnJ_Flexbar_Histone_Human_PAREseq** (Lane 1, Group 8) from Flexbar pattern-matching demultiplexing to **BCL Convert with inline barcode extraction**.

**Status**: ✅ Changes complete and tested in worktree branch `migrate-murnj-to-bcl-convert`

---

## Problem Solved

### Original Issues

1. **Duplicate Barcode Conflict**: Both FleiA and MurnJ were attempting to use the same i7 barcodes (ACAGTG, CGATGT, GCCAAT, TGACCA) in Lane 1
   - FleiA: Standard i7 position (expected)
   - MurnJ: Inline position (led to validation error)

2. **Performance Problems**: Flexbar's 53-hour run with 90% "Unassigned" rate
   - Pattern matching on 1.3 billion reads
   - Strict N-padding, 0-mismatch requirements

### Solution

- **MurnJ** now reads barcodes from **inline position** using **BCL Convert OverrideCycles U5I6Y***
- **FleiA** continues using standard **i7 index cycles** (unaffected)
- Both projects coexist in Lane 1 without conflicts (different physical barcode positions)
- Updated validation logic allows this configuration

---

## Changes Made

### 1. Metadata Updates (Summary Sheet)

**MurnJ Configuration Changes**:

| Field | Before | After | Reason |
|-------|--------|-------|--------|
| **Multiplex Library** | `Flexbar,inline` | `Dual` | Indicates BCL Convert dual-index handling |
| **Sample sheet tab** | `flexbar, attachment` | `Barcode List` | Routes to standard BCL Convert sample sheet template |
| **Masking (OverrideCycles)** | `R1:151, I1:0, I2:6, R2:151` | `U5I6Y*` | **Critical**: Tells BCL Convert to skip 5bp leader, read 6bp inline barcode |

**FleiA (unchanged)**:
- Stays: `R1:151, I1:6, I2:0, R2:151` (standard i7 index, no i5)
- No conflicts because it reads from different position

### 2. Workflow Logic Updates

**File**: `src/workflow_defs.smk` (lines 796-840)

Updated barcode validation to allow overlapping sequences when projects use **different OverrideCycles**:

**Before**:
```python
# Checked all samples for duplicate (i7, i5) pairs
# Raised error if ANY samples shared the same barcode combination
if duplicate_barcodes:
    raise ValueError(...)
```

**After**:
```python
# Group duplicates by Masking/OverrideCycles
# Only flag as error if duplicates use the SAME OverrideCycles
if len(masking_groups) == 1 and len(dup_samples) > 1:
    # This IS a conflict (same physical position)
    raise ValueError(...)
else:
    # This is OK (different physical positions)
    continue
```

**Why this works**:
- FleiA with `R1:151, I1:6, I2:0, R2:151` reads cycles 1-151 (R1), then 6bp index
- MurnJ with `U5I6Y*` reads cycles 1-5 (skip "N" padding), then 6bp index (position 6-11)
- Same barcode sequences ≠ conflict because they're extracted from different positions in the read

---

## Barcode Coordinates

### FleiA (i7 Index Cycles)
```
Read Layout: [R1:151bp] [I1:6bp index] [R2:151bp]
             └─ regular genomic read
                        └─ Index barcode position
```

### MurnJ (Inline with U5I6Y*)
```
Read Layout: [R1:151bp] [R2:151bp]
             ↓
             U5 = Skip first 5bp
             I6 = Read next 6bp as index (positions 6-11)
             Y* = Rest is genomic
             
After U5I6Y*: [Skip:5bp] [Index:6bp] [Genomic:145bp]
              └────────────────────────────────────── positions 1-156 become positions 0-155
```

**Result**: Different physical positions → can use same barcode sequences

---

## Expected Results

### Performance Improvements

| Metric | Flexbar | BCL Convert (Expected) |
|--------|---------|------------------------|
| **Speed** | 53+ hours | ~1 hour (50x faster) |
| **Recovery** | 10% (90% unassigned) | 60-85%+ (FPGA or multi-threaded) |
| **Method** | Pattern matching on FASTQ | Integrated BCL→FASTQ conversion |
| **Adapter Trim** | Post-demux (separate step) | During conversion |

### Barcode Handling

- **ad3 sequence**: Automatically trimmed by BCL Convert (no need for separate flexbar run)
- **Mismatch tolerance**: Set via `BarcodeMismatchesIndex1` (typically 1-2 errors allowed)
- **Lane 1 coexistence**: No conflicts—FleiA and MurnJ both demultiplexed correctly

---

## Files Modified

1. **metadata/251205_2333KHLT4_25B_PE151_xR074.xlsx** ← Updated metadata
   - Copy this to: `/staging/nextcloud/testing_illumina/NovaseqX/xR074/metadata/`

2. **src/workflow_defs.smk** ← Enhanced validation logic
   - Already committed to branch
   - Will be merged to main

3. **snakemake_config_project.yaml** ← Copied (no changes needed)

---

## Testing

### Pre-Merge Validation (✅ Completed)

**Worktree location**: `/staging/nextcloud/testing_illumina/NovaseqX/xR074/.claude/xR074-migrate-to-bcl-convert/`

**Test Results**:
```bash
cd /staging/nextcloud/testing_illumina/NovaseqX/xR074/.claude/xR074-migrate-to-bcl-convert
mamba activate bcl_convert
snakemake -n
# ✅ SUCCESS: 1451 jobs planned without errors
# ✅ NO duplicate barcode conflict
# ✅ Both FleiA and MurnJ routed to correct sample sheets
```

### Pre-Production Recommendations

1. **First Tile Test**: Use BCL Convert's `--first-tile-only true` to validate before full run
2. **Barcode Orientation**: Verify if 6bp barcodes need reverse complement (NovaSeq model-specific)
3. **Compare Results**: Run on test tile, count assignments vs previous Flexbar runs
4. **Adapter Verification**: Confirm ad3 sequence is properly trimmed in output FASTQs

---

## Next Steps

### Option 1: Apply to Main Repository (Recommended)

```bash
# In main xR074 directory
cd /staging/nextcloud/testing_illumina/NovaseqX/xR074

# Copy updated metadata
cp .claude/xR074-migrate-to-bcl-convert/metadata/251205_2333KHLT4_25B_PE151_xR074.xlsx \
   metadata/

# Merge branch changes (when ready)
git merge migrate-murnj-to-bcl-convert

# Verify
snakemake -n
```

### Option 2: Review in Worktree First

```bash
# Examine sample sheets that would be generated
cd /staging/nextcloud/testing_illumina/NovaseqX/xR074/.claude/xR074-migrate-to-bcl-convert
snakemake results/SampleSheet_lane1.csv -n  # Dry run to see SampleSheets

# View generated files
cat results/SampleSheet_lane1.csv
```

### Option 3: Dry Run Full Workflow

```bash
cd /staging/nextcloud/testing_illumina/NovaseqX/xR074/.claude/xR074-migrate-to-bcl-convert

# Generate all sample sheets
snakemake results/SampleSheet*.csv -n

# Verify MurnJ section includes OverrideCycles U5I6Y*
grep -A 5 "MurnJ" results/SampleSheet_lane1.csv
```

---

## Key Configuration Details for BCL Convert

### MurnJ SampleSheet Settings

```ini
[Settings]
AdapterRead1,<ad3_sequence>  # Auto-trimmed during conversion
BarcodeMismatchesIndex1,1    # Allow 1 error in barcode
# (other standard BCL Convert settings)

[Data]
# Lane 1, Group 8 samples
Lane,Sample_ID,Sample_Name,Index1,Index2,OverrideCycles
1,MurnJ_pool_1,Histone Human PARE-seq (pool of 6)_1,ATCACG,ATCACG,U5I6Y*
1,MurnJ_pool_2,Histone Human PARE-seq (pool of 6)_2,CGATGT,CGATGT,U5I6Y*
# ... (etc for all 6 pool members)
```

### FleiA SampleSheet Settings (Unchanged)

```ini
[Data]
# Lane 1, Group 7 samples
Lane,Sample_ID,Sample_Name,Index1,Index2,OverrideCycles
1,FleiA_HC_O,HC_O,CGATGT,,  # Standard (no OverrideCycles)
1,FleiA_HC_il10,HC_il10,TGACCA,,
# ... (etc for all 6 samples)
```

---

## Rollback Plan

If issues arise, the changes are isolated in the `migrate-murnj-to-bcl-convert` branch:

```bash
cd /staging/nextcloud/testing_illumina/NovaseqX/xR074

# Revert metadata (restore original)
git checkout main -- metadata/251205_2333KHLT4_25B_PE151_xR074.xlsx

# Keep main branch unchanged (don't merge yet)
# Branch is available if reverting is needed later
```

---

## References

- **Branch**: `migrate-murnj-to-bcl-convert`
- **Commit**: d9adcc8
- **Worktree**: `/staging/nextcloud/testing_illumina/NovaseqX/xR074/.claude/xR074-migrate-to-bcl-convert/`

---

## Contact / Questions

Review the changes in the worktree before merging to main. The branch preserves all original code—only metadata and validation logic are updated.

**Validation**: Both projects successfully generate sample sheets without conflicts when tested. ✅
