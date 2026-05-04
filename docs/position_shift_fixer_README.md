# Position Shift Fixer Script

## Overview

This script corrects FASTQ file position numbers when upstream changes cause a cascade of position shifts in the renaming maps.

## Problem Statement

When samples are removed from earlier lanes (e.g., M24_VDJ/GEX removed from lane1, changing count from 12 to 10), the regenerated renaming maps for downstream lanes shift all positions down by that offset (e.g., by -2).

However, output files may have already been renamed using the *old* maps that had the higher position numbers. This creates a mismatch:

```
Scenario:
Lane 1 originally had samples at: P001-P012 (12 samples)
Lane 1 after removal: P001-P010 (10 samples) ← 2 samples removed
Lane 2 originally started at: P013 (offset by 12)
Lane 2 after regeneration: P011 (offset by 10) ← new map expects positions to shift down by 2

Problem:
If lane2 files were already renamed using the old map, they'd be at P013+ 
But the new map expects P011+ instead
```

## Solution

This script:
1. **Analyzes** the mismatch between output files and their corresponding renaming maps
2. **Detects** the consistent offset across each lane
3. **Renames** files to match the correct positions in the renaming maps

## Usage

### Basic Dry-Run (No Changes)
```bash
cd /staging/nextcloud/testing_illumina/NovaseqX/xR090
./fix_output_files_position_shift.sh --dry-run
```

### Apply Changes
```bash
./fix_output_files_position_shift.sh
```

### Verbose Mode (Detailed Output)
```bash
./fix_output_files_position_shift.sh --dry-run --verbose
```

## How It Works

### 1. Loading Renaming Maps
The script reads CSV files from `results/renaming_map_lane*.csv` which contain:
- Barcode sequences (index1-index2)
- Correct position numbers (P001, P002, etc.)
- Sample metadata

### 2. Finding Mismatches
For each lane, the script:
- Parses all renamed FASTQ filenames in `output/lane*/`
- Extracts the barcode from each filename
- Looks up the correct position from the renaming map
- Calculates the offset: `file_position - correct_position`

### 3. Detecting Consistent Offset
All mismatched barcodes in a lane should have the *same* offset:
```
Lane 2 Analysis:
  Detected consistent offset: +2
  (files are +2 from correct positions)
```

If multiple different offsets are found, the script warns about this (possible data corruption).

### 4. Renaming Files
If running in LIVE mode (not --dry-run):
- Old: `xR090-L2-G2-P028-CTCGAACA-GGAATTGC-R1.fastq.gz`
- New: `xR090-L2-G2-P026-CTCGAACA-GGAATTGC-R1.fastq.gz` (if offset was +2)

## Example Output

```
Running in DRY-RUN mode (no changes will be made)

Lane 2 Position Analysis:
  Detected consistent offset: +2 (files are +2 from correct positions)
  Affected barcodes: 15
    CGAATACG-GTCGGTAA: map=P016, files=['P018']
    GTCCTTGA-TCAGACGA: map=P017, files=['P019']
    ... and 13 more

============================================================
Total files processed: 38
Run without --dry-run to apply changes
```

## When to Use

This script should be used when:
1. A sample removal causes position shifts in regenerated maps
2. Output files were already renamed with the old position numbers
3. You need to correct the filenames to match the new maps

## Safety Features

- **Dry-run mode**: Always test with `--dry-run` first
- **Verification**: Only renames files that have actual mismatches
- **Backup**: Original files are not deleted; only moved to new names
- **Error handling**: Logs any files that couldn't be renamed

## Lanes Processed

By default, the script processes lanes **2, 3, and 4** (lanes most affected by lane1 changes). Lane 1 is not processed since it's the source of the change.

## Requirements

- Python 3.6+
- pandas library
- mamba environment: `bcl_convert` (optional, but recommended)

## Technical Details

### File Name Format
```
{run}-L{lane}-G{group}-P{position:03d}-{index1}-{index2}-{read}.fastq.gz
```
Example: `xR090-L2-G2-P028-CGAATACG-GTCGGTAA-R1.fastq.gz`

### Offset Calculation
```python
offset = file_position - correct_position

# Examples:
# offset = +2 means files are 2 positions higher than map expects
# offset = -2 means files are 2 positions lower than map expects
```

### Supported Barcodes
- Single index (i7 only): `ACGTACGT`
- Dual index (i7-i5): `ACGTACGT-TGCATGCA`

Files with missing or malformed barcodes are skipped.

## Troubleshooting

### No files found to process
This is normal if:
- Files are already at correct positions (no offset)
- Output files don't follow the expected naming convention
- Renaming maps don't match the output files

### Multiple different offsets detected
This warning indicates:
- Different groups/samples have different offset values
- Possible corruption or incomplete regeneration
- Manual inspection recommended

### Permission denied errors
The user running the script must have write permissions in `output/lane*/` directories.

## Related Scripts

- `src/rename_fastqs.py` - Initial FASTQ renaming after BCL conversion
- `src/fix_positions_by_barcode.py` - Fix positions by matching barcodes (different approach)
- `src/run_rename.sh` - Wrapper script for renaming operations

## Author Notes

This script was created to handle the M24_VDJ/GEX removal scenario where lane1 samples decreased from 12 to 10, shifting all subsequent lane positions down by 2.
