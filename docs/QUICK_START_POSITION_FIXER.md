# Quick Start: Position Shift Fixer

## What This Does

Fixes FASTQ file names in lanes 2, 3, 4 that have position numbers offset by +2 due to sample removal from lane1.

**Example Fix:**
```
Old: xR090-L2-G2-P016-CGAATACG-GTCGGTAA-R1.fastq.gz  (wrong, +2)
New: xR090-L2-G2-P014-CGAATACG-GTCGGTAA-R1.fastq.gz  (correct)
```

## Quick Commands

### 1. Preview Changes (Always do this first!)
```bash
cd /staging/nextcloud/testing_illumina/NovaseqX/xR090
./fix_output_files_position_shift.sh --dry-run
```

### 2. Apply Changes
```bash
./fix_output_files_position_shift.sh
```

### 3. Check Results
```bash
ls output/lane2/*/xR090-L2-G2-P0* | head -5
```

## Understanding the Output

```
Lane 2 Position Analysis:
  Detected consistent offset: +2 (files are +2 from correct positions)
  Affected barcodes: 19
```

This means:
- ✅ All files in lane2 are consistently 2 positions too high
- ✅ Safe to fix automatically
- ✅ 19 different samples (barcodes) are affected

## When It Found Issues

The script detected that lane2 output files are at **+2 positions**:
- File position: P016, Map position: P014 → Offset: +2 ✓
- File position: P017, Map position: P015 → Offset: +2 ✓
- File position: P013, Map position: P011 → Offset: +2 ✓

All consistent, so fixing is safe!

## Why This Happened

Lane1 originally had 12 samples. When M24_VDJ/GEX was removed:
- Lane1: 12 → 10 samples
- Renaming maps regenerated with correct positions (shifted down by 2)
- But output files were already named with old positions
- Result: Files are 2 positions higher than the new maps expect

## Help

```bash
./fix_output_files_position_shift.sh --help
```

## More Information

See: `POSITION_SHIFT_FIXER_SUMMARY.md` and `docs/position_shift_fixer_README.md`
