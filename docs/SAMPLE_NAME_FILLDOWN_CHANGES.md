# Sample Name Fill-Down and Uniqueness Implementation

## Changes Made

### 1. New Helper Function: `filldown_and_make_unique_sample_names(df)`
**Location:** [src/workflow_defs.smk](src/workflow_defs.smk#L204)

This function implements a two-step process for handling missing Sample Names in the Barcode List:

#### Step 1: Fill Down Within Each Project
- Scans each project group independently
- Identifies rows with missing, empty, or "nan" Sample_Name values
- Fills missing values with the last non-null Sample_Name from the same project
- Uses forward-fill logic to propagate sample names down the list

#### Step 2: Make Unique Within Each Project
- Counts occurrences of each Sample_Name within the project
- For Sample_Names that appear multiple times, appends a numeric suffix
- Format: `{original_name}_1`, `{original_name}_2`, etc.

**Example:**
```
Before:
Project: ProjectA
  Sample1
  (missing)      <- filled with "Sample1"
  Sample2
  (missing)      <- filled with "Sample2"
  Sample2        <- duplicate

After:
Project: ProjectA
  Sample1_1
  Sample1_2      <- filled and numbered
  Sample2_1
  Sample2_2      <- filled and numbered
  Sample2_3      <- duplicate numbered
```

### 2. Integration Point
**Location:** [src/workflow_defs.smk](src/workflow_defs.smk#L664-L665)

The function is called in `generate_lane_samplesheets()` after:
- All metadata sheets are read
- Projects are assigned from lookup tables
- Masking is determined

**Timing:** Applied to the aggregated DataFrame `df` before sample sheet generation begins for each config

## How It Works

1. **Project-Level Processing:** Only processes rows belonging to a valid project (not NaN, empty, or 'nan' string)

2. **Fill-Down Logic:**
   - Groups rows by project
   - For each project, identifies missing Sample_Name values
   - Searches backward to find the last valid Sample_Name
   - Fills the missing value with that Sample_Name

3. **Uniqueness Logic:**
   - Groups rows by project
   - Counts occurrences of each Sample_Name within the project
   - For duplicates, iterates through them and appends a suffix (_1, _2, etc.)

## Why This Works

- **Non-Invasive:** Only modifies Sample_Name values when they are missing or need uniqueness
- **Project-Scoped:** Fill-down and uniqueness are applied per-project, so the same sample name can exist in different projects with different numbering
- **Safe:** Handles NaN, empty strings, and the literal string 'nan' consistently
- **Compatible:** Works with existing BCL conversion and renaming logic downstream

## Testing Recommendations

1. Verify Sample_Name values in generated SampleSheets
2. Check that filled-down values propagate correctly within each project
3. Confirm that duplicate Sample_Names are numbered appropriately
4. Run Snakemake to ensure no errors in downstream rules

## Example Metadata Scenario

**Input (Barcode List with missing Sample Names):**
```
Lane  Group  Project     index   Sample_Name
1     1      ProjectA    ACGT    Sample_A
1     1      ProjectA    TGCA    (missing)
1     1      ProjectA    GGCC    (missing)
1     2      ProjectB    AAAA    Sample_B
1     2      ProjectB    TTTT    (missing)
1     2      ProjectB    TTTT    (missing) <- duplicate
```

**Output (After filldown_and_make_unique_sample_names):**
```
Lane  Group  Project     index   Sample_Name
1     1      ProjectA    ACGT    Sample_A_1
1     1      ProjectA    TGCA    Sample_A_2      (filled from previous)
1     1      ProjectA    GGCC    Sample_A_3      (filled from previous)
1     2      ProjectB    AAAA    Sample_B_1
1     2      ProjectB    TTTT    Sample_B_2      (filled from previous)
1     2      ProjectB    TTTT    Sample_B_3      (filled from previous, duplicate numbered)
```

## Edge Cases Handled

- **Empty Sample_Name column:** Creates a dummy name using row index
- **All rows for a project are missing:** Fallback to generic naming (handled by existing code)
- **Single valid Sample_Name per project:** Duplicates are still numbered for clarity
- **Mixed valid and missing:** Correctly distinguishes and processes each case
