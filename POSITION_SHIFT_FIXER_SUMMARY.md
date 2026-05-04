# Position Shift Fixer - Implementation Summary

## Scripts Created

### 1. **Main Python Script**: `src/fix_output_files_position_shift.py`
- **Purpose**: Core logic for analyzing and fixing position mismatches
- **Features**:
  - Loads renaming maps from CSV files
  - Parses FASTQ filenames to extract position numbers
  - Detects position offsets between files and maps
  - Optionally renames files to correct positions
  - Supports dry-run mode for safe previewing
  
- **Key Functions**:
  - `load_renaming_map()`: Reads CSV renaming maps into memory
  - `analyze_lane_positions()`: Detects mismatches without changes
  - `process_lane_output()`: Performs the actual renaming
  - `parse_renamed_filename()`: Extracts metadata from FASTQ names

### 2. **Shell Wrapper**: `fix_output_files_position_shift.sh`
- **Purpose**: User-friendly wrapper for the Python script
- **Features**:
  - Validates project directory and required files
  - Provides help text (`--help`)
  - Supports `--dry-run` and `--verbose` flags
  - Automatically uses mamba environment if available
  - Comprehensive error checking

### 3. **Documentation**: `docs/position_shift_fixer_README.md`
- Detailed explanation of the problem
- Usage examples
- Technical details about the fix
- Troubleshooting guide

## How It Works

### The Problem
When samples are removed from lane1:
- Lane1: 12 samples → 10 samples (2 samples removed)
- Renaming maps regenerate with adjusted positions
- Lane2+ positions shift down by 2 (e.g., P013 becomes P011)
- But output files may already be renamed with old positions (+2)

### The Solution
The script:
1. **Analyzes** each lane to find position mismatches
2. **Detects** the consistent offset (e.g., +2 for all files)
3. **Renames** files to match the current renaming maps
4. **Reports** the changes (or would-be changes in dry-run)

### Example
```
Lane 2 Analysis:
  Detected consistent offset: +2 (files are +2 from correct positions)
  Affected barcodes: 19

Would rename:
  xR090-L2-G2-P016-CGAATACG-GTCGGTAA-R1.fastq.gz
  → xR090-L2-G2-P014-CGAATACG-GTCGGTAA-R1.fastq.gz
```

## Usage

### Preview Changes (Recommended First Step)
```bash
cd /staging/nextcloud/testing_illumina/NovaseqX/xR090
./fix_output_files_position_shift.sh --dry-run
```

### Apply Changes
```bash
./fix_output_files_position_shift.sh
```

### Detailed Preview
```bash
./fix_output_files_position_shift.sh --dry-run --verbose
```

### Get Help
```bash
./fix_output_files_position_shift.sh --help
```

## Testing Results

✅ Script successfully:
- ✅ Loads renaming maps from CSV files
- ✅ Parses FASTQ filenames with correct patterns
- ✅ Detects position offsets (+2 for lane 2)
- ✅ Identifies affected barcodes
- ✅ Shows detailed preview of changes in dry-run mode
- ✅ Works with mamba environment
- ✅ Validates project directory and required files

### Test Output
```
Position Shift Fixer for FASTQ Files
=====================================

Mode: DRY RUN (no files will be changed)

Running position shift fixer...

Using mamba environment: bcl_convert
Running in DRY-RUN mode (no changes will be made)

Lane 2 Position Analysis:
  Detected consistent offset: +2 (files are +2 from correct positions)
  Affected barcodes: 19
  
  Would rename: xR090-L2-G1-P013-GGAGATTC-GTCTGAAC-R1.fastq.gz 
  → xR090-L2-G1-P011-GGAGATTC-GTCTGAAC-R1.fastq.gz
  
  [... 35 more files ...]

============================================================
Total files processed: 0  # (0 because in dry-run mode)
Run without --dry-run to apply changes
```

## Files Modified/Created

| File | Type | Status |
|------|------|--------|
| `src/fix_output_files_position_shift.py` | Python | ✅ Created |
| `fix_output_files_position_shift.sh` | Bash | ✅ Created |
| `docs/position_shift_fixer_README.md` | Documentation | ✅ Created |

## Lane Configuration

The script targets:
- **Lane 2** (affected: position +2)
- **Lane 3** (affected: position +2)
- **Lane 4** (affected: position +2)

Lanes 1, 5, 6, 7, 8 are not processed (unless specifically configured).

## Safety Features

1. **Dry-Run Mode**: Always test changes before applying
2. **Validation**: Checks for required files before processing
3. **Consistent Offsets**: Warns if different offsets are found
4. **Error Handling**: Logs and reports files that couldn't be renamed
5. **Atomic Operations**: Files are moved (not copied), preventing duplication

## Next Steps

To use the script when position mismatches occur:

```bash
# 1. Preview the changes
./fix_output_files_position_shift.sh --dry-run

# 2. If output looks correct, apply the changes
./fix_output_files_position_shift.sh

# 3. Verify the changes
ls output/lane2/*/ | head -20
```

## Integration with Workflow

This script can be integrated into:
- Manual correction workflows
- Post-Snakemake cleanup steps
- Validation pipelines
- Data quality checks

The script is independent and doesn't require Snakemake, making it suitable for manual use or integration into other tools.
