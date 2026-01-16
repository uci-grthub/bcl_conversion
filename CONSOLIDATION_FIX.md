# Project Links Consolidation Fix

## Problem Statement
The report for order_id with multiple projects (e.g., order_1225I-34) only showed download links for one project instead of consolidating links from ALL projects in that order_id. Specifically:
- order_1225I-34 contains 3 projects: FleiA_smMIP_Pool1_12plex, FleiA_smMIP_Pool2_18plex, FleiA_smMIP_Pool3_17plex
- But the report only showed links for one project

## Root Cause
The workflow was processing each project separately:
1. Snakefile calls `generate_report.py` three times (once per project) with `append_mode=True`
2. Each call received ONLY that project's fastq links via subprocess parameter
3. The `generate_report.py` function in append_mode only extracted existing links from HTML, not from YAML
4. Therefore, when subsequent projects were processed, their links were never consolidated in the "Your Download Links" section at the top

## Solution Implemented

### Changes to src/generate_report.py

#### 1. Modified Function Signature (line 54)
**Before:**
```python
def generate_report(project, output_base_dir, fastp_plots_base_dir, fastp_base_dir, report_dir, fastq_links_str, lane_filter=None, append_mode=False):
```

**After:**
```python
def generate_report(project, output_base_dir, fastp_plots_base_dir, fastp_base_dir, report_dir, fastq_links_str, lane_filter=None, append_mode=False, links_yaml=None, order_id=None):
```

Added two new parameters:
- `links_yaml`: Path to the `logs/project_links.yaml` file containing all consolidated links
- `order_id`: The order ID to use for fetching all projects' links from YAML

#### 2. Added YAML Reading Logic (lines 86-117)
When in append_mode and YAML parameters are provided:
1. Opens the `links_yaml` file
2. Parses the YAML structure to find all projects for the given `order_id`
3. Builds a dictionary mapping project names to their download links
4. Gracefully handles errors with a warning message

```python
if append_mode and os.path.exists(html_file_path):
    # ... existing HTML extraction ...
    
    # NEW: If we have links_yaml and order_id, read ALL project links from YAML
    if links_yaml and order_id and os.path.exists(links_yaml):
        try:
            import yaml
            with open(links_yaml, 'r') as f:
                all_links_data = yaml.safe_load(f) or {}
            # Collect links for all projects in this order_id
            for proj_name, lane_configs in all_links_data.items():
                for lane_config, lane_links in lane_configs.items():
                    if isinstance(lane_links, dict):
                        for oid, link in lane_links.items():
                            if oid == order_id:
                                if proj_name not in existing_project_links:
                                    existing_project_links[proj_name] = []
                                existing_project_links[proj_name].append(link)
        except Exception as e:
            print(f"Warning: Could not read links from YAML: {e}")
```

#### 3. Updated Link Consolidation Logic (lines 119-139)
**Before:** Only de-duplicated existing_download_links + project_fastq_links

**After:** Consolidates from three sources:
1. Existing links already in the HTML (from previous projects processed)
2. Links from OTHER projects in the order_id (from YAML)
3. Current project's links (passed as parameter)

```python
# Build consolidated list of all download links
seen = set()
all_download_links = []
# Add existing links from HTML
for lk in existing_download_links:
    if lk not in seen:
        seen.add(lk)
        all_download_links.append(lk)
# Add links from other projects in the order_id from YAML
for proj_name, proj_links in existing_project_links.items():
    if proj_name != project:
        for lk in proj_links:
            if lk not in seen:
                seen.add(lk)
                all_download_links.append(lk)
# Add current project's links
for lk in project_fastq_links:
    if lk not in seen:
        seen.add(lk)
        all_download_links.append(lk)
```

#### 4. Updated Main Entry Point (lines 610-640)
Modified the script's command-line interface to accept the new parameters:

```python
if __name__ == "__main__":
    if len(sys.argv) < 7:
        print("Usage: generate_report.py <project> <output_base> <fastp_plots_base> <fastp_base> <report_dir> <fastq_links> [lane] [links_yaml] [order_id]")
        sys.exit(1)
    
    # ... parameter extraction ...
    
    if len(sys.argv) >= 9:
        links_yaml = sys.argv[8]
    
    if len(sys.argv) >= 10:
        order_id = sys.argv[9]
    
    # ... call generate_report with new parameters ...
    generate_report(..., links_yaml=links_yaml, order_id=order_id)
```

### Changes to Snakefile

#### Modified report_order_id Rule (line 907-917)
**Before:**
```python
cmd = [
    "python3", "src/generate_report.py",
    project,
    params.output_base,
    params.fastp_plots_base,
    params.fastp_base,
    report_dir,
    fastq_links
]
```

**After:**
```python
cmd = [
    "python3", "src/generate_report.py",
    project,
    params.output_base,
    params.fastp_plots_base,
    params.fastp_base,
    report_dir,
    fastq_links,
    "None",  # lane_filter
    input.links_yaml,  # Path to project_links.yaml
    order_id  # The order_id being processed
]
```

Now passes:
- `input.links_yaml`: The path to the consolidated project links YAML file
- `order_id`: The current order being processed

## How It Works Now

### Processing Flow for order_id with 3 Projects:

1. **First Project (FleiA_smMIP_Pool1_12plex):**
   - Report doesn't exist yet, append_mode=False
   - Links from project 1 only appear in report
   - Report created with links section

2. **Second Project (FleiA_smMIP_Pool2_18plex):**
   - Report exists, append_mode=True
   - YAML is read to find ALL projects for order_id
   - existing_project_links = {
       FleiA_smMIP_Pool1_12plex: [link1],
       FleiA_smMIP_Pool2_18plex: [link2],
       FleiA_smMIP_Pool3_17plex: [link3]
     }
   - All three links are consolidated in the "Your Download Links" section
   - Project 2's sample details are appended to "Sample Details" section

3. **Third Project (FleiA_smMIP_Pool3_17plex):**
   - Report exists, append_mode=True
   - YAML is read again, finds all three projects
   - All three links remain consolidated
   - Project 3's sample details are appended to "Sample Details" section

## Verification

To verify the fix works, test with order_1225I-34 which has 3 projects:

```bash
snakemake -j 1 Reports/order_1225I-34/index.html --unlock
```

Then check that the "Your Download Links" section at the top of the HTML report contains all three download URLs:
1. https://precision.biochem.uci.edu/s/awQjHnZgf4kJYH6 (Pool1)
2. https://precision.biochem.uci.edu/s/c7WCm8pS8kZAHay (Pool2)
3. https://precision.biochem.uci.edu/s/9gWt7s8WosXPZwG (Pool3)

## Additional Context

- The `existing_project_links` variable initialized at line 86 holds all projects' links from YAML
- De-duplication ensures no duplicate links appear even if the same URL appears in multiple places
- YAML reading is wrapped in try-except to handle any file format issues gracefully
- The implementation preserves backward compatibility: if links_yaml or order_id are not provided, the function still works (but won't consolidate links from YAML)

## Files Modified
1. `src/generate_report.py` - Added YAML reading and consolidation logic
2. `Snakefile` - Updated subprocess call to pass links_yaml and order_id
