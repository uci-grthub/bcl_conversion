#!/usr/bin/env python3
"""
Metadata Validation Script for Illumina Sequencing Runs
=========================================================

This script performs comprehensive validation on metadata Excel files to catch
common errors before running the Snakemake pipeline.

Tests performed:
1. File format and structure validation
2. Required columns presence
3. Duplicate barcode detection (same lane, same index)
4. Empty/missing critical fields
5. Index sequence format validation
6. Lane number validation
7. Project name consistency
8. Masking string format validation
9. Sample name uniqueness within projects
10. Cross-sheet consistency checks

Usage:
    python3 debug/validate_metadata.py [metadata_file.xlsx]
    
If no file is specified, uses the metadata file from snakemake_config.yaml
"""

import pandas as pd
import os
import sys
import re
import yaml
from collections import defaultdict
import argparse


class MetadataValidator:
    """Validator class for Illumina sequencing metadata files"""
    
    def __init__(self, excel_path):
        self.excel_path = excel_path
        self.errors = []
        self.warnings = []
        self.info = []
        self.xl = None
        self.all_sheets_data = {}
        
    def add_error(self, msg):
        """Add a critical error"""
        self.errors.append(f"❌ ERROR: {msg}")
        
    def add_warning(self, msg):
        """Add a warning (non-critical issue)"""
        self.warnings.append(f"⚠️  WARNING: {msg}")
        
    def add_info(self, msg):
        """Add informational message"""
        self.info.append(f"ℹ️  INFO: {msg}")
    
    def validate_file_exists(self):
        """Test 1: Check if file exists and is readable"""
        if not os.path.exists(self.excel_path):
            self.add_error(f"Metadata file not found: {self.excel_path}")
            return False
            
        if not os.path.isfile(self.excel_path):
            self.add_error(f"Path is not a file: {self.excel_path}")
            return False
            
        if not self.excel_path.endswith(('.xlsx', '.xls')):
            self.add_warning(f"File does not have .xlsx or .xls extension")
            
        try:
            self.xl = pd.ExcelFile(self.excel_path)
            self.add_info(f"Successfully opened metadata file: {self.excel_path}")
            self.add_info(f"Sheet names: {', '.join(self.xl.sheet_names)}")
            return True
        except Exception as e:
            self.add_error(f"Cannot read Excel file: {e}")
            return False
    
    def validate_sheet_structure(self):
        """Test 2: Validate sheet structure and required sheets"""
        if not self.xl:
            return False
            
        # Check for MiSeq vs NovaSeqX format
        is_miseq = 'Barcode Entries' in self.xl.sheet_names and 'Summary' not in self.xl.sheet_names
        is_novaseq = 'Summary' in self.xl.sheet_names
        
        if is_miseq:
            self.add_info("Detected MiSeq format metadata")
            required_sheets = ['Sample Information + User Info', 'Barcode Entries']
        elif is_novaseq:
            self.add_info("Detected NovaSeqX format metadata")
            required_sheets = ['Summary']
        else:
            self.add_warning("Could not determine metadata format (MiSeq or NovaSeqX)")
            return True
            
        for sheet in required_sheets:
            if sheet not in self.xl.sheet_names:
                self.add_error(f"Required sheet '{sheet}' not found")
                
        return len(self.errors) == 0
    
    def load_all_sheets(self):
        """Test 3: Load all data sheets and validate basic structure"""
        if not self.xl:
            return False
        
        # Check if this is NovaSeqX format with Summary sheet
        is_novaseq = 'Summary' in self.xl.sheet_names
        data_sheets = []
        
        if is_novaseq:
            # Parse Summary sheet to find which data sheets to load
            try:
                df_summary = pd.read_excel(self.excel_path, sheet_name='Summary')
                
                # Find the header row (contains 'Lane')
                header_row = -1
                for i, row in df_summary.iterrows():
                    if 'Lane' in row.values or 'lane' in str(row.values).lower():
                        header_row = i
                        break
                
                if header_row >= 0:
                    # Re-read with proper header
                    df_summary = pd.read_excel(self.excel_path, sheet_name='Summary', header=header_row)
                    
                    # Find column that contains sheet names (usually 'Sample sheet tab' or similar)
                    sheet_col = None
                    for col in df_summary.columns:
                        if 'sheet' in str(col).lower() and 'tab' in str(col).lower():
                            sheet_col = col
                            break
                    
                    if sheet_col:
                        data_sheets = df_summary[sheet_col].dropna().unique().tolist()
                        self.add_info(f"Found data sheet references in Summary: {', '.join(str(s) for s in data_sheets)}")
            except Exception as e:
                self.add_warning(f"Could not parse Summary sheet: {e}")
        
        # If no data sheets found from Summary, load all non-Summary sheets
        if not data_sheets:
            data_sheets = [s for s in self.xl.sheet_names if 'summary' not in s.lower()]
            
        for sheet_name in data_sheets:
            if sheet_name not in self.xl.sheet_names:
                self.add_warning(f"Data sheet '{sheet_name}' referenced in Summary but not found in file")
                continue
                
            try:
                # First, read raw to find the header row (contains 'Lane' AND 'Sample_ID'/'Sample_Name')
                df_raw = pd.read_excel(self.excel_path, sheet_name=sheet_name, header=None)
                
                # Find the row containing both 'Lane' and sample columns (the actual header row)
                header_row = -1
                for i, row in df_raw.iterrows():
                    row_values = [str(x).strip() for x in row.values]
                    if "Lane" in row_values and any(col in row_values for col in ['Sample_ID', 'Sample_Name', 'Sample Name']):
                        header_row = i
                        break
                
                # Re-read with proper header
                if header_row >= 0:
                    df = pd.read_excel(self.excel_path, sheet_name=sheet_name, header=header_row)
                else:
                    # If no header found, skip this sheet
                    self.add_warning(f"Sheet '{sheet_name}' does not have recognizable sample data header")
                    continue
                
                # Check if sheet has data
                if df.empty:
                    self.add_warning(f"Sheet '{sheet_name}' is empty")
                    continue
                    
                # Check for required columns
                has_lane = 'Lane' in df.columns
                has_index = 'index' in df.columns
                has_project = 'Project' in df.columns or 'Sample_Project' in df.columns
                
                if has_lane and has_index:
                    # Normalize Project column name
                    if 'Sample_Project' in df.columns and 'Project' not in df.columns:
                        df['Project'] = df['Sample_Project']
                    
                    self.all_sheets_data[sheet_name] = df
                    self.add_info(f"Loaded sheet '{sheet_name}': {len(df)} rows, {len(df.columns)} columns")
                else:
                    missing = []
                    if not has_lane:
                        missing.append('Lane')
                    if not has_index:
                        missing.append('index')
                    if not has_project:
                        missing.append('Project/Sample_Project')
                    self.add_warning(f"Sheet '{sheet_name}' missing required columns: {', '.join(missing)}")
                    
            except Exception as e:
                self.add_warning(f"Could not load sheet '{sheet_name}': {e}")
                
        return len(self.all_sheets_data) > 0
    
    def validate_duplicate_indices(self):
        """Test 4: Check for duplicate barcode indices in the same lane"""
        found_duplicates = False
        
        for sheet_name, df in self.all_sheets_data.items():
            if 'Lane' not in df.columns or 'index' not in df.columns:
                continue
                
            # Group by lane
            for lane in df['Lane'].unique():
                if pd.isna(lane):
                    continue
                    
                lane_df = df[df['Lane'] == lane]
                
                # Get valid indices (non-empty)
                valid_indices = lane_df['index'].dropna()
                valid_indices = valid_indices[valid_indices.astype(str).str.strip() != '']
                
                if valid_indices.empty:
                    continue
                    
                # Check for duplicates
                duplicates = valid_indices[valid_indices.duplicated(keep=False)]
                
                if not duplicates.empty:
                    found_duplicates = True
                    dup_indices = duplicates.unique()
                    
                    for idx_val in dup_indices:
                        dup_rows = lane_df[lane_df['index'] == idx_val]
                        samples = []
                        projects = []
                        
                        for _, row in dup_rows.iterrows():
                            sample = row.get('Sample_Name', 'N/A')
                            project = row.get('Project', 'N/A')
                            samples.append(str(sample))
                            projects.append(str(project))
                        
                        self.add_error(
                            f"Sheet '{sheet_name}', Lane {lane}: Duplicate index '{idx_val}' found in:\n"
                            f"  Samples: {', '.join(samples)}\n"
                            f"  Projects: {', '.join(projects)}"
                        )
        
        if not found_duplicates:
            self.add_info("✓ No duplicate indices detected within lanes")
            
        return not found_duplicates
    
    def validate_index_format(self):
        """Test 5: Validate barcode index sequences"""
        valid_bases = set('ACGTN')
        
        for sheet_name, df in self.all_sheets_data.items():
            if 'index' not in df.columns:
                continue
                
            for idx, row in df.iterrows():
                index_val = row.get('index')
                
                if pd.isna(index_val) or str(index_val).strip() == '':
                    continue
                    
                index_str = str(index_val).strip().upper()
                
                # Check for invalid characters
                invalid_chars = set(index_str) - valid_bases
                if invalid_chars:
                    self.add_error(
                        f"Sheet '{sheet_name}', Row {idx+2}: Invalid characters in index '{index_val}': "
                        f"{', '.join(invalid_chars)}"
                    )
                    
                # Check for reasonable length (typically 6-12 bp)
                if len(index_str) < 6 or len(index_str) > 12:
                    self.add_warning(
                        f"Sheet '{sheet_name}', Row {idx+2}: Unusual index length ({len(index_str)} bp): '{index_val}'"
                    )
                    
                # Check for index2 if present
                if 'index2' in df.columns:
                    index2_val = row.get('index2')
                    if pd.notna(index2_val) and str(index2_val).strip() != '':
                        index2_str = str(index2_val).strip().upper()
                        invalid_chars2 = set(index2_str) - valid_bases
                        if invalid_chars2:
                            self.add_error(
                                f"Sheet '{sheet_name}', Row {idx+2}: Invalid characters in index2 '{index2_val}': "
                                f"{', '.join(invalid_chars2)}"
                            )
        
        self.add_info("✓ Index format validation complete")
        return True
    
    def validate_required_fields(self):
        """Test 6: Check for empty/missing required fields"""
        required_fields = ['Lane', 'index', 'Project']
        
        for sheet_name, df in self.all_sheets_data.items():
            for field in required_fields:
                if field not in df.columns:
                    continue
                    
                # Count empty/missing values
                empty_count = df[field].isna().sum()
                empty_str_count = (df[field].astype(str).str.strip() == '').sum()
                total_empty = empty_count + empty_str_count
                
                if total_empty > 0:
                    self.add_warning(
                        f"Sheet '{sheet_name}': {total_empty} rows have empty '{field}' values"
                    )
        
        self.add_info("✓ Required fields validation complete")
        return True
    
    def validate_lane_numbers(self):
        """Test 7: Validate lane numbers are reasonable"""
        for sheet_name, df in self.all_sheets_data.items():
            if 'Lane' not in df.columns:
                continue
                
            lanes = df['Lane'].dropna().unique()
            
            for lane in lanes:
                try:
                    lane_int = int(lane)
                    if lane_int < 1 or lane_int > 8:
                        self.add_warning(
                            f"Sheet '{sheet_name}': Unusual lane number: {lane_int} (expected 1-8)"
                        )
                except (ValueError, TypeError):
                    self.add_error(
                        f"Sheet '{sheet_name}': Invalid lane value: '{lane}' (must be numeric 1-8)"
                    )
        
        self.add_info("✓ Lane number validation complete")
        return True
    
    def validate_project_names(self):
        """Test 8: Check project naming consistency"""
        all_projects = defaultdict(set)  # project -> set of sheets
        
        for sheet_name, df in self.all_sheets_data.items():
            if 'Project' not in df.columns:
                continue
                
            projects = df['Project'].dropna().unique()
            
            for project in projects:
                project_str = str(project).strip()
                
                # Check for problematic characters
                if any(char in project_str for char in ['/', '\\', ':', '*', '?', '"', '<', '>', '|']):
                    self.add_warning(
                        f"Sheet '{sheet_name}': Project name '{project}' contains filesystem-unsafe characters"
                    )
                    
                all_projects[project_str].add(sheet_name)
        
        # Report projects that appear in multiple sheets
        for project, sheets in all_projects.items():
            if len(sheets) > 1:
                self.add_info(f"Project '{project}' appears in sheets: {', '.join(sheets)}")
        
        self.add_info("✓ Project name validation complete")
        return True
    
    def validate_sample_names(self):
        """Test 9: Check for duplicate sample names within projects"""
        for sheet_name, df in self.all_sheets_data.items():
            if 'Sample_Name' not in df.columns or 'Project' not in df.columns:
                continue
                
            # Group by project
            for project in df['Project'].dropna().unique():
                project_df = df[df['Project'] == project]
                samples = project_df['Sample_Name'].dropna()
                
                # Find duplicates
                duplicates = samples[samples.duplicated(keep=False)]
                
                if not duplicates.empty:
                    dup_names = duplicates.unique()
                    self.add_warning(
                        f"Sheet '{sheet_name}', Project '{project}': Duplicate sample names found: "
                        f"{', '.join(str(n) for n in dup_names)}"
                    )
        
        self.add_info("✓ Sample name validation complete")
        return True
    
    def validate_project_name_variations(self):
        """Test 10a: List all project names across all sources and flag near-duplicate variations"""
        from difflib import SequenceMatcher

        # Collect project names from Summary sheet
        summary_projects = {}  # (lane, group) -> project_name
        barcode_projects = {}  # (lane, group) -> project_name

        if self.xl:
            # Summary sheet
            try:
                df_sum = pd.read_excel(self.excel_path, sheet_name='Summary', header=2)
                if 'Project Name' in df_sum.columns:
                    for _, row in df_sum.iterrows():
                        try:
                            l = int(float(row['Lane']))
                            g = int(float(row['Gr']))
                            p = str(row['Project Name']).strip()
                            if p and p.lower() != 'nan':
                                summary_projects[(l, g)] = p
                        except Exception:
                            pass
            except Exception as e:
                self.add_warning(f"Could not read Summary for project name validation: {e}")

            # Barcode List sheet
            try:
                if 'Barcode List' in self.xl.sheet_names:
                    df_bl = pd.read_excel(self.excel_path, sheet_name='Barcode List', header=1)
                    for _, row in df_bl.iterrows():
                        try:
                            l = int(float(row.get('Lane', 0)))
                            g = int(float(row.get('Group', 0)))
                            p = str(row.get('Project name', '')).strip()
                            if p and p.lower() != 'nan':
                                barcode_projects[(l, g)] = p
                        except Exception:
                            pass
            except Exception as e:
                self.add_warning(f"Could not read Barcode List for project name validation: {e}")

        # Collect all unique project names
        all_names = sorted(set(list(summary_projects.values()) + list(barcode_projects.values())))

        self.add_info(f"All project names found ({len(all_names)} unique):")
        for name in all_names:
            self.add_info(f"  {name}")

        # Flag cross-sheet naming mismatches for same (lane, group)
        common_keys = set(summary_projects.keys()) & set(barcode_projects.keys())
        for key in sorted(common_keys):
            s_name = summary_projects[key]
            b_name = barcode_projects[key]
            if s_name != b_name:
                self.add_error(
                    f"Lane {key[0]} Gr {key[1]}: Project name mismatch between Summary "
                    f"('{s_name}') and Barcode List ('{b_name}')"
                )

        # Flag near-duplicate project names (similar but not identical)
        def normalize(name):
            return re.sub(r'[_\-\s]', '', name.lower())

        seen_pairs = set()
        for i, a in enumerate(all_names):
            for b in all_names[i+1:]:
                pair = (a, b)
                if pair in seen_pairs:
                    continue
                seen_pairs.add(pair)
                ratio = SequenceMatcher(None, normalize(a), normalize(b)).ratio()
                if ratio >= 0.8 and a != b:
                    self.add_warning(
                        f"Similar project names (similarity {ratio:.0%}): '{a}' vs '{b}' — "
                        f"verify these are distinct projects"
                    )

        self.add_info("✓ Project name variation check complete")
        return True

    def validate_order_ids(self):
        """Test 10b: Flag Summary rows that lack an Order ID, and flag data sheet tabs missing an Order ID column"""
        ok = True

        # --- Check Summary sheet row-by-row ---
        if self.xl and 'Summary' in self.xl.sheet_names:
            try:
                df = pd.read_excel(self.excel_path, sheet_name='Summary', header=2)
                if 'Order ID' not in df.columns or 'Project Name' not in df.columns:
                    self.add_warning("Summary sheet missing 'Order ID' or 'Project Name' column")
                else:
                    missing = []
                    for _, row in df.iterrows():
                        project = str(row.get('Project Name', '')).strip()
                        order_id = str(row.get('Order ID', '')).strip()
                        if project and project.lower() != 'nan':
                            if not order_id or order_id.lower() == 'nan':
                                try:
                                    lane = int(float(row['Lane']))
                                    gr = int(float(row['Gr']))
                                except Exception:
                                    lane, gr = '?', '?'
                                missing.append(f"Lane {lane} Gr {gr}: '{project}'")
                    if missing:
                        ok = False
                        for entry in missing:
                            self.add_error(f"Missing Order ID in Summary — {entry}")
                    else:
                        self.add_info("✓ All Summary rows have an Order ID")
            except Exception as e:
                self.add_warning(f"Could not read Summary for order ID validation: {e}")

        # --- Check each loaded data sheet tab for Order ID column ---
        for sheet_name, df in self.all_sheets_data.items():
            # Look for any order-id-like column (case-insensitive)
            order_cols = [c for c in df.columns if re.search(r'order.?id', str(c), re.IGNORECASE)]
            if not order_cols:
                self.add_warning(
                    f"Sheet '{sheet_name}' has no 'Order ID' column — "
                    f"order ID cannot be assigned to samples in this tab"
                )
            else:
                # Check for rows where Order ID is blank
                col = order_cols[0]
                blank = df[df[col].isna() | (df[col].astype(str).str.strip().isin(['', 'nan']))]
                if not blank.empty:
                    self.add_warning(
                        f"Sheet '{sheet_name}': {len(blank)} row(s) have a blank '{col}'"
                    )

        return ok

    def validate_lane_conflicts(self):
        """Test 10c: Flag projects with conflicting lane assignments between Summary and Barcode List"""
        if not self.xl:
            return True

        # Build project -> set of (lane, group) from Summary
        summary_map = defaultdict(set)
        barcode_map = defaultdict(set)

        try:
            df_sum = pd.read_excel(self.excel_path, sheet_name='Summary', header=2)
            if 'Project Name' in df_sum.columns:
                for _, row in df_sum.iterrows():
                    try:
                        p = str(row['Project Name']).strip()
                        l = int(float(row['Lane']))
                        g = int(float(row['Gr']))
                        if p and p.lower() != 'nan':
                            summary_map[p].add((l, g))
                    except Exception:
                        pass
        except Exception as e:
            self.add_warning(f"Could not read Summary for lane conflict check: {e}")

        try:
            if 'Barcode List' in self.xl.sheet_names:
                df_bl = pd.read_excel(self.excel_path, sheet_name='Barcode List', header=1)
                for _, row in df_bl.drop_duplicates(subset=['Lane', 'Group', 'Project name']).iterrows():
                    try:
                        p = str(row.get('Project name', '')).strip()
                        l = int(float(row.get('Lane', 0)))
                        g = int(float(row.get('Group', 0)))
                        if p and p.lower() != 'nan':
                            barcode_map[p].add((l, g))
                    except Exception:
                        pass
        except Exception as e:
            self.add_warning(f"Could not read Barcode List for lane conflict check: {e}")

        # Check consistency
        all_projects = set(summary_map.keys()) | set(barcode_map.keys())
        found_conflict = False
        for project in sorted(all_projects):
            s_lanes = summary_map.get(project, set())
            b_lanes = barcode_map.get(project, set())

            if s_lanes and b_lanes and s_lanes != b_lanes:
                found_conflict = True
                only_in_summary = s_lanes - b_lanes
                only_in_barcode = b_lanes - s_lanes
                msg = f"Project '{project}' has lane/group conflicts:"
                if only_in_summary:
                    msg += f"\n    In Summary only: {sorted(only_in_summary)}"
                if only_in_barcode:
                    msg += f"\n    In Barcode List only: {sorted(only_in_barcode)}"
                self.add_error(msg)

            if s_lanes and not b_lanes:
                self.add_info(f"Project '{project}' is in Summary but not Barcode List (OK for 10x/Parse/BD)")
            elif b_lanes and not s_lanes:
                self.add_warning(f"Project '{project}' is in Barcode List but not Summary")

        if not found_conflict:
            self.add_info("✓ No lane/group conflicts between Summary and Barcode List")

        return not found_conflict

    def validate_masking_format(self):
        """Test 10d: Validate masking string format if present"""
        masking_pattern = re.compile(r'^[RIYNUryn]+\d+[;,]?')  # Basic pattern
        
        for sheet_name, df in self.all_sheets_data.items():
            if 'Masking' not in df.columns:
                continue
                
            maskings = df['Masking'].dropna().unique()
            
            for masking in maskings:
                masking_str = str(masking).strip()
                
                # Basic format check
                if not masking_pattern.search(masking_str):
                    self.add_warning(
                        f"Sheet '{sheet_name}': Unusual masking format: '{masking}'"
                    )
        
        self.add_info("✓ Masking format validation complete")
        return True
    
    def generate_summary_report(self):
        """Generate a comprehensive summary report"""
        print("\n" + "=" * 80)
        print("METADATA VALIDATION REPORT")
        print("=" * 80)
        print(f"File: {self.excel_path}")
        print(f"Date: {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 80 + "\n")
        
        # Statistics
        total_sheets = len(self.all_sheets_data)
        total_samples = sum(len(df) for df in self.all_sheets_data.values())
        
        print(f"📊 Statistics:")
        print(f"  - Sheets processed: {total_sheets}")
        print(f"  - Total samples: {total_samples}")
        
        if self.all_sheets_data:
            all_lanes = set()
            all_projects = set()
            
            for df in self.all_sheets_data.values():
                if 'Lane' in df.columns:
                    all_lanes.update(df['Lane'].dropna().unique())
                if 'Project' in df.columns:
                    all_projects.update(df['Project'].dropna().unique())
            
            print(f"  - Unique lanes: {sorted(all_lanes) if all_lanes else 'N/A'}")
            print(f"  - Unique projects: {len(all_projects)}")
        
        print()
        
        # Info messages
        if self.info:
            print(f"ℹ️  Information ({len(self.info)} items):")
            for msg in self.info:
                print(f"  {msg}")
            print()
        
        # Warnings
        if self.warnings:
            print(f"⚠️  Warnings ({len(self.warnings)} items):")
            for msg in self.warnings:
                print(f"  {msg}")
            print()
        
        # Errors
        if self.errors:
            print(f"❌ Errors ({len(self.errors)} items):")
            for msg in self.errors:
                print(f"  {msg}")
            print()
        
        # Overall status
        print("=" * 80)
        if self.errors:
            print("❌ VALIDATION FAILED - Please fix errors before running pipeline")
            print("=" * 80)
            return False
        elif self.warnings:
            print("⚠️  VALIDATION PASSED WITH WARNINGS")
            print("=" * 80)
            return True
        else:
            print("✅ VALIDATION PASSED - No errors or warnings")
            print("=" * 80)
            return True
    
    def run_all_tests(self):
        """Run all validation tests"""
        print(f"\nStarting validation of: {self.excel_path}\n")
        
        # Run tests in order
        tests = [
            ("File Existence", self.validate_file_exists),
            ("Sheet Structure", self.validate_sheet_structure),
            ("Data Loading", self.load_all_sheets),
            ("Duplicate Indices", self.validate_duplicate_indices),
            ("Index Format", self.validate_index_format),
            ("Required Fields", self.validate_required_fields),
            ("Lane Numbers", self.validate_lane_numbers),
            ("Project Names", self.validate_project_names),
            ("Sample Names", self.validate_sample_names),
            ("Project Name Variations", self.validate_project_name_variations),
            ("Order IDs", self.validate_order_ids),
            ("Lane Conflicts", self.validate_lane_conflicts),
            ("Masking Format", self.validate_masking_format),
        ]
        
        for test_name, test_func in tests:
            print(f"Running test: {test_name}...", end=" ")
            try:
                result = test_func()
                if result:
                    print("✓")
                else:
                    print("✗")
                    if test_name in ["File Existence", "Sheet Structure", "Data Loading"]:
                        # Critical tests - stop if they fail
                        print(f"\nCritical test '{test_name}' failed. Stopping validation.")
                        break
            except Exception as e:
                print(f"✗ (Exception: {e})")
                self.add_error(f"Test '{test_name}' failed with exception: {e}")
        
        # Generate report
        return self.generate_summary_report()


def main():
    parser = argparse.ArgumentParser(
        description="Validate Illumina sequencing metadata Excel files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Validate specific file
  python3 debug/validate_metadata.py metadata/sample_sheet.xlsx
  
  # Use metadata from snakemake_config.yaml
  python3 debug/validate_metadata.py
  
  # Use with project config
  python3 debug/validate_metadata.py --config snakemake_config_project.yaml
        """
    )
    
    parser.add_argument(
        'metadata_file',
        nargs='?',
        help='Path to metadata Excel file (optional if using config)'
    )
    
    parser.add_argument(
        '--config',
        default='snakemake_config.yaml',
        help='Config YAML file to read metadata path from (default: snakemake_config.yaml)'
    )
    
    args = parser.parse_args()
    
    # Determine metadata file path
    metadata_path = args.metadata_file
    
    if not metadata_path:
        # Try to read from config file
        if os.path.exists(args.config):
            try:
                with open(args.config, 'r') as f:
                    config = yaml.safe_load(f)
                metadata_path = config.get('metadata')
                
                if not metadata_path:
                    print(f"Error: No 'metadata' key found in {args.config}")
                    sys.exit(1)
                    
                print(f"Using metadata file from {args.config}: {metadata_path}")
            except Exception as e:
                print(f"Error reading config file {args.config}: {e}")
                sys.exit(1)
        else:
            print(f"Error: Config file not found: {args.config}")
            print("Please specify a metadata file or ensure config file exists.")
            sys.exit(1)
    
    # Create validator and run tests
    validator = MetadataValidator(metadata_path)
    success = validator.run_all_tests()
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
