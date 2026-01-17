import os
import re
import yaml
import pandas as pd
import xml.etree.ElementTree as ET
from io import StringIO

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
        links = PROJECT_LINKS.get(project, ["https://precision.biochem.uci.edu/s/x8PGTAWcXbrRySG"])
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
            return "https://precision.biochem.uci.edu/s/x8PGTAWcXbrRySG"
        
        with open(yaml_path, 'r') as f:
            links_data = yaml.safe_load(f)
        
        if not links_data or project not in links_data:
            return "https://precision.biochem.uci.edu/s/x8PGTAWcXbrRySG"
        
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
            return "https://precision.biochem.uci.edu/s/x8PGTAWcXbrRySG"
        
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
        return "https://precision.biochem.uci.edu/s/x8PGTAWcXbrRySG"

# 10x/Parse/BD naming: keep Illumina default (<sample>_S<num>_L00<lane>_R<read>_001.fastq.gz)
def is_parse_or_10x(project_name):
    try:
        p = str(project_name or "").lower()
    except Exception:
        p = ""
    return ("10x" in p) or ("parse" in p) or ("bd" in p)

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

def generate_lane_samplesheets(metadata_file, lane_configs, project_lookup, masking_lookup, out_dir, run_info_path=None):
    if not metadata_file or not os.path.exists(metadata_file):
        print("Metadata file not found.")
        return {}
        
    # print(f"Generating sample sheets from {metadata_file}")
    
    # Extract run name from metadata filename
    run_name = "Run"
    try:
        base = os.path.basename(metadata_file)
        name_part = os.path.splitext(base)[0]
        parts = name_part.split('_')
        if parts:
            run_name = parts[-1]
    except:
        pass
    
    # Get actual run read lengths
    run_reads = get_run_read_lengths(run_info_path)
    
    all_samples = pd.DataFrame()
    
    try:
        xl = pd.ExcelFile(metadata_file)
        for sheet in xl.sheet_names:
            if sheet == "Summary":
                continue
            
            # print(f"Reading sheet: {sheet}")
            try:
                # Read raw to find header
                df_raw = pd.read_excel(metadata_file, sheet_name=sheet, header=None)
                
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
                    
                df = pd.read_excel(metadata_file, sheet_name=sheet, header=header_row)
                
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
                else:
                    sheet_samples['Group'] = pd.NA

                # Project
                if 'Project name' in df.columns:
                    df['Project name'] = df['Project name'].ffill()
                    sheet_samples['Project'] = df['Project name']
                elif 'Sample_Project' in df.columns:
                    df['Sample_Project'] = df['Sample_Project'].ffill()
                    sheet_samples['Project'] = df['Sample_Project']
                else:
                    sheet_samples['Project'] = pd.NA
                
                # Fill missing Project from Lookup using Lane and Group
                def fill_project(row):
                    if pd.isna(row['Project']) or str(row['Project']).strip() == "" or str(row['Project']).lower() == 'nan':
                        try:
                            l = int(float(row['Lane']))
                            g = int(float(row['Group']))
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
    
    # Assign Masking to samples based on Lane and Group
    def get_sample_masking(row):
        try:
            l = int(float(row['Lane']))
            g = int(float(row['Group']))
            return masking_lookup.get((l, g), "")
        except:
            return ""
            
    df['Masking'] = df.apply(get_sample_masking, axis=1)
    
    generated_files = {}
    
    # Ensure output directory exists
    os.makedirs(out_dir, exist_ok=True)
    
    global_position_counter = 1

    for config in lane_configs:
        lane = config['lane']
        masking = config['masking']
        masking_sanitized = config['masking_sanitized']
        
        # Filter by Lane AND Masking
        lane_df = df[(df['Lane'] == lane) & (df['Masking'] == masking)].copy()
        
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

        valid_indices = lane_df['index'].apply(is_valid_index)
        if valid_indices.any():
            lane_df = lane_df[valid_indices]
        
        if lane_df.empty:
            print(f"No samples found for lane {lane} with masking {masking}")
            continue
            
        # Map columns
        # Target: Project,Lane,Sample_ID,Sample_Name,index,index2,Sample_Project
        
        ss_data = pd.DataFrame()
        
        ss_data['Lane'] = lane_df['Lane']
        ss_data['Project'] = lane_df['Project']
        ss_data['Sample_Project'] = lane_df['Project']
        
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
        
        # Calculate OverrideCycles and Index flags
        override_cycles = ""
        has_index1 = False
        has_index2 = False
        
        if masking:
            # Masking format from metadata: "R1:151, I1:8, I2:8, R2:151"
            # Target format: Y151;I8;I8;Y151
            
            try:
                parts = [p.strip() for p in masking.split(',')]
                cycles = []
                for i, p in enumerate(parts):
                    if ':' in p:
                        type_, len_ = p.split(':')
                        type_ = type_.strip().upper()
                        len_ = len_.strip()
                        specified_len = int(len_)
                        
                        if type_ == 'I1' and specified_len > 0:
                            has_index1 = True
                        if type_ == 'I2' and specified_len > 0:
                            has_index2 = True
                        
                        cycle_str = ""
                        
                        # Get actual length from RunInfo if available
                        actual_len = 0
                        is_indexed_read = False
                        if run_reads and i < len(run_reads):
                            actual_len = run_reads[i]['NumCycles']
                            is_indexed_read = run_reads[i].get('IsIndexedRead') == 'Y'
                        
                        # Handle Y2 case: treat as UMI (U) matching actual length
                        if type_ == 'Y2':
                            if actual_len > 0:
                                cycle_str = f"U{actual_len}"
                            else:
                                cycle_str = f"U{specified_len}"
                        # Handle 0 length case: replace with N{actual_len} (skips the read)
                        elif specified_len == 0 and actual_len > 0:
                            cycle_str = f"N{actual_len}"
                        else:
                            if type_.startswith('R'):
                                cycle_str = f"Y{len_}"
                            elif type_.startswith('I'):
                                cycle_str = f"I{len_}"
                            elif type_.startswith('U'):
                                cycle_str = f"U{len_}"
                            
                            # Pad with N if needed
                            if actual_len > 0 and specified_len > 0 and specified_len < actual_len:
                                diff = actual_len - specified_len
                                cycle_str += f"N{diff}"
                        
                        cycles.append(cycle_str)
                
                if cycles:
                    override_cycles = ";".join(cycles)
            except Exception as e:
                print(f"Error parsing masking '{masking}' for lane {lane}: {e}")

        ss_data['OverrideCycles'] = override_cycles

        # Reorder columns
        cols = ['Lane', 'Sample_ID', 'Sample_Name', 'index', 'index2', 'Sample_Project', 'OverrideCycles']
        # Add missing cols if any
        for c in cols:
            if c not in ss_data.columns:
                ss_data[c] = ""
                
        ss_data = ss_data[cols]
        
        outfile = os.path.join(out_dir, f"SampleSheet_lane{lane}_{masking_sanitized}.csv")
        with open(outfile, 'w') as f:
            f.write("[Header]\n")
            f.write("FileFormatVersion,2\n")
            f.write("\n")
            
            # Add Settings block
            f.write("[BCLConvert_Settings]\n")
            
            # Check if any project in this lane contains "10x", "BD", "parse" or "Parse"
            create_fastq_for_index = "0"
            if 'Sample_Project' in ss_data.columns:
                for proj in ss_data['Sample_Project'].unique():
                    proj_str = str(proj)
                    if any(keyword in proj_str for keyword in ["10x", "BD", "parse", "Parse"]):
                        create_fastq_for_index = "1"
                        break
            
            f.write(f"CreateFastqForIndexReads,{create_fastq_for_index}\n")
            f.write("MinimumTrimmedReadLength,8\n")
            f.write("MaskShortReads,8\n")
            # if has_index1:
            #     f.write("BarcodeMismatchesIndex1,1\n")
            # if has_index2:
            #     f.write("BarcodeMismatchesIndex2,1\n")
            f.write("FastqCompressionFormat,gzip\n")
            f.write("\n")
            
            f.write("[BCLConvert_Data]\n")
            ss_data.to_csv(f, index=False)
            
        generated_files[config['id']] = outfile
        
        # Generate renaming map
        try:
            map_df = pd.DataFrame()
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
            
            # Add Position (P001, P002, etc.)
            positions = []
            for _ in range(len(ss_data)):
                positions.append(f"P{global_position_counter:03d}")
                global_position_counter += 1
            map_df['Position'] = positions
            
            map_file = os.path.join(out_dir, f"renaming_map_{config['id']}.csv")
            map_df.to_csv(map_file, index=False)
        except Exception as e:
            print(f"Error generating renaming map for {config['id']}: {e}")
        
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
            barcode_file = os.path.join("metadata", f"flexbar_barcodes_{config['id']}.fasta")
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
        map_path = f"src/renaming_map_{config_id}.csv"
        if os.path.exists(map_path):
            try:
                df = pd.read_csv(map_path)
                df['Sample_Project'] = df['Sample_Project'].astype(str)
                
                for project in df['Sample_Project'].unique():
                    project = str(project).strip()
                    if not project or project.lower() == 'nan':
                        continue
                    
                    # Get order_id for this project
                    order_id = PROJECT_ORDER_ID.get(project, "")
                    
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
        map_path = f"src/renaming_map_{config_id}.csv"
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
        map_path = f"src/renaming_map_{config_id}.csv"
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
        if links_str and links_str != "https://precision.biochem.uci.edu/s/x8PGTAWcXbrRySG":
            all_links[project] = links_str
    
    return all_links

def get_project_plot_targets(project, lane_filter=None, order_id=None):
    targets = []
    
    for config_id in CONFIG_IDS:
        map_path = f"src/renaming_map_{config_id}.csv"
        if os.path.exists(map_path):
            try:
                df = pd.read_csv(map_path)
                df['Sample_Project'] = df['Sample_Project'].astype(str)
                project_samples = df[df['Sample_Project'] == project]
                
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
                    
                    if is_parse_or_10x(project):
                        if not sample_name or sample_name.lower() == 'nan':
                            continue
                        path = f"{project}/{sample_name}"
                    else:
                        stem = f"{run}-L{lane_val}-G{group}-{position}-{barcode}"
                        path = f"{project}/{stem}"
                    
                    targets.append(f"results/fastp_plots/{config_id}/{path}-mean_phred.png")
                    targets.append(f"results/fastp_plots/{config_id}/{path}-base_comp.png")
            except Exception as e:
                print(f"Error reading map file {map_path}: {e}")
    return targets

def read_sample_sheet(config_id):
    sheet_path = f"src/SampleSheet_{config_id}.csv"
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

def get_fastp_targets(wildcards):
    config_id = wildcards.config_id
    
    # Use renaming map to define targets
    map_path = f"src/renaming_map_{config_id}.csv"
    if os.path.exists(map_path):
        try:
            df = pd.read_csv(map_path)
            targets = []
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
                
                # Construct filename path based on convention
                if is_parse_or_10x(project):
                    if not sample_name or sample_name.lower() == 'nan':
                        continue
                    path = f"{project}/{sample_name}" if project and project.lower() != 'nan' else sample_name
                else:
                    stem = f"{run}-L{lane}-G{group}-{position}-{barcode}"
                    path = f"{project}/{stem}" if project and project.lower() != 'nan' else stem
                    
                targets.append(f"results/fastp/{config_id}/{path}.json")
            return targets
        except Exception as e:
            print(f"Error reading map file {map_path}: {e}")
            return []
            
    # Fallback to SampleSheet (old naming) - though we prefer map
    df = read_sample_sheet(config_id)
    if df is None:
        return []
    
    targets = []
    for idx, row in df.iterrows():
        project = str(row.get('Sample_Project', '')).strip()
        sample = str(row.get('Sample_Name', row.get('Sample_ID', ''))).strip()
        
        if not sample or sample.lower() == 'nan':
            continue

        if project and project.lower() != 'nan':
            path = f"{project}/{sample}"
        else:
            path = sample
        targets.append(f"results/fastp/{config_id}/{path}.json")
    return targets

def get_fastp_sample_input(wildcards):
    config_id = wildcards.config_id
    sample_path = wildcards.sample_path
    
    # Try to use renaming map first
    map_path = f"src/renaming_map_{config_id}.csv"
    if not os.path.exists(map_path):
        raise ValueError(f"Renaming map not found: {map_path}")
        
    try:
        df = pd.read_csv(map_path)
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
            
            # Construct sample_path consistently with get_fastp_targets
            if is_parse_or_10x(project):
                if not sample_name or sample_name.lower() == 'nan':
                    continue
                path = f"{project}/{sample_name}" if project and project.lower() != 'nan' else sample_name
            else:
                stem = f"{run}-L{lane}-G{group}-{position}-{barcode}"
                path = f"{project}/{stem}" if project and project.lower() != 'nan' else stem
            
            if path == sample_path:
                prefix = f"output/{config_id}"
                if project and project.lower() != 'nan':
                    prefix = f"{prefix}/{project}"
                
                if is_parse_or_10x(project):
                    s_num = idx + 1
                    r1 = f"{prefix}/{sample_name}_S{s_num}_L{lane:03d}_R1_001.fastq.gz"
                    if NUM_READS > 1:
                        r2 = f"{prefix}/{sample_name}_S{s_num}_L{lane:03d}_R2_001.fastq.gz"
                        return [r1, r2]
                    else:
                        return [r1]
                else:
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
    
    # Use renaming map to define targets
    map_path = f"src/renaming_map_{config_id}.csv"
    if os.path.exists(map_path):
        try:
            df = pd.read_csv(map_path)
            targets = []
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
                
                # Construct path based on convention
                if is_parse_or_10x(project):
                    if not sample_name or sample_name.lower() == 'nan':
                        continue
                    path = f"{project}/{sample_name}" if project and project.lower() != 'nan' else sample_name
                else:
                    stem = f"{run}-L{lane}-G{group}-{position}-{barcode}"
                    path = f"{project}/{stem}" if project and project.lower() != 'nan' else stem
                    
                targets.append(f"results/fastp_plots/{config_id}/{path}-mean_phred.png")
                targets.append(f"results/fastp_plots/{config_id}/{path}-base_comp.png")
            return targets
        except Exception as e:
            print(f"Error reading map file {map_path}: {e}")
            return []

    df = read_sample_sheet(config_id)
    if df is None:
        return []
    
    targets = []
    for idx, row in df.iterrows():
        project = str(row.get('Sample_Project', '')).strip()
        sample = str(row.get('Sample_Name', row.get('Sample_ID', ''))).strip()
        
        if not sample or sample.lower() == 'nan':
            continue

        if project and project.lower() != 'nan':
            path = f"{project}/{sample}"
        else:
            path = sample
        targets.append(f"results/fastp_plots/{config_id}/{path}-mean_phred.png")
        targets.append(f"results/fastp_plots/{config_id}/{path}-base_comp.png")
    return targets

def get_project_fastp_targets(wildcards):
    project = wildcards.project
    targets = []
    
    for config_id in CONFIG_IDS:
        map_path = f"src/renaming_map_{config_id}.csv"
        if os.path.exists(map_path):
            try:
                df = pd.read_csv(map_path)
                # Ensure string type for comparison
                df['Sample_Project'] = df['Sample_Project'].astype(str)
                
                # Filter for this project
                project_samples = df[df['Sample_Project'] == project]
                
                for idx, row in project_samples.iterrows():
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
                    
                    if is_parse_or_10x(project):
                        if not sample_name or sample_name.lower() == 'nan':
                            continue
                        path = f"{project}/{sample_name}"
                    else:
                        stem = f"{run}-L{lane}-G{group}-{position}-{barcode}"
                        path = f"{project}/{stem}"
                    
                    targets.append(f"results/fastp/{config_id}/{path}.json")
            except Exception as e:
                print(f"Error reading map file {map_path}: {e}")
    return targets

def get_fastp_plots_lane_inputs(wildcards):
    lane = wildcards.lane
    prefix = f"lane{lane}_"
    relevant_configs = [cid for cid in CONFIG_IDS if cid.startswith(prefix)]
    return [f"results/fastp_plots_{cid}.done" for cid in relevant_configs]

def get_bcl_convert_fastqs(wildcards):
    import pandas as pd
    import os
    config_id = wildcards.config_id
    map_path = f"src/renaming_map_{config_id}.csv"
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
