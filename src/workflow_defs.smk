import os
import re
import yaml
import pandas as pd
import xml.etree.ElementTree as ET
from io import StringIO
import csv
try:
    import openpyxl
    from openpyxl.styles import PatternFill, Font
except Exception:
    openpyxl = None

# Import shared validation function
from metadata_validation import validate_metadata_and_write_report


# Re-export for backward compatibility (in case it's called as workflow_defs.validate_metadata_and_write_report)
__all__ = ['validate_metadata_and_write_report']


# Sanitize Masking strings for filenames: strip appended project-like suffixes
def sanitize_masking(masking):
    if not masking:
        return masking
    s = str(masking).strip()
    try:
        m = re.search(r'(\s|_)(SwarV[^\s_]*)', s, flags=re.IGNORECASE)
        if m:
            s = s[:m.start()].rstrip(' _-')
        m2 = re.search(r'(_|\s)[A-Z0-9]+_L\d', s)
        if m2:
            s = s[:m2.start()].rstrip(' _-')
    except Exception:
        pass
    s = s.replace(":", "-").replace(", ", "_").replace(",", "_").replace(" ", "")
    return s

# Helper to generate organized directory name
def get_organized_dir_name(project, config_id, lab_id, run_name, project_lookup, project_order_id):
    """Generate directory name: lab-id_order-id_run-number_lane_group"""
    # Extract lane from config_id
    lane_match = re.match(r'lane(\d+)', config_id)
    lane = lane_match.group(1) if lane_match else "0"
    
    # Get group for this project and lane
    group = ""
    try:
        lane_int = int(lane)
        for (l, g), p in project_lookup.items():
            if l == lane_int and p == project:
                group = str(g)
                break
    except:
        pass
    
    # Get order_id for this project+lane
    try:
        order_id = project_order_id.get((project, int(lane)), "NOORDER")
    except (ValueError, TypeError):
        order_id = project_order_id.get((project, 0), "NOORDER")
    
    # Sanitize components for filename
    lab_id_clean = lab_id.replace(" ", "-").replace("_", "-")
    order_id_clean = order_id.replace(" ", "-").replace("_", "-")
    run_clean = run_name.replace(" ", "-").replace("_", "-")
    
    # Build directory name
    dir_name = f"{lab_id_clean}_{order_id_clean}_{run_clean}_L{lane}"
    if group:
        dir_name += f"_G{group}"
    
    return dir_name

# Helper to get group for a project from metadata
def get_project_group(project, config_id):
    """Extract group number for a project based on config_id (lane)."""
    # Extract lane from config_id
    lane_match = re.match(r'lane(\d+)', config_id)
    if not lane_match:
        return ""
    
    lane = int(lane_match.group(1))
    
    # Look up in PROJECT_LOOKUP to find the group
    for (l, g), p in PROJECT_LOOKUP.items():
        if l == lane and p == project:
            return str(g)
    
    return ""

# Helper to produce semicolon-separated fastq links for a given project+lane
def get_fastq_links_for_project_lane(project, lane):
    try:
        lane = int(lane)
    except Exception:
        pass
    links = PROJECT_LINKS_BY_LANE.get((project, lane))
    if not links:
        links = PROJECT_LINKS.get(project, ["https://precision.biochem.uci.edu/"])
        if not isinstance(links, list):
            links = [links]
    # De-duplicate while preserving order
    seen = set()
    unique = []
    for lk in links:
        if lk not in seen:
            seen.add(lk)
            unique.append(lk)
    return ";".join(unique)

# Helper to get project links from the consolidated YAML file
def get_project_links_from_yaml(yaml_path, project, lane=None, order_id=None):
    try:
        if not os.path.exists(yaml_path):
            return "https://precision.biochem.uci.edu/"
        
        with open(yaml_path, 'r') as f:
            links_data = yaml.safe_load(f)
        
        if not links_data or project not in links_data:
            return "https://precision.biochem.uci.edu/"
        
        project_links = links_data[project]
        lane_prefix = f"lane{lane}_" if lane is not None else None
        
        # Find all config_ids that match this lane (if specified) and optionally filter by order_id
        urls = []
        for config_id, config_data in project_links.items():
            if lane_prefix is not None and not config_id.startswith(lane_prefix):
                continue
            # Check if config_data is a dict (new format with order_id) or string (old format)
            if isinstance(config_data, dict):
                # New nested format: {config_id: {order_id: {'link': url, 'group': ...}}}
                if order_id is not None:
                    # Filter by order_id
                    if order_id in config_data:
                        link_data = config_data[order_id]
                        # Extract link from dict if it's a dict, otherwise use as-is
                        if isinstance(link_data, dict):
                            urls.append(link_data.get('link', link_data))
                        else:
                            urls.append(link_data)
                else:
                    # No order_id filter, include all urls for this config
                    for link_data in config_data.values():
                        # Extract link from dict if it's a dict, otherwise use as-is
                        if isinstance(link_data, dict):
                            urls.append(link_data.get('link', ''))
                        else:
                            urls.append(link_data)
            else:
                # Old format: {config_id: url}
                urls.append(config_data)
        
        if not urls:
            return "https://precision.biochem.uci.edu/"
        
        # De-duplicate while preserving order
        seen = set()
        unique = []
        for url in urls:
            if url and url not in seen:
                seen.add(url)
                unique.append(url)
        
        return ";".join(unique)
    except Exception as e:
        print(f"Error reading project links from YAML: {e}")
        return "https://precision.biochem.uci.edu/"

# 10x/Parse/BD naming: keep Illumina default (<sample>_S<num>_L00<lane>_R<read>_001.fastq.gz)
def is_parse_or_10x(project_name):
    try:
        p = str(project_name or "").lower()
    except Exception:
        p = ""
    return ("10x" in p) or ("parse" in p) or ("bd" in p)


def is_special_atac_project_or_sheet(name):
    """Return True for ATAC projects/sheets that need index-read preservation behavior."""
    try:
        n = str(name or "").replace("_", "").replace(" ", "").lower()
    except Exception:
        n = ""
    return n in ("bdrhapsodyatacseq", "bdrhapsodyatac", "10xmultiomeatacseq")


def is_10x_multiome_atac_project_or_sheet(name):
    """Return True for 10x Multiome ATAC project/sheet names."""
    try:
        n = str(name or "").replace("_", "").replace(" ", "").lower()
    except Exception:
        n = ""
    return "10xmultiomeatacseq" in n

# Write renaming map with a fixed schema to avoid malformed CSVs
def write_renaming_map(map_df, map_file):
    required_cols = [
        "Sample_ID",
        "Sample_Name",
        "Sample_Project",
        "Lane",
        "index",
        "index2",
        "Run",
        "Group",
        "Position",
    ]
    for c in required_cols:
        if c not in map_df.columns:
            map_df[c] = ""

    # Normalize Lane to int if possible
    try:
        map_df["Lane"] = map_df["Lane"].apply(lambda x: int(float(x)) if str(x).strip() != "" else "")
    except Exception:
        pass

    # Ensure Position exists and is non-empty
    if "Position" in map_df.columns:
        missing_pos = map_df["Position"].isna() | (map_df["Position"].astype(str).str.strip() == "")
        if missing_pos.any():
            positions = []
            counter = 1
            for i in range(len(map_df)):
                if missing_pos.iloc[i]:
                    positions.append(f"P{counter:03d}")
                    counter += 1
                else:
                    positions.append(map_df["Position"].iloc[i])
            map_df["Position"] = positions

    map_df = map_df[required_cols]
    map_df.to_csv(map_file, index=False, quoting=csv.QUOTE_MINIMAL)

def filldown_and_make_unique_sample_names(df):
    """
    Fill down missing Sample Names and make them unique within each project.
    
    For each project:
    1. Fill down: use the last non-null Sample_Name for rows with missing names
    2. Make unique: if duplicates exist within the project, append a suffix (_1, _2, etc.)
    
    Args:
        df: DataFrame with 'Project' and 'Sample_Name' columns
    
    Returns:
        Modified DataFrame with filled and unique Sample_Name values
    """
    df = df.copy()
    
    # Fill down Sample_Name within each project group
    for project in df['Project'].unique():
        if pd.isna(project) or str(project).strip() == '' or str(project).lower() == 'nan':
            continue
        
        project_mask = df['Project'] == project
        
        # Within this project, fill down missing Sample_Name values
        missing_mask = (df.loc[project_mask, 'Sample_Name'].isna() | 
                       (df.loc[project_mask, 'Sample_Name'].astype(str).str.strip() == '') |
                       (df.loc[project_mask, 'Sample_Name'].astype(str).str.lower() == 'nan'))
        
        if missing_mask.any():
            # Forward-fill the Sample_Name within the project group
            indices = df[project_mask].index
            for idx in indices[1:]:
                if missing_mask[idx]:
                    # Find the last non-null Sample_Name before this index
                    prev_indices = indices[indices < idx]
                    for prev_idx in prev_indices[::-1]:
                        prev_val = df.loc[prev_idx, 'Sample_Name']
                        if (not pd.isna(prev_val) and 
                            str(prev_val).strip() != '' and 
                            str(prev_val).lower() != 'nan'):
                            df.loc[idx, 'Sample_Name'] = prev_val
                            break
    
    # Make Sample_Name unique within each project by appending suffixes.
    # Skip 10x/BD/Parse projects: CellRanger/BD tools rely on the Illumina lane
    # number embedded in the FASTQ filename (L001, L002, …) to distinguish
    # multi-lane replicates, so adding _1/_2 suffixes here would break that
    # auto-merging convention and confuse clients.
    for project in df['Project'].unique():
        if pd.isna(project) or str(project).strip() == '' or str(project).lower() == 'nan':
            continue

        if is_parse_or_10x(project):
            continue

        project_mask = df['Project'] == project
        project_indices = df[project_mask].index

        # Count occurrences of each Sample_Name within this project
        sample_name_counts = df.loc[project_indices, 'Sample_Name'].value_counts()

        # For Sample_Names that appear more than once, add suffixes
        for sample_name, count in sample_name_counts.items():
            if count > 1:
                # Find all occurrences of this Sample_Name in this project
                dup_mask = (df['Project'] == project) & (df['Sample_Name'] == sample_name)
                dup_indices = df[dup_mask].index

                # Append suffix to each duplicate (_1, _2, etc.)
                for i, idx in enumerate(dup_indices, start=1):
                    df.loc[idx, 'Sample_Name'] = f"{sample_name}_{i}"
    
    return df

def generate_miseq_samplesheets(metadata_file, out_dir, run_info_path, run_name):
    """Generate sample sheets for MiSeq runs with simpler metadata format."""
    
    print(f"Processing MiSeq format metadata: {metadata_file}")
    
    # Read project information
    try:
        df_info = pd.read_excel(metadata_file, sheet_name='Sample Information + User Info', header=None)
        
        # Find the header row (contains 'Lab ID')
        header_row = -1
        for i, row in df_info.iterrows():
            if 'Lab ID' in row.values:
                header_row = i
                break
        
        if header_row == -1:
            print("Could not find header row in Sample Information sheet")
            return {}
        
        # Read with proper header
        df_info = pd.read_excel(metadata_file, sheet_name='Sample Information + User Info', header=header_row)
        
        # Get project name (the project label in the first Lab ID row) and the
        # order ID used for the config/sample-sheet filename.
        project_name = None
        order_id = None
        if 'Lab ID' in df_info.columns:
            lab_ids = [str(v).strip() for v in df_info['Lab ID'].dropna().tolist() if str(v).strip() and str(v).strip().lower() != 'nan']
            if lab_ids:
                project_name = lab_ids[0]
                for lab_id in lab_ids:
                    if re.match(r'^\d+[iI]-\d+$', lab_id):
                        order_id = lab_id.replace('i', 'I')
                        break
        if not project_name and 'Sample Name' in df_info.columns:
            project_name = df_info['Sample Name'].dropna().iloc[0] if not df_info['Sample Name'].dropna().empty else None
        
        if not project_name:
            project_name = "Project"
        
        project_name = str(project_name).strip()
        
    except Exception as e:
        print(f"Error reading project info: {e}")
        project_name = "Project"
    
    # Read barcode entries
    try:
        df_barcodes = pd.read_excel(metadata_file, sheet_name='Barcode Entries', header=None)
        
        # Find header row
        header_row = -1
        for i, row in df_barcodes.iterrows():
            row_str = ' '.join([str(x) for x in row.values if pd.notna(x)])
            if 'Barcode Entries i7' in row_str or 'i7' in row_str.lower():
                header_row = i
                break
        
        if header_row == -1:
            print("Could not find barcode header")
            return {}
        
        # Read barcodes starting after header
        barcodes_i7 = []
        barcodes_i5 = []
        
        # Column indices (typically: 0=Library Name, 1=i7, 2=spacer, 3=i5)
        i7_col = 1
        i5_col = 3
        
        for i in range(header_row + 1, len(df_barcodes)):
            row = df_barcodes.iloc[i]
            
            # i7 barcode
            if pd.notna(row.iloc[i7_col]) and str(row.iloc[i7_col]).strip():
                val = str(row.iloc[i7_col]).strip()
                if val and val.upper() != 'NAN' and not val.startswith('Barcode'):
                    barcodes_i7.append(val)
            
            # i5 barcode (if exists)
            if i5_col < len(row) and pd.notna(row.iloc[i5_col]) and str(row.iloc[i5_col]).strip():
                val = str(row.iloc[i5_col]).strip()
                if val and val.upper() != 'NAN':
                    barcodes_i5.append(val)
        
        if not barcodes_i7:
            print("No barcodes found")
            return {}
        
        # Determine if dual-indexed
        has_i5 = len(barcodes_i5) > 0 and len(barcodes_i5) == len(barcodes_i7)
        
    except Exception as e:
        print(f"Error reading barcodes: {e}")
        return {}
    
    # Build sample sheet data
    samples = []
    for idx, i7 in enumerate(barcodes_i7):
        sample_name = f"Sample_{idx+1:03d}"
        sample_data = {
            'Lane': 1,  # MiSeq typically has only 1 lane
            'Sample_ID': sample_name,
            'Sample_Name': sample_name,
            'index': i7,
            'index2': barcodes_i5[idx] if has_i5 and idx < len(barcodes_i5) else '',
            'Sample_Project': project_name,
        }
        samples.append(sample_data)
    
    df_samples = pd.DataFrame(samples)
    
    # Determine OverrideCycles from RunInfo.xml
    override_cycles = ""
    try:
        run_reads = get_run_read_lengths(run_info_path)
        if run_reads:
            cycles = []
            for read in run_reads:
                num_cycles = read['NumCycles']
                is_index = read['IsIndexedRead'] == 'Y'
                
                if is_index:
                    cycles.append(f"I{num_cycles}")
                else:
                    cycles.append(f"Y{num_cycles}")
            
            override_cycles = ";".join(cycles)
    except Exception as e:
        print(f"Could not parse RunInfo for OverrideCycles: {e}")
    
    df_samples['OverrideCycles'] = override_cycles
    
    # Generate sample sheet file
    config_id = "lane1"
    outfile = os.path.join(out_dir, config_id, f"SampleSheet_{config_id}.csv")

    os.makedirs(os.path.join(out_dir, config_id), exist_ok=True)
    
    with open(outfile, 'w') as f:
        f.write("[Header]\n")
        f.write("FileFormatVersion,2\n")
        f.write("\n")
        
        f.write("[BCLConvert_Settings]\n")
        # BD_Rhapsody_ATACseq / 10xMultiomeATACseq special settings
        special_atac_index_reads = False
        if 'Sample_Project' in df_samples.columns:
            for proj in df_samples['Sample_Project'].unique():
                if is_special_atac_project_or_sheet(proj):
                    special_atac_index_reads = True
                    break
        if special_atac_index_reads:
            f.write("CreateFastqForIndexReads,1\n")
        else:
            f.write("CreateFastqForIndexReads,0\n")
        f.write("MinimumTrimmedReadLength,8\n")
        f.write("MaskShortReads,8\n")
        f.write("FastqCompressionFormat,gzip\n")
        f.write("\n")
        
        f.write("[BCLConvert_Data]\n")
        cols = ['Lane', 'Sample_ID', 'Sample_Name', 'index', 'index2', 'Sample_Project', 'OverrideCycles']
        df_samples[cols].to_csv(f, index=False)
    
    print(f"Generated MiSeq sample sheet: {outfile}")
    
    # Generate renaming map
    map_df = pd.DataFrame()
    # Sample_ID preserved as string from sample sheet
    map_df['Sample_ID'] = df_samples['Sample_ID'].astype(str)
    map_df['Sample_Name'] = df_samples['Sample_Name']
    map_df['Sample_Project'] = df_samples['Sample_Project']
    map_df['Lane'] = df_samples['Lane']
    map_df['index'] = df_samples['index']
    map_df['index2'] = df_samples['index2']
    map_df['Run'] = run_name
    map_df['Group'] = '1'  # MiSeq typically has one group
    
    # Add positions
    positions = [f"P{i+1:03d}" for i in range(len(df_samples))]
    map_df['Position'] = positions
    
    map_file = os.path.join(out_dir, config_id, f"renaming_map_{config_id}.csv")
    write_renaming_map(map_df, map_file)
    print(f"Generated renaming map: {map_file}")

    return {config_id: outfile}

def get_run_read_lengths(run_info_path):
    if not os.path.exists(run_info_path):
        return []
    try:
        tree = ET.parse(run_info_path)
        root = tree.getroot()
        reads = []
        for read in root.findall(".//Read"):
            reads.append({
                'Number': int(read.get('Number')),
                'NumCycles': int(read.get('NumCycles')),
                'IsIndexedRead': read.get('IsIndexedRead')
            })
        return sorted(reads, key=lambda x: x['Number'])
    except Exception as e:
        print(f"Error parsing RunInfo.xml: {e}")
        return []

def generate_lane_samplesheets(metadata_file, lane_configs, project_lookup, masking_lookup, out_dir, run_info_path=None, library_name="Run"):
    if not metadata_file or not os.path.exists(metadata_file):
        print("Metadata file not found.")
        return {}
        
    # print(f"Generating sample sheets from {metadata_file}")
    
    # Use provided library_name (e.g., "xR081_B_Side") as run name
    run_name = library_name

    # Produce a metadata validation workbook (highlighted copy + RECOMMENDED_CHANGES tab)
    # Regenerate if: xlsx missing, metadata newer, or any orientation_decision file is newer
    # (the RC_ORIENTATION sheet needs decision files that may not exist on first pass).
    out_xlsx = None
    try:
        _base = os.path.splitext(os.path.basename(metadata_file))[0]
        out_xlsx = os.path.join('metadata', f"metadata_validation_{_base}.xlsx")
        _dec_files = glob.glob('logs/*/orientation_decision_*.json')
        _needs_regen = (
            not os.path.exists(out_xlsx)
            or os.path.getmtime(metadata_file) > os.path.getmtime(out_xlsx)
            or any(os.path.getmtime(d) > os.path.getmtime(out_xlsx) for d in _dec_files)
        )
        if _needs_regen:
            validate_metadata_and_write_report(metadata_file, out_xlsx=out_xlsx)
    except Exception as e:
        print(f"Warning: metadata validation report generation failed: {e}")

    # Use validated xlsx as data source for sample sheet construction if available.
    # RECOMMENDED_CHANGES and RC_ORIENTATION sheets are retained in the xlsx for
    # inspection but skipped during sample iteration below.
    _data_file = out_xlsx if (out_xlsx and os.path.exists(out_xlsx)) else metadata_file
    
    # Detect metadata format: MiSeq (simple) vs NovaSeqX (complex with Summary sheet)
    try:
        xl = pd.ExcelFile(metadata_file)
        is_miseq_format = 'Barcode Entries' in xl.sheet_names and 'Summary' not in xl.sheet_names
    except:
        is_miseq_format = False
    
    if is_miseq_format:
        return generate_miseq_samplesheets(metadata_file, out_dir, run_info_path, run_name)
    
    # Get actual run read lengths
    run_reads = get_run_read_lengths(run_info_path)
    
    # Read Barcode List to build Lane/Group -> (Project, Order ID) lookup
    barcode_list_lookup = {}
    try:
        xl = pd.ExcelFile(metadata_file)
        if 'Barcode List' in xl.sheet_names:
            df_barcode = pd.read_excel(metadata_file, sheet_name='Barcode List', header=1)
            # header=1 means second row is header
            for idx, row in df_barcode.iterrows():
                try:
                    lane = int(float(row.get('Lane', pd.NA)))
                    group = int(float(row.get('Group', pd.NA)))
                    project = str(row.get('Project name', '')).strip().replace(' ', '_')
                    if project and project.lower() != 'nan':
                        barcode_list_lookup[(lane, group)] = project
                except:
                    pass
    except Exception as e:
        print(f"Note: Could not read Barcode List: {e}")

    # Build lookup from Summary sheet: (lane, sheet_tab_normalized) -> global_group
    # Only include entries where a sheet tab maps to exactly ONE group per lane.
    # Sheets like "Barcode List" appear multiple times per lane (multiple groups) and
    # must be excluded so we don't incorrectly override their multi-group assignments.
    sheet_tab_group_lookup = {}
    flexbar_groups = set()  # (lane, group) pairs whose demux is handled by flexbar, not bcl-convert
    try:
        xl = pd.ExcelFile(metadata_file)
        if 'Summary' in xl.sheet_names:
            df_summary = pd.read_excel(metadata_file, sheet_name='Summary', header=2)
            if 'Lane' in df_summary.columns and 'Gr' in df_summary.columns and 'Sample sheet tab' in df_summary.columns:
                # Count how many groups each (lane, tab) has
                tab_counts = {}
                for _, row in df_summary.iterrows():
                    try:
                        l = int(float(row['Lane']))
                        g = int(float(row['Gr']))
                        tab = str(row['Sample sheet tab']).strip()
                        tab_norm = tab.replace('_', ' ').strip().lower()
                        if tab_norm and tab_norm != 'nan':
                            tab_counts.setdefault((l, tab_norm), set()).add(g)
                            # "Flexbar, attachment" tab means flexbar handles demux post-bcl-convert;
                            # exclude these groups from bcl-convert sample sheets entirely.
                            if 'flexbar' in tab_norm or 'pareseq' in tab_norm:
                                flexbar_groups.add((l, g))
                    except:
                        pass
                # Only include tabs that map to exactly one group per lane
                for _, row in df_summary.iterrows():
                    try:
                        l = int(float(row['Lane']))
                        g = int(float(row['Gr']))
                        tab = str(row['Sample sheet tab']).strip()
                        tab_norm = tab.replace('_', ' ').strip().lower()
                        if tab_norm and tab_norm != 'nan' and len(tab_counts.get((l, tab_norm), set())) == 1:
                            sheet_tab_group_lookup[(l, tab_norm)] = g
                    except:
                        pass
    except Exception as e:
        print(f"Note: Could not build sheet_tab_group_lookup: {e}")
    
    all_samples = pd.DataFrame()
    
    try:
        xl = pd.ExcelFile(_data_file)
        for sheet in xl.sheet_names:
            if sheet in ("Summary", "RECOMMENDED_CHANGES", "RC_ORIENTATION"):
                continue

            # print(f"Reading sheet: {sheet}")
            try:
                # Read raw to find header
                df_raw = pd.read_excel(_data_file, sheet_name=sheet, header=None)

                header_row = -1
                for i, row in df_raw.iterrows():
                    row_values = [str(x).strip() for x in row.values]
                    # Heuristic to find header row
                    if "Lane" in row_values and ("Sample_ID" in row_values or "Sample Name" in row_values or "Sample_Name" in row_values):
                        header_row = i
                        break

                if header_row == -1:
                    print(f"Could not find header in sheet {sheet}, skipping.")
                    continue

                df = pd.read_excel(_data_file, sheet_name=sheet, header=header_row)
                
                # Remove NBSP characters
                for col in df.select_dtypes(include=['object']).columns:
                    df[col] = df[col].apply(lambda x: x.replace('\xa0', ' ') if isinstance(x, str) else x)
                
                # Normalize columns
                sheet_samples = pd.DataFrame()
                
                # Lane
                if 'Lane' in df.columns:
                    df['Lane'] = df['Lane'].ffill()
                    # Remove repeated headers or invalid rows
                    df = df[pd.to_numeric(df['Lane'], errors='coerce').notnull()]
                    sheet_samples['Lane'] = df['Lane'].astype(int)
                else:
                    print(f"No Lane column in {sheet}")
                    continue
                
                # Group (for project lookup)
                if 'Group' in df.columns:
                    df['Group'] = df['Group'].ffill()
                    sheet_samples['Group'] = df['Group']
                elif 'group' in df.columns:
                    df['group'] = df['group'].ffill()
                    sheet_samples['Group'] = df['group']
                elif 'gr' in df.columns:
                    df['gr'] = df['gr'].ffill()
                    sheet_samples['Group'] = df['gr']
                else:
                    sheet_samples['Group'] = pd.NA

                # Override local group with global group from Summary sheet if available.
                # Application-specific sheets (e.g., BD Rhapsody_WTA) use local group
                # numbering that may not match the global group from the Summary sheet.
                # Only apply when the lane's rows agree on a single group (or have none):
                # sheets like Barcode List carry multi-group data with correct global
                # numbering and must not be collapsed to the Summary's single-group entry.
                tab_norm = str(sheet).replace('_', ' ').strip().lower()
                for lane_val in sheet_samples['Lane'].unique():
                    try:
                        l = int(float(lane_val))
                        if (l, tab_norm) in sheet_tab_group_lookup:
                            global_grp = sheet_tab_group_lookup[(l, tab_norm)]
                            lane_mask = sheet_samples['Lane'] == lane_val
                            lane_groups = sheet_samples.loc[lane_mask, 'Group'].dropna().unique()
                            if len(lane_groups) <= 1:
                                sheet_samples.loc[lane_mask, 'Group'] = global_grp
                    except:
                        pass

                # Project
                if 'Project' in df.columns and not (df['Project'].isna() | (df['Project'].astype(str).str.strip() == '')).all():
                    df['Project'] = df['Project'].ffill()
                    sheet_samples['Project'] = df['Project'].astype(str).str.strip().str.replace(' ', '_', regex=False)
                elif 'Project name' in df.columns:
                    df['Project name'] = df['Project name'].ffill()
                    sheet_samples['Project'] = df['Project name'].astype(str).str.strip().str.replace(' ', '_', regex=False)
                elif 'Sample_Project' in df.columns:
                    df['Sample_Project'] = df['Sample_Project'].ffill()
                    sheet_samples['Project'] = df['Sample_Project'].astype(str).str.strip().str.replace(' ', '_', regex=False)
                else:
                    sheet_samples['Project'] = pd.NA
                
                # Fill missing Project from Lookup using Lane and Group
                def fill_project(row):
                    if pd.isna(row['Project']) or str(row['Project']).strip() == "" or str(row['Project']).lower() == 'nan':
                        try:
                            l = int(float(row['Lane']))
                            g = int(float(row['Group']))
                            # First check Barcode List lookup
                            if (l, g) in barcode_list_lookup:
                                return barcode_list_lookup[(l, g)]
                            # Then fall back to project_lookup
                            return project_lookup.get((l, g), "")
                        except:
                            return row['Project']
                    return row['Project']
                
                if not sheet_samples.empty:
                    sheet_samples['Project'] = sheet_samples.apply(fill_project, axis=1)

                # Sample Name / ID
                # We want a single 'Sample_Name' column to use for ID generation later
                if 'Sample Name' in df.columns:
                    df['Sample Name'] = df['Sample Name'].ffill()
                    sheet_samples['Sample_Name'] = df['Sample Name']
                elif 'Sample_Name' in df.columns:
                    df['Sample_Name'] = df['Sample_Name'].ffill()
                    sheet_samples['Sample_Name'] = df['Sample_Name']
                
                # If Sample_Name is missing/NaN, try Sample_ID
                if 'Sample_ID' in df.columns:
                    if 'Sample_Name' not in sheet_samples.columns:
                        sheet_samples['Sample_Name'] = df['Sample_ID']
                    else:
                        sheet_samples['Sample_Name'] = sheet_samples['Sample_Name'].fillna(df['Sample_ID'])
                
                # Indexes
                if 'i7 Barcode Sequence' in df.columns:
                    sheet_samples['index'] = df['i7 Barcode Sequence']
                elif 'index' in df.columns:
                    sheet_samples['index'] = df['index']
                else:
                    sheet_samples['index'] = ""
                    
                if 'i5 Barcode Sequence' in df.columns:
                    sheet_samples['index2'] = df['i5 Barcode Sequence']
                elif 'index2' in df.columns:
                    sheet_samples['index2'] = df['index2']
                else:
                    sheet_samples['index2'] = ""
                
                # Track sheet name for each sample
                sheet_samples['__sheet_name__'] = sheet
                all_samples = pd.concat([all_samples, sheet_samples], ignore_index=True)
                
            except Exception as e:
                print(f"Error reading sheet {sheet}: {e}")
                continue

    except Exception as e:
        print(f"Error reading metadata file: {e}")
        return {}

    if all_samples.empty:
        print("No samples found in any sheet.")
        return {}
        
    df = all_samples

    # Remove flexbar-handled groups: their reads land in Undetermined and are
    # demuxed by flexbar_per_config, so they must not appear in bcl-convert sheets.
    if flexbar_groups and 'Lane' in df.columns and 'Group' in df.columns:
        def _is_flexbar_row(row):
            try:
                return (int(float(row['Lane'])), int(float(row['Group']))) in flexbar_groups
            except:
                return False
        flexbar_mask = df.apply(_is_flexbar_row, axis=1)
        if flexbar_mask.any():
            print(f"Excluding {flexbar_mask.sum()} flexbar-handled samples from bcl-convert sheets: "
                  f"{sorted(flexbar_groups)}")
            df = df[~flexbar_mask].reset_index(drop=True)

    # Assign Masking to samples based on Lane and Group
    def get_sample_masking(row):
        try:
            l = int(float(row['Lane']))
            g = int(float(row['Group']))
            return masking_lookup.get((l, g), "")
        except:
            return ""
            
    df['Masking'] = df.apply(get_sample_masking, axis=1)
    
    # Fill down and make unique Sample_Name values within each project
    df = filldown_and_make_unique_sample_names(df)
    
    generated_files = {}
    
    # Ensure output directory exists
    os.makedirs(out_dir, exist_ok=True)

    # Build lane start offsets using all lanes in metadata, so Pxxx stays stable
    # even when config['lanes'] runs only a subset of lanes.
    def _is_valid_index(val):
        if pd.isna(val):
            return False
        s = str(val).strip()
        if not s:
            return False
        return s.lower() != 'nan'

    def _parse_i1_i2_lengths(masking):
        i1_len = None
        i2_len = None
        try:
            for p in [x.strip() for x in str(masking).split(',') if x and str(x).strip()]:
                if ':' not in p:
                    continue
                t, l = p.split(':', 1)
                t = t.strip().upper()
                l = int(str(l).strip())
                if t == 'I1':
                    i1_len = l
                elif t == 'I2':
                    i2_len = l
        except Exception:
            pass
        return i1_len, i2_len

    def _prepare_lane_df(raw_df, lane):
        lane_prepped = raw_df[raw_df['Lane'] == lane].copy()

        # Normalize I2-only rows: move barcode index -> index2 when I1 is disabled.
        if 'Masking' in lane_prepped.columns and 'index' in lane_prepped.columns and 'index2' in lane_prepped.columns:
            for ridx, row in lane_prepped.iterrows():
                i1_len, i2_len = _parse_i1_i2_lengths(row.get('Masking', ''))
                if i1_len == 0 and (i2_len or 0) > 0:
                    idx1 = row.get('index', '')
                    idx2 = row.get('index2', '')
                    if _is_valid_index(idx1) and not _is_valid_index(idx2):
                        lane_prepped.at[ridx, 'index2'] = str(idx1).strip()
                        lane_prepped.at[ridx, 'index'] = ""

        valid_indices = lane_prepped.apply(
            lambda r: _is_valid_index(r.get('index', '')) or _is_valid_index(r.get('index2', '')),
            axis=1
        )
        if valid_indices.any():
            lane_prepped = lane_prepped[valid_indices]

        for _col in ['index', 'index2']:
            if _col in lane_prepped.columns:
                lane_prepped[_col] = lane_prepped[_col].apply(
                    lambda x: '' if pd.isna(x) or str(x).strip().lower() == 'nan' else str(x).strip()
                )

        lane_prepped = lane_prepped.drop_duplicates(subset=['Lane', 'Project', 'index', 'index2'], keep='first')

        # Remove projects that are demuxed post-hoc (not present in renaming maps).
        if 'Project' in lane_prepped.columns:
            lane_prepped = lane_prepped[
                ~lane_prepped['Project'].astype(str).str.contains('flexbar|pareseq|fqtk', case=False, na=False, regex=True)
            ]

        return lane_prepped.reset_index(drop=True)

    lane_position_start = {}
    all_lanes_for_positioning = sorted({int(float(l)) for l in df['Lane'].dropna().unique()})
    for lane_for_position in all_lanes_for_positioning:
        lane_position_start[lane_for_position] = 1

    for config in lane_configs:
        lane = config['lane']
        config_id = config['id']
        # Filter by Lane only — multiple masking groups are merged into one SampleSheet
        lane_df = _prepare_lane_df(df, lane)
        lane_position_counter = lane_position_start.get(lane, 1)
        # Determine if this config comes from a special ATAC sheet (allow both space and underscore)
        # that should preserve index-read handling.
        special_atac_index_reads = False
        special_10x_atac = False
        if not lane_df.empty and '__sheet_name__' in lane_df.columns:
            for s in lane_df['__sheet_name__'].unique():
                if is_special_atac_project_or_sheet(s):
                    special_atac_index_reads = True
                if is_10x_multiome_atac_project_or_sheet(s):
                    special_10x_atac = True

        # Also detect by project name in case the tab name does not encode application type.
        if not special_atac_index_reads and 'Project' in lane_df.columns:
            for p in lane_df['Project'].dropna().unique():
                if is_special_atac_project_or_sheet(p):
                    special_atac_index_reads = True
                if is_10x_multiome_atac_project_or_sheet(p):
                    special_10x_atac = True
                    break

        def parse_i1_i2_lengths(masking):
            i1_len = None
            i2_len = None
            try:
                for p in [x.strip() for x in str(masking).split(',') if x and str(x).strip()]:
                    if ':' not in p:
                        continue
                    t, l = p.split(':', 1)
                    t = t.strip().upper()
                    l = int(str(l).strip())
                    if t == 'I1':
                        i1_len = l
                    elif t == 'I2':
                        i2_len = l
            except Exception:
                pass
            return i1_len, i2_len
        
        # Remove rows with empty index if there are other rows with index
        def is_valid_index(val):
            if pd.isna(val):
                return False
            s = str(val).strip()
            if not s:
                return False
            if s.lower() == 'nan':
                return False
            return True

        # Normalize I2-only rows: if masking says I1:0 and I2>0, but barcode is stored in `index`,
        # move it to `index2` so generated SampleSheets match DRAGEN expectations.
        if 'Masking' in lane_df.columns and 'index' in lane_df.columns and 'index2' in lane_df.columns:
            for ridx, row in lane_df.iterrows():
                i1_len, i2_len = parse_i1_i2_lengths(row.get('Masking', ''))
                if i1_len == 0 and (i2_len or 0) > 0:
                    idx1 = row.get('index', '')
                    idx2 = row.get('index2', '')
                    if is_valid_index(idx1) and not is_valid_index(idx2):
                        lane_df.at[ridx, 'index2'] = str(idx1).strip()
                        lane_df.at[ridx, 'index'] = ""

        # Keep rows that have an index in either column (supports I2-only projects).
        valid_indices = lane_df.apply(
            lambda r: is_valid_index(r.get('index', '')) or is_valid_index(r.get('index2', '')),
            axis=1
        )
        if valid_indices.any():
            lane_df = lane_df[valid_indices]

        # Normalize NaN/blank in index columns to '' so that deduplication treats them as equal
        for _col in ['index', 'index2']:
            if _col in lane_df.columns:
                lane_df[_col] = lane_df[_col].apply(
                    lambda x: '' if pd.isna(x) or str(x).strip().lower() == 'nan' else str(x).strip()
                )

        # True de-duplication based on Lane + Project + index + index2
        # (prevents duplicate rows from multiple tabs like Barcode List, but preserves dual-indexed samples)
        lane_df = lane_df.drop_duplicates(subset=['Lane', 'Project', 'index', 'index2'], keep='first')
        
        if lane_df.empty:
            print(f"No samples found for lane {lane}")
            continue
        
        # VALIDATION: Check for duplicate barcode combinations (index + index2)
        # This is a sequencing error - BCL Convert cannot distinguish reads with identical dual-index barcodes
        # Note: Single i7 barcodes can be reused with different i5 barcodes (dual indexing is valid)
        if 'index' in lane_df.columns and 'index2' in lane_df.columns:
            # Create a combined barcode string (index + index2) for validation
            lane_df['combined_barcode'] = lane_df.apply(
                lambda r: (
                    f"{'' if pd.isna(r['index']) or str(r['index']).strip().lower() == 'nan' else str(r['index']).strip()}"
                    f":{'' if pd.isna(r['index2']) or str(r['index2']).strip().lower() == 'nan' else str(r['index2']).strip()}"
                ),
                axis=1
            )
            
            # Filter out rows where both index fields are empty/NaN
            valid_barcodes = lane_df[
                (
                    (lane_df['index'].notna()) &
                    (lane_df['index'].astype(str).str.strip() != '') &
                    (lane_df['index'].astype(str).str.lower() != 'nan')
                ) |
                (
                    (lane_df['index2'].notna()) &
                    (lane_df['index2'].astype(str).str.strip() != '') &
                    (lane_df['index2'].astype(str).str.lower() != 'nan')
                )
            ].copy()
            
            if not valid_barcodes.empty:
                # Check for duplicate combined barcodes ONLY within the same OverrideCycles/Masking group
                # Samples with different Masking settings (e.g., standard i7 vs inline U5I6Y*) read 
                # barcodes from different physical positions and can have overlapping barcode sequences.
                duplicate_mask = valid_barcodes['combined_barcode'].duplicated(keep=False)
                duplicate_barcodes = valid_barcodes[duplicate_mask]['combined_barcode'].unique()
                
                if len(duplicate_barcodes) > 0:
                    # Filter duplicates: only report if they share the same Masking/OverrideCycles
                    real_conflicts = []
                    for combo in duplicate_barcodes:
                        dup_samples = valid_barcodes[valid_barcodes['combined_barcode'] == combo]
                        # Group by Masking to see if all duplicates use the same OverrideCycles
                        masking_groups = dup_samples['Masking'].unique()
                        # If all duplicates have the SAME Masking, it's a real conflict
                        if len(masking_groups) == 1 and len(dup_samples) > 1:
                            real_conflicts.append(combo)
                    
                    if real_conflicts:
                        # Get detailed information about real conflicts
                        dup_rows = valid_barcodes[valid_barcodes['combined_barcode'].isin(real_conflicts)]
                        error_msg = f"\n{'='*80}\n"
                        error_msg += f"ERROR: Duplicate dual-index barcode combinations detected in Lane {lane}!\n"
                        error_msg += f"{'='*80}\n\n"
                        error_msg += "The same combination of i7 and i5 barcodes cannot be used for multiple samples.\n"
                        error_msg += "BCL Convert will not be able to distinguish which reads belong to which sample.\n\n"
                        error_msg += "Duplicate entries:\n"
                        error_msg += "-" * 80 + "\n"
                        
                        for combo in sorted(real_conflicts):
                            dup_samples = dup_rows[dup_rows['combined_barcode'] == combo]
                            i7, i5 = combo.split(':')
                            error_msg += f"\ni7={i7}, i5={i5}:\n"
                            for _, row in dup_samples.iterrows():
                                sample = row.get('Sample_Name', 'N/A')
                                project = row.get('Project', 'N/A')
                                error_msg += f"  - Sample: {sample}, Project: {project}\n"
                        
                        error_msg += "\n" + "=" * 80 + "\n"
                        error_msg += "Please fix the metadata file to use unique barcode combinations for each sample.\n"
                        error_msg += "=" * 80 + "\n"
                        
                        raise ValueError(error_msg)
            
        # Map columns
        # Target: Project,Lane,Sample_ID,Sample_Name,index,index2,Sample_Project
        
        ss_data = pd.DataFrame()

        ss_data['Lane'] = lane_df['Lane']
        # Sanitize project names for DRAGEN: only allow alphanumeric, hyphen, underscore.
        # Replace other characters with underscore and prevent ambiguous names like 'Undetermined'.
        def _sanitize_project_name(v):
            try:
                if pd.isna(v):
                    return ''
                s = str(v).strip()
                # Replace any character not in A-Z a-z 0-9 - _ with '_'
                s = re.sub(r'[^a-zA-Z0-9\-_]', '_', s)
                if s == '':
                    return ''
                if s.lower() == 'undetermined':
                    return 'Project_Undetermined'
                return s
            except Exception:
                return str(v)

        ss_data['Project'] = lane_df['Project'].apply(_sanitize_project_name)
        ss_data['Sample_Project'] = ss_data['Project']
        
        if 'Sample_Name' in lane_df.columns:
            # Fill missing sample names with a default
            lane_df['Sample_Name'] = lane_df['Sample_Name'].fillna("Sample")
            
            # Ensure uniqueness
            final_names = []
            seen = set()
            for name in lane_df['Sample_Name']:
                name = str(name).strip()
                if not name or name.lower() == 'nan':
                    name = "Sample"
                
                # Sanitize name: allow only alphanumeric, -, _
                name = re.sub(r'[^a-zA-Z0-9\-_]', '_', name)
                
                # Prevent "Undetermined" as Sample_ID
                if name.lower() == "undetermined":
                    name = "Sample_Undetermined"
                
                candidate = name
                counter = 1
                while candidate in seen:
                    candidate = f"{name}_{counter}"
                    counter += 1
                seen.add(candidate)
                final_names.append(candidate)
            
            ss_data['Sample_ID'] = final_names
            ss_data['Sample_Name'] = final_names
        else:
            # Generate generic names
            names = [f"Sample_{i+1}" for i in range(len(lane_df))]
            ss_data['Sample_ID'] = names
            ss_data['Sample_Name'] = names
            
        ss_data['index'] = lane_df['index']
        ss_data['index2'] = lane_df['index2']
        
        # Calculate per-row OverrideCycles from each sample's Masking
        def compute_override_cycles(masking_str, run_reads, strip_i2=False):
            """Convert masking string to OverrideCycles format.

            masking_str: e.g. "R1:151, I1:8, I2:8, R2:151"
            Returns: e.g. "Y151;I8;I8;Y151"
            """
            if not masking_str or str(masking_str).strip() == '' or str(masking_str).lower() == 'nan':
                return ""

            masking_clean = str(masking_str).strip()

            # Support compact inline format used for inline barcodes, e.g. U5I6Y*
            # Expand to full per-read OverrideCycles expected by DRAGEN/BCL Convert.
            compact_match = re.fullmatch(r'[UIYN0-9\*]+', masking_clean.upper())
            if compact_match and ':' not in masking_clean and ',' not in masking_clean and ';' not in masking_clean:
                try:
                    read1_len = 0
                    if run_reads and len(run_reads) > 0:
                        read1_len = int(run_reads[0].get('NumCycles', 0))

                    tokens = re.findall(r'(?:[UIYN]\d+|Y\*)', masking_clean.upper())
                    if tokens:
                        consumed = 0
                        read1_parts = []
                        for tok in tokens:
                            if tok == 'Y*':
                                remaining = max(read1_len - consumed, 0)
                                read1_parts.append(f"Y{remaining}")
                                consumed += remaining
                            else:
                                t = tok[0]
                                n = int(tok[1:])
                                read1_parts.append(f"{t}{n}")
                                consumed += n

                        cycles = [''.join(read1_parts)]
                        for rr in (run_reads[1:] if run_reads else []):
                            rr_len = int(rr.get('NumCycles', 0))
                            rr_is_index = rr.get('IsIndexedRead') == 'Y'
                            cycles.append(f"N{rr_len}" if rr_is_index else f"Y{rr_len}")

                        return ';'.join(cycles)
                except Exception as e:
                    print(f"Error parsing compact masking '{masking_str}' for lane {lane}: {e}")

            masking_for_cycles = masking_str
            if strip_i2:
                try:
                    parts = [p.strip() for p in masking_str.split(',') if p and str(p).strip()]
                    parts = [p for p in parts if not p.strip().upper().startswith('I2:')]
                    masking_for_cycles = ', '.join(parts)
                except Exception:
                    masking_for_cycles = masking_str
            try:
                parts = [p.strip() for p in masking_for_cycles.split(',')]
                cycles = []
                for i, p in enumerate(parts):
                    if ':' in p:
                        type_, len_ = p.split(':')
                        type_ = type_.strip().upper()
                        len_ = len_.strip()
                        specified_len = int(len_)

                        cycle_str = ""

                        actual_len = 0
                        actual_is_index = False
                        if run_reads and i < len(run_reads):
                            actual_len = int(run_reads[i]['NumCycles'])
                            actual_is_index = run_reads[i].get('IsIndexedRead') == 'Y'

                        if type_ == 'Y2':
                            cycle_str = f"U{actual_len}" if actual_len > 0 else f"U{specified_len}"
                        elif specified_len == 0 and actual_len > 0:
                            cycle_str = f"N{actual_len}"
                        else:
                            if type_.startswith('R'):
                                cycle_str = f"U{len_}" if actual_is_index else f"Y{len_}"
                            elif type_.startswith('I'):
                                if type_ == 'I2' and (special_10x_atac or special_atac_index_reads) and not row_has_index2:
                                    cycle_str = f"U{len_}"
                                else:
                                    cycle_str = f"I{len_}"
                            elif type_.startswith('U'):
                                cycle_str = f"U{len_}"

                            if actual_len > 0 and specified_len > 0 and specified_len < actual_len:
                                diff = actual_len - specified_len
                                cycle_str += f"N{diff}"

                        cycles.append(cycle_str)

                if cycles:
                    return ";".join(cycles)
            except Exception as e:
                print(f"Error parsing masking '{masking_str}' for lane {lane}: {e}")
            return ""

        # Determine per-row whether to strip I2 (special ATAC projects are exempt).
        override_cycles_list = []
        for _, row in lane_df.iterrows():
            row_masking = str(row.get('Masking', '')).strip()
            row_project = str(row.get('Project', '')).strip().upper()
            row_index2 = str(row.get('index2', '')).strip()
            row_has_index2 = row_index2 and row_index2.lower() != 'nan'
            strip_i2 = not special_atac_index_reads and ('ATAC' in row_project and not row_has_index2)
            override_cycles_list.append(compute_override_cycles(row_masking, run_reads, strip_i2=strip_i2))

        ss_data['OverrideCycles'] = override_cycles_list

        # Flexbar inline-barcode samples have barcodes embedded in R1 (positions 5–10),
        # not in physical index reads. DRAGEN cannot use I in non-index reads, so these
        # samples cannot be demultiplexed by DRAGEN. Generate barcode FASTA then exclude
        # them from the DRAGEN sheet; src/inline_demux.py processes Undetermined reads post-hoc.
        def _revcomp(seq):
            comp = str.maketrans('ATGCNatgcn', 'TACGNtacgn')
            return str(seq).translate(comp)[::-1]

        if 'Sample_Project' in ss_data.columns:
            flexbar_mask = ss_data['Sample_Project'].str.contains('flexbar|pareseq', case=False, na=False, regex=True)
            if flexbar_mask.any():
                # Write barcode FASTA (R1-direction) before removing flexbar rows from ss_data.
                # FLEXBAR_CONFIGS in Snakefile detects this file to trigger inline_demux rules.
                inline_fasta_path = os.path.join("metadata", f"flexbar_barcodes_{config_id}.fasta")
                os.makedirs("metadata", exist_ok=True)
                with open(inline_fasta_path, 'w') as bf:
                    for _, row in ss_data[flexbar_mask].iterrows():
                        name = str(row.get('Sample_Name', '')).strip()
                        i2 = str(row.get('index2', '') or '').strip()
                        i2 = '' if i2.lower() in ('nan', '') else i2
                        if name and i2:
                            bf.write(f">{name}\n{_revcomp(i2)}\n")
                print(f"Generated {inline_fasta_path}")
                ss_data = ss_data[~flexbar_mask].reset_index(drop=True)
                lane_df = lane_df[~flexbar_mask].reset_index(drop=True)
                override_cycles_list = [oc for oc, fb in zip(override_cycles_list, flexbar_mask.values) if not fb]

        # fqtk samples are demultiplexed post-hoc from Undetermined reads using fqtk
        # (i7-only barcode matching via I1 reads).  Remove them from the DRAGEN sheet
        # and write metadata/fqtk_barcodes_{config_id}.tsv so the Snakefile can detect
        # the config and build FQTK_CONFIGS / FQTK_CONFIG_RENAMING_MAP at DAG time.
        if 'Sample_Project' in ss_data.columns:
            fqtk_mask = ss_data['Sample_Project'].str.contains('fqtk', case=False, na=False)
            if fqtk_mask.any():
                fqtk_tsv_path = os.path.join("metadata", f"fqtk_barcodes_{config_id}.tsv")
                os.makedirs("metadata", exist_ok=True)
                with open(fqtk_tsv_path, 'w') as tf:
                    tf.write("sample_id\tbarcode\n")
                    for _, row in ss_data[fqtk_mask].iterrows():
                        name = str(row.get('Sample_Name', '')).strip()
                        i1 = str(row.get('index', '') or '').strip()
                        i1 = '' if i1.lower() in ('nan', '') else i1
                        if name and i1:
                            tf.write(f"{name}\t{i1}\n")
                print(f"Generated {fqtk_tsv_path}")
                ss_data = ss_data[~fqtk_mask].reset_index(drop=True)
                lane_df = lane_df[~fqtk_mask].reset_index(drop=True)
                override_cycles_list = [oc for oc, fq in zip(override_cycles_list, fqtk_mask.values) if not fq]

        # Sort by Group so SampleSheet row order matches renaming map order (preserves S-number alignment)
        if 'Group' in lane_df.columns:
            group_order = pd.to_numeric(lane_df['Group'], errors='coerce').fillna(999).values
            sort_idx = sorted(range(len(group_order)), key=lambda i: group_order[i])
            ss_data = ss_data.iloc[sort_idx].reset_index(drop=True)
            lane_df = lane_df.iloc[sort_idx].reset_index(drop=True)
            override_cycles_list = [override_cycles_list[i] for i in sort_idx]

        # Reorder columns
        cols = ['Lane', 'Sample_ID', 'Sample_Name', 'index', 'index2', 'Sample_Project', 'OverrideCycles']
        # Add missing cols if any
        for c in cols:
            if c not in ss_data.columns:
                ss_data[c] = ""

        ss_data = ss_data[cols]
        
        outfile = os.path.join(out_dir, config_id, f"SampleSheet_{config_id}.csv")
        os.makedirs(os.path.join(out_dir, config_id), exist_ok=True)
        with open(outfile, 'w') as f:
            f.write("[Header]\n")
            f.write("FileFormatVersion,2\n")
            f.write("\n")
            
            # Add Settings block
            f.write("[BCLConvert_Settings]\n")

            # Special ATAC settings (BD_Rhapsody_ATACseq / 10xMultiomeATACseq)
            # If ANY project on the lane needs index read FASTQs, set globally for the run.
            # (DRAGEN 4.x does not support CreateFastqForIndexReads as a per-sample column.)
            _INDEX_READ_KEYWORDS = ["10x", "BD", "parse", "Parse", "SMK", "smk", "CITE", "cite", "Hashtag", "hashtag"]
            create_fastq_for_index = "0"
            if special_atac_index_reads:
                f.write("CreateFastqForIndexReads,1\n")
            else:
                # Check both Project Name and Sample Sheet tab columns for index-read keywords
                names_to_check = set()
                if 'Sample_Project' in ss_data.columns:
                    names_to_check.update(str(p) for p in ss_data['Sample_Project'].unique())
                if '__sheet_name__' in lane_df.columns:
                    names_to_check.update(str(s) for s in lane_df['__sheet_name__'].unique())
                if any(kw in name for name in names_to_check for kw in _INDEX_READ_KEYWORDS):
                    create_fastq_for_index = "1"
                f.write(f"CreateFastqForIndexReads,{create_fastq_for_index}\n")
            if special_10x_atac or special_atac_index_reads:
                f.write("TrimUMI,0\n")
            f.write("MinimumTrimmedReadLength,8\n")
            f.write("MaskShortReads,8\n")
            # When multiple masking groups with different index lengths are merged, DRAGEN
            # N-pads shorter indexes during collision detection, causing false hamming distance
            # errors. Set BarcodeMismatchesIndex1/2 to 0 only when:
            #   (a) samples have mixed effective index lengths for that position, AND
            #   (b) every sample uses that index (DRAGEN rejects a global setting when any sample lacks it)
            import re as _re
            def _effective_index_len(cycles_str, position):
                """Return the active I-read length for index position (1=I1, 2=I2).
                Returns 0 if that position is absent or is a pure N (skipped) read.
                """
                if not cycles_str:
                    return 0
                parts = cycles_str.split(';')
                if position >= len(parts):
                    return 0
                m = _re.match(r'^I(\d+)', parts[position])
                return int(m.group(1)) if m else 0

            i1_lens = [_effective_index_len(c, 1) for c in override_cycles_list]
            i2_lens = [_effective_index_len(c, 2) for c in override_cycles_list]
            # Use actual index columns to decide whether a barcode index exists.
            # Some assays (e.g., 10x) can have an I2 segment in OverrideCycles for
            # biology/UMI structure while index2 is intentionally blank.
            has_i1 = [bool(str(v).strip()) for v in ss_data['index'].fillna('').astype(str)]
            has_i2 = [bool(str(v).strip()) for v in ss_data['index2'].fillna('').astype(str)]

            # Use per-sample BarcodeMismatchesIndex1/2 columns instead of global settings.
            # DRAGEN rejects global settings when any sample lacks that index entirely (len=0).
            # Per-sample: 0 when active-index lengths are mixed (avoids N-pad collision errors),
            # 1 when all active-index samples share the same length. Samples with no active
            # index for that position get a blank cell (DRAGEN ignores blank per-sample values).
            active_i1 = [l for l, present in zip(i1_lens, has_i1) if present and l > 0]
            active_i2 = [l for l, present in zip(i2_lens, has_i2) if present and l > 0]
            mixed_i1 = len(set(active_i1)) > 1 if active_i1 else False
            mixed_i2 = len(set(active_i2)) > 1 if active_i2 else False

            if active_i1:
                ss_data['BarcodeMismatchesIndex1'] = [
                    (0 if mixed_i1 else 1) if (present and l > 0) else ''
                    for l, present in zip(i1_lens, has_i1)
                ]
            if active_i2:
                ss_data['BarcodeMismatchesIndex2'] = [
                    (0 if mixed_i2 else 1) if (present and l > 0) else ''
                    for l, present in zip(i2_lens, has_i2)
                ]
            f.write("FastqCompressionFormat,gzip\n")
            f.write("\n")
            
            f.write("[BCLConvert_Data]\n")
            ss_data.to_csv(f, index=False)
            
        generated_files[config_id] = outfile
        
        # Generate renaming map
        try:
            map_df = pd.DataFrame()
            # Sample_ID is a string that could be numeric or text (e.g., "66" or "SMKL12")
            map_df['Sample_ID'] = ss_data['Sample_ID'].astype(str)
            map_df['Sample_Name'] = ss_data['Sample_Name']
            map_df['Sample_Project'] = ss_data['Sample_Project']
            map_df['Lane'] = ss_data['Lane']
            map_df['index'] = ss_data['index']
            map_df['index2'] = ss_data['index2']
            map_df['Run'] = run_name
            
            # Add Group from lane_df
            # ss_data was constructed from lane_df, so indices should match
            def format_group(val):
                try:
                    return str(int(float(val)))
                except:
                    return str(val)
            map_df['Group'] = lane_df['Group'].apply(format_group).values
            
            # Add Position (P001, P002, ...) sorted by Group so Group 1 always gets lower positions
            map_df = map_df.sort_values(
                by='Group',
                key=lambda col: col.apply(lambda v: int(v) if str(v).isdigit() else float('inf')),
                kind='stable'
            ).reset_index(drop=True)
            positions = []
            for _ in range(len(map_df)):
                positions.append(f"P{lane_position_counter:03d}")
                lane_position_counter += 1
            map_df['Position'] = positions
            
            map_file = os.path.join(out_dir, config_id, f"renaming_map_{config_id}.csv")
            write_renaming_map(map_df, map_file)
        except Exception as e:
            print(f"Error generating renaming map for {config_id}: {e}")
        
        # Check for Flexbar projects and generate barcode file
        flexbar_samples = []
        if 'Sample_Project' in ss_data.columns:
            for idx, row in ss_data.iterrows():
                proj = str(row['Sample_Project'])
                if "flexbar" in proj.lower():
                    s_name = row['Sample_Name']
                    s_index = row['index']
                    
                    # Fallback to index2 if index is missing/nan
                    if pd.isna(s_index) or str(s_index).strip() == "" or str(s_index).lower() == "nan":
                        s_index = row['index2']
                    
                    # Check validity of the selected index
                    if not (pd.isna(s_index) or str(s_index).strip() == "" or str(s_index).lower() == "nan"):
                        if s_name:
                            flexbar_samples.append((s_name, s_index))
        
        if flexbar_samples:
            barcode_file = os.path.join("metadata", f"flexbar_barcodes_{config_id}.fasta")
            os.makedirs("metadata", exist_ok=True)
            with open(barcode_file, 'w') as bf:
                for name, idx in flexbar_samples:
                    bf.write(f">{name}\n{idx}\n")
            print(f"Generated {barcode_file}")
        
    return generated_files

# Retrieve project names from all generated SampleSheets
def get_all_projects(sample_sheets_dict):
    projects = set()
    for config_id, sheet_path in sample_sheets_dict.items():
        if os.path.exists(sheet_path):
            try:
                with open(sheet_path, 'r') as f:
                    lines = f.readlines()
                
                header_row = -1
                for i, line in enumerate(lines):
                    if line.strip().startswith("[BCLConvert_Data]") or line.strip().startswith("[Data]"):
                        header_row = i + 1
                        break
                
                if header_row != -1 and header_row < len(lines):
                    data_str = "".join(lines[header_row:])
                    df = pd.read_csv(StringIO(data_str))
                    if 'Sample_Project' in df.columns:
                        projs = df['Sample_Project'].dropna().astype(str).unique()
                        # Filter out 'nan' and empty strings
                        projs = [p for p in projs if p.lower() != 'nan' and p.strip() != '']
                        projects.update(projs)
            except Exception as e:
                print(f"Error reading projects from {sheet_path}: {e}")
    return sorted(list(projects))

# Map order_id to list of projects
def get_order_id_configs(sample_sheets_dict):
    order_id_to_projects = {}
    
    for config_id in sample_sheets_dict:
        map_path = f"results/{config_id}/renaming_map_{config_id}.csv"
        if os.path.exists(map_path):
            try:
                import time as _time
                df = None
                for _attempt in range(3):
                    try:
                        df = pd.read_csv(map_path)
                        if not df.empty:
                            break
                    except Exception:
                        pass
                    _time.sleep(2)
                if df is None or df.empty:
                    print(f"Warning: {map_path} was empty or unreadable after retries, skipping")
                    continue
                df['Sample_Project'] = df['Sample_Project'].astype(str)

                # Extract lane from config_id for lane-aware order lookup
                lane_match = re.match(r'lane(\d+)', config_id)
                config_lane = int(lane_match.group(1)) if lane_match else 0

                for project in df['Sample_Project'].unique():
                    project = str(project).strip()
                    if not project or project.lower() == 'nan':
                        continue

                    # Use per-group order_id lookup so duplicate project names on the
                    # same lane each map to their own order (not just the last-written one).
                    proj_rows = df[df['Sample_Project'] == project]
                    groups_seen = set()
                    for _, row in proj_rows.iterrows():
                        try:
                            g = int(float(row.get('Group', '')))
                            groups_seen.add(g)
                        except Exception:
                            pass

                    if groups_seen:
                        for g in groups_seen:
                            order_id = ORDER_ID_LOOKUP.get((config_lane, g),
                                PROJECT_ORDER_ID.get((project, config_lane), ""))
                            if order_id:
                                if order_id not in order_id_to_projects:
                                    order_id_to_projects[order_id] = set()
                                order_id_to_projects[order_id].add(project)
                    else:
                        order_id = PROJECT_ORDER_ID.get((project, config_lane), "")
                        if order_id:
                            if order_id not in order_id_to_projects:
                                order_id_to_projects[order_id] = set()
                            order_id_to_projects[order_id].add(project)
            except Exception as e:
                print(f"Error reading map file {map_path}: {e}")
    
    return order_id_to_projects

# Map each project to the set of lanes it appears in so we can emit per-lane reports.
def get_project_lane_pairs(sample_sheets_dict):
    pairs = set()
    for config_id in sample_sheets_dict:
        map_path = f"results/{config_id}/renaming_map_{config_id}.csv"
        if os.path.exists(map_path):
            try:
                df = pd.read_csv(map_path)
                df['Sample_Project'] = df['Sample_Project'].astype(str)
                for _, row in df.iterrows():
                    project = str(row.get('Sample_Project', '')).strip()
                    if not project or project.lower() == 'nan':
                        continue
                    try:
                        lane_val = int(float(row.get('Lane', '')))
                    except Exception:
                        continue
                    pairs.add((project, lane_val))
            except Exception as e:
                print(f"Error reading map file {map_path}: {e}")
    return sorted(pairs)

# Get (config_id, project) pairs for project links
def get_config_project_pairs(sample_sheets_dict):
    pairs = set()
    for config_id in sample_sheets_dict:
        map_path = f"results/{config_id}/renaming_map_{config_id}.csv"
        if os.path.exists(map_path):
            try:
                df = pd.read_csv(map_path)
                df['Sample_Project'] = df['Sample_Project'].astype(str)
                for project in df['Sample_Project'].unique():
                    project = str(project).strip()
                    if project and project.lower() != 'nan':
                        pairs.add((config_id, project))
            except Exception as e:
                print(f"Error reading map file {map_path}: {e}")
    return sorted(list(pairs))

def get_order_id_plot_targets(order_id):
    """Get all fastp plot targets for all projects in a given order_id."""
    targets = []
    projects = ORDER_ID_CONFIGS.get(order_id, set())
    
    for project in projects:
        project_targets = get_project_plot_targets(project, lane_filter=None, order_id=order_id)
        targets.extend(project_targets)
    
    return targets

def get_order_id_fastq_links(yaml_path, order_id):
    """Get all fastq links for all projects in a given order_id."""
    all_links = {}
    projects = ORDER_ID_CONFIGS.get(order_id, set())
    
    for project in projects:
        links_str = get_project_links_from_yaml(yaml_path, project, lane=None, order_id=order_id)
        if links_str and links_str != "https://precision.biochem.uci.edu/":
            all_links[project] = links_str
    
    return all_links

def get_project_plot_targets(project, lane_filter=None, order_id=None):
    targets = []
    
    for config_id in CONFIG_IDS:
        try:
            df = _fastp_rows_for_config(config_id)
            if df is None:
                continue
            df['Sample_Project'] = df['Sample_Project'].astype(str)
            # Resolve renamed project name -> original name for CSV lookup
            orig_project = PROJECT_RENAME_MAP_INV.get((config_id, project), project)
            project_samples = df[df['Sample_Project'] == orig_project]

            for idx, row in project_samples.iterrows():
                try:
                    lane_val = int(float(row.get('Lane', 0)))
                except Exception:
                    continue
                if lane_filter is not None and lane_val != lane_filter:
                    continue

                # Filter by Order ID if specified
                if order_id is not None:
                    try:
                        group_val = int(float(row.get('Group', 0)))
                        sample_order_id = ORDER_ID_LOOKUP.get((lane_val, group_val))
                        if sample_order_id != order_id:
                            continue
                    except Exception:
                        continue

                sample_name = str(row.get('Sample_Name', '')).strip()
                run = str(row.get('Run', '')).strip()
                try:
                    group = str(int(float(row.get('Group', 0))))
                except:
                    group = str(row.get('Group', '')).strip()
                if group.lower() == 'nan' or not group:
                    group = "Undetermined"

                index1 = str(row.get('index', '')).strip()
                if index1.lower() == 'nan':
                    index1 = ""
                index2 = str(row.get('index2', '')).strip()
                if index2.lower() == 'nan':
                    index2 = ""

                barcode = f"{index1}-{index2}" if index2 else index1
                position = str(row.get('Position', f"P{idx+1:03d}")).strip()

                output_project = PROJECT_RENAME_MAP.get((config_id, orig_project), orig_project)
                if is_parse_or_10x(orig_project):
                    if not sample_name or sample_name.lower() == 'nan':
                        continue
                    path = f"{output_project}/{sample_name}"
                else:
                    stem = f"{run}-L{lane_val}-G{group}-{position}-{barcode}"
                    path = f"{output_project}/{stem}"

                targets.append(f"results/{config_id}/{path}-mean_phred.png")
                targets.append(f"results/{config_id}/{path}-base_comp.png")
        except Exception as e:
            print(f"Error building plot targets for {project} in {config_id}: {e}")
    return targets

def read_sample_sheet(config_id):
    sheet_path = f"results/{config_id}/SampleSheet_{config_id}.csv"
    if not os.path.exists(sheet_path):
        return None
    
    with open(sheet_path, 'r') as f:
        lines = f.readlines()
    
    header_row_idx = -1
    for i, line in enumerate(lines):
        if line.strip().startswith("[BCLConvert_Data]") or line.strip().startswith("[Data]"):
            header_row_idx = i + 1
            break
            
    if header_row_idx == -1 or header_row_idx >= len(lines):
        return None
        
    data_str = "".join(lines[header_row_idx:])
    try:
        return pd.read_csv(StringIO(data_str))
    except:
        return None

def _fastp_row_path(row, idx):
    project = str(row.get('Sample_Project', '')).strip()
    sample_name = str(row.get('Sample_Name', '')).strip()

    run = str(row.get('Run', '')).strip()
    lane = int(row.get('Lane', 0))
    config_id = f"lane{lane}"
    output_project = PROJECT_RENAME_MAP.get((config_id, project), project)
    try:
        group = str(int(float(row.get('Group', 0))))
    except:
        group = str(row.get('Group', '')).strip()
    if group.lower() == 'nan' or not group:
        group = "Undetermined"

    index1 = str(row.get('index', '')).strip()
    if index1.lower() == 'nan':
        index1 = ""
    index2 = str(row.get('index2', '')).strip()
    if index2.lower() == 'nan':
        index2 = ""

    if index2:
        barcode = f"{index1}-{index2}"
    else:
        barcode = index1

    position = str(row.get('Position', f"P{idx+1:03d}")).strip()

    if is_parse_or_10x(project):
        if not sample_name or sample_name.lower() == 'nan':
            return None
        return f"{output_project}/{sample_name}" if output_project and output_project.lower() != 'nan' else sample_name

    stem = f"{run}-L{lane}-G{group}-{position}-{barcode}"
    return f"{output_project}/{stem}" if output_project and output_project.lower() != 'nan' else stem

def _fastp_rows_for_config(config_id):
    frames = []
    map_path = f"results/{config_id}/renaming_map_{config_id}.csv"
    if os.path.exists(map_path):
        try:
            frames.append(pd.read_csv(map_path))
        except Exception as e:
            print(f"Error reading map file {map_path}: {e}")

    flex_rows = globals().get('FLEXBAR_CONFIG_RENAMING_MAP', {}).get(config_id, [])
    if flex_rows:
        frames.append(pd.DataFrame(flex_rows))

    fqtk_rows = globals().get('FQTK_CONFIG_RENAMING_MAP', {}).get(config_id, [])
    if fqtk_rows:
        frames.append(pd.DataFrame(fqtk_rows))

    if not frames:
        return None
    return pd.concat(frames, ignore_index=True)

def get_fastp_targets(wildcards):
    config_id = wildcards.config_id
    df = _fastp_rows_for_config(config_id)
    if df is not None:
        try:
            targets = []
            for idx, row in df.iterrows():
                path = _fastp_row_path(row, idx)
                if path:
                    targets.append(f"results/{config_id}/{path}.fastp.json")
            return list(dict.fromkeys(targets))
        except Exception as e:
            print(f"Error building fastp targets for {config_id}: {e}")

    # Fallback to SampleSheet (old naming) - though we prefer map
    df = read_sample_sheet(config_id)
    if df is None:
        return []
    
    targets = []
    for idx, row in df.iterrows():
        path = _fastp_row_path(row, idx)
        if path:
            targets.append(f"results/fastp/{config_id}/{path}.json")
    return targets

def get_fastp_sample_input(wildcards):
    config_id = wildcards.config_id
    sample_path = wildcards.sample_path

    # Try to use renaming map first, then injected flexbar rows.
    map_path = f"results/{config_id}/renaming_map_{config_id}.csv"
    import time as _time
    df = None
    if os.path.exists(map_path):
        for _attempt in range(5):
            try:
                df = pd.read_csv(map_path)
                break
            except pd.errors.EmptyDataError:
                print(f"Renaming map {map_path} is empty (attempt {_attempt + 1}/5), retrying in 2s...")
                _time.sleep(2)

    if df is None:
        flex_rows = globals().get('FLEXBAR_CONFIG_RENAMING_MAP', {}).get(config_id, [])
        if flex_rows:
            df = pd.DataFrame(flex_rows)
    else:
        flex_rows = globals().get('FLEXBAR_CONFIG_RENAMING_MAP', {}).get(config_id, [])
        if flex_rows:
            df = pd.concat([df, pd.DataFrame(flex_rows)], ignore_index=True)

    fqtk_rows = globals().get('FQTK_CONFIG_RENAMING_MAP', {}).get(config_id, [])
    if fqtk_rows:
        fqtk_df = pd.DataFrame(fqtk_rows)
        df = pd.concat([df, fqtk_df], ignore_index=True) if df is not None else fqtk_df

    if df is None:
        raise ValueError(f"Renaming map not found and no flexbar/fqtk rows available: {config_id}")

    try:
        for idx, row in df.iterrows():
            path = _fastp_row_path(row, idx)
            if not path:
                continue
            
            path_stem = path.split('/', 1)[1] if '/' in path else path
            sample_stem = sample_path.split('/', 1)[1] if '/' in sample_path else sample_path
            if path == sample_path or path_stem == sample_stem:
                project = str(row.get('Sample_Project', '')).strip()
                sample_name = str(row.get('Sample_Name', '')).strip()
                run = str(row.get('Run', '')).strip()
                lane = int(row.get('Lane', 0))
                try:
                    group = str(int(float(row.get('Group', 0))))
                except:
                    group = str(row.get('Group', '')).strip()
                prefix = f"output/{config_id}"
                if project and project.lower() != 'nan':
                    output_project = PROJECT_RENAME_MAP.get((config_id, project), project)
                    prefix = f"{prefix}/{output_project}"
                
                if is_parse_or_10x(project):
                    import glob as _glob
                    matches = _glob.glob(f"{prefix}/{sample_name}_S*_L{lane:03d}_R1_001.fastq.gz")
                    if not matches:
                        # Directory doesn't exist yet (BCL convert hasn't run); return a
                        # predictable placeholder so dry-run DAG evaluation doesn't abort.
                        # The real path is resolved at execution time after normalize_project_fastq_names.
                        r1 = f"{prefix}/{sample_name}_S1_L{lane:03d}_R1_001.fastq.gz"
                    else:
                        r1 = matches[0]
                    if NUM_READS > 1:
                        r2 = r1.replace('_R1_001.fastq.gz', '_R2_001.fastq.gz')
                        return [r1, r2]
                    else:
                        return [r1]
                else:
                    stem = path.split('/', 1)[1] if '/' in path else path
                    r1 = f"{prefix}/{stem}-R1.fastq.gz"
                    if NUM_READS > 1:
                        r2 = f"{prefix}/{stem}-R2.fastq.gz"
                        return [r1, r2]
                    else:
                        return [r1]
    except Exception as e:
        print(f"Error reading map file {map_path}: {e}")
        raise e

    raise ValueError(f"Could not find sample for config_id='{config_id}' and sample_path='{sample_path}' in renaming map.")

def get_fastp_plots_targets(wildcards):
    config_id = wildcards.config_id
    df = _fastp_rows_for_config(config_id)
    if df is None:
        df = read_sample_sheet(config_id)
    if df is None:
        return []
    
    targets = []
    for idx, row in df.iterrows():
        path = _fastp_row_path(row, idx)
        if path:
            targets.append(f"results/{config_id}/{path}-mean_phred.png")
            targets.append(f"results/{config_id}/{path}-base_comp.png")
    return targets

def get_project_fastp_targets(wildcards):
    project = wildcards.project
    targets = []
    
    for config_id in CONFIG_IDS:
        try:
            df = _fastp_rows_for_config(config_id)
            if df is None:
                continue
            df['Sample_Project'] = df['Sample_Project'].astype(str)

            # Filter for this project, allowing flexbar projects to resolve via
            # their original project names in the injected rows.
            orig_project = PROJECT_RENAME_MAP_INV.get((config_id, project), project)
            project_samples = df[df['Sample_Project'] == orig_project]

            for idx, row in project_samples.iterrows():
                path = _fastp_row_path(row, idx)
                if path:
                    targets.append(f"results/{config_id}/{path}.fastp.json")
        except Exception as e:
            print(f"Error building fastp targets for {project} in {config_id}: {e}")
    return targets

def get_project_demux_stats(wildcards):
    return [
        f"output/{config_id}/Reports/Demultiplex_Stats.csv"
        for config_id, project in CONFIG_PROJECT_PAIRS
        if project == wildcards.project
    ]

def get_fastp_plots_lane_inputs(wildcards):
    lane = wildcards.lane
    config_id = f"lane{lane}"
    if config_id in CONFIG_IDS:
        return [f"results/{config_id}/fastp_plots_{config_id}.done"]
    return []

def get_bcl_convert_fastqs(wildcards):
    import pandas as pd
    import os
    config_id = wildcards.config_id
    map_path = f"results/{config_id}/renaming_map_{config_id}.csv"
    if not os.path.exists(map_path):
        return []
    df = pd.read_csv(map_path)
    fastqs = []
    for idx, row in df.iterrows():
        project = str(row.get('Sample_Project', '')).strip()
        sample_name = str(row.get('Sample_Name', '')).strip()
        run = str(row.get('Run', '')).strip()
        lane = int(row.get('Lane', 0))
        try:
            group = str(int(float(row.get('Group', 0))))
        except:
            group = str(row.get('Group', '')).strip()
        if group.lower() == 'nan' or not group:
            group = "Undetermined"
        index1 = str(row.get('index', '')).strip()
        if index1.lower() == 'nan':
            index1 = ""
        index2 = str(row.get('index2', '')).strip()
        if index2.lower() == 'nan':
            index2 = ""
        if index2:
            barcode = f"{index1}-{index2}"
        else:
            barcode = index1
        position = str(row.get('Position', f"P{idx+1:03d}")).strip()
        # Custom naming (default)
        stem = f"{run}-L{lane}-G{group}-{position}-{barcode}"
        fqdir = f"output/{config_id}"
        if project and project.lower() != 'nan':
            fqdir = f"{fqdir}/{project}"
        for read in ['R1', 'R2']:
            fastqs.append(f"{fqdir}/{stem}-{read}.fastq.gz")
    return fastqs

# Helper: get lane for a config_id
def get_lane_for_config(config_id):
    for config in LANE_CONFIGS:
        if config['id'] == config_id:
            return config.get('lane')
    return None

# Helper: get all config_ids for a lane
def get_config_ids_for_lane(lane):
    return [config['id'] for config in LANE_CONFIGS if config.get('lane') == lane]

# Helper: get index sequences from a SampleSheet CSV
def get_index_sequences_from_samplesheet(samplesheet_path):
    import csv
    indexes = set()
    if os.path.exists(samplesheet_path):
        with open(samplesheet_path) as f:
            reader = csv.DictReader(f)
            for row in reader:
                idx = row.get('index')
                idx2 = row.get('index2')
                if idx:
                    if idx2:
                        indexes.add(f"{idx}+{idx2}")
                    else:
                        indexes.add(idx)
    return indexes