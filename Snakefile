import os
import re
import pandas as pd
import xml.etree.ElementTree as ET
from io import StringIO

envvars:
    "GMAIL_APP_PASSWORD"

configfile: "snakemake_config.yaml"

SCRIPTDIR = config.get("script_dir", "src/Tools")
SCRIPT = config.get("script_path", "src/Tools/postprocess/postprocess_hiseq_lane_centos7_test_gzip.pl")
SAMPLE_SHEET = config.get("sample_sheet", "src/SampleSheet_default.csv")
NUM_READS = config.get("num_reads", 2)
LIBRARY = config.get("library_name", "xR077")
FASTQDIR = config.get("fastqdir", "output")
START_S = config.get("start_s", 1)
DRYRUN = config.get("dryrun", False)
RUN_INFO_PATH = config.get("run_info_path", "src/RunInfo.xml")
DATA_DIR = config.get("data_dir", "/staging/nextcloud/NovaseqX/20251219_LH00626_0085_A23G5F2LT3")
TILES = config.get("tiles", "1_1101")

EMAIL_SENDER = config.get("email_sender", "kstachel@uci.edu")
EMAIL_RECIPIENT = config.get("email_recipient", "kstachel@uci.edu")
EMAIL_CC = config.get("email_cc", "kstachel@uci.edu")

# Auto-detect lanes from data/Data/Intensities/BaseCalls
detected_lanes = []
basecalls_path = config.get("basecalls_path", "data/Data/Intensities/BaseCalls")
if os.path.exists(basecalls_path):
    detected_lanes = sorted([
        int(d[1:]) for d in os.listdir(basecalls_path) 
        if d.startswith("L") and d[1:].isdigit() and os.path.isdir(os.path.join(basecalls_path, d))
    ])

print("detected_lanes:", detected_lanes)

metadata = config.get("metadata", "metadata/SampleSheet.xlsx")

METADATA_FILE = config.get("metadata")
LANE_CONFIGS = []
PROJECT_LOOKUP = {}
MASKING_LOOKUP = {}
PROJECT_LINKS = {}
PROJECT_LINKS_BY_LANE = {}

if METADATA_FILE and os.path.exists(METADATA_FILE):
    try:
        df = pd.read_excel(METADATA_FILE, sheet_name="Summary", header=2)
        
        # Build Project and Masking Lookups: (Lane, Group) -> Value
        if 'Lane' in df.columns and 'Gr' in df.columns:
             for index, row in df.iterrows():
                 try:
                     l = int(float(row['Lane']))
                     g = int(float(row['Gr']))
                     
                     if 'Project Name' in df.columns:
                        p = str(row['Project Name']).strip()
                        PROJECT_LOOKUP[(l, g)] = p
                        
                        # Check for Fastq Link
                        link_col = None
                        for col in ['Fastq Link', 'fastq link', 'Fastq link', 'Download Link', 'download link']:
                            if col in df.columns:
                                link_col = col
                                break
                        
                        if link_col:
                             link = str(row[link_col]).strip()
                             if link and link.lower() != 'nan':
                                 # Accumulate multiple links per project (e.g., multiple lanes)
                                 PROJECT_LINKS.setdefault(p, []).append(link)
                                 # Also accumulate links per (project, lane) for lane-specific reports
                                 PROJECT_LINKS_BY_LANE.setdefault((p, l), []).append(link)
                     
                     if 'Masking' in df.columns:
                        m = str(row['Masking']).strip()
                        MASKING_LOOKUP[(l, g)] = m
                 except:
                     pass
        
        if 'Lane' in df.columns and 'Masking' in df.columns:
            # Collect unique (Lane, Masking) combinations
            groups = df[['Lane', 'Masking']].drop_duplicates()
            for index, row in groups.iterrows():
                try:
                    lane = int(float(row['Lane']))
                    masking = str(row['Masking']).strip()
                    # Sanitize masking for filename
                    # Example: "R1:151, I1:8, I2:8, R2:151" -> "R1-151_I1-8_I2-8_R2-151"
                    masking_sanitized = masking.replace(":", "-").replace(", ", "_").replace(",", "_").replace(" ", "")
                    
                    LANE_CONFIGS.append({
                        'lane': lane,
                        'masking': masking,
                        'masking_sanitized': masking_sanitized,
                        'id': f"lane{lane}_{masking_sanitized}"
                    })
                except ValueError:
                    continue
    except Exception as e:
        print(f"Error reading metadata: {e}")

print("LANE_CONFIGS:", LANE_CONFIGS)
print("PROJECT_LOOKUP:", PROJECT_LOOKUP)
print("MASKING_LOOKUP:", MASKING_LOOKUP)
print("PROJECT_LINKS_BY_LANE:", PROJECT_LINKS_BY_LANE)

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
        
    print(f"Generating sample sheets from {metadata_file}")
    
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
            if sheet == "Summary": continue
            
            print(f"Reading sheet: {sheet}")
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
            if pd.isna(val): return False
            s = str(val).strip()
            if not s: return False
            if s.lower() == 'nan': return False
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
                if not name or name.lower() == 'nan': name = "Sample"
                
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
                        # Handle 0 length case: replace with I0N{actual_len} for index reads, N{actual_len} for data reads
                        elif specified_len == 0 and actual_len > 0:
                            if is_indexed_read:
                                cycle_str = f"I0N{actual_len}"
                            else:
                                cycle_str = f"N{actual_len}"
                        else:
                            if type_.startswith('R'):
                                cycle_str = f"Y{len_}"
                            elif type_.startswith('I'):
                                cycle_str = f"I{len_}"
                            elif type_.startswith('U'): # UMI?
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
        print(f"Generated {outfile}")
        
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
            print(f"Generated {map_file}")
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

SAMPLE_SHEETS_DICT = generate_lane_samplesheets(METADATA_FILE, LANE_CONFIGS, PROJECT_LOOKUP, MASKING_LOOKUP, "src", RUN_INFO_PATH)

print(SAMPLE_SHEETS_DICT)
print(RUN_INFO_PATH)

CONFIG_IDS = [c['id'] for c in LANE_CONFIGS] if LANE_CONFIGS else []
# Fallback if no metadata
if not CONFIG_IDS and detected_lanes:
    CONFIG_IDS = [f"lane{l}_default" for l in detected_lanes]

FASTP_THREADS = config.get("fastp_threads", 4)
FASTP_OUTDIR = config.get("fastp_outdir", "results/fastp")
FASTP_PLOTS_OUTDIR = config.get("fastp_plots_outdir", "results/fastp_plots")

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

PROJECTS = get_all_projects(SAMPLE_SHEETS_DICT)

print("PROJECTS found in SampleSheet:", PROJECTS)

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

PROJECT_LANES = get_project_lane_pairs(SAMPLE_SHEETS_DICT)
PROJECT_LANE_REPORTS = [f"Reports/{p}/lane{l}/index.html" for p, l in PROJECT_LANES]
PROJECT_LANE_MD5S = [f"Reports/{p}/lane{l}/md5sums.txt" for p, l in PROJECT_LANES]

print("PROJECT_LANES:", PROJECT_LANES)

# Identify configs that require Flexbar processing
FLEXBAR_CONFIGS = []
for config in LANE_CONFIGS:
    # Only include configs for which a barcode file was generated
    # This avoids scheduling flexbar for lanes/maskings without flexbar samples
    barcode_path = os.path.join("metadata", f"flexbar_barcodes_{config['id']}.fasta")
    if os.path.exists(barcode_path):
        FLEXBAR_CONFIGS.append(config['id'])

print("FLEXBAR_CONFIGS:", FLEXBAR_CONFIGS)

rule all:
    input:
        # expand("results/postprocess_{config_id}.done", config_id=CONFIG_IDS),
        expand("results/fastp_plots_{config_id}.done", config_id=CONFIG_IDS),
        expand("output/{config_id}/.done", config_id=CONFIG_IDS),
        PROJECT_LANE_REPORTS,
        PROJECT_LANE_MD5S,
        # expand("results/flexbar_{config_id}.done", config_id=FLEXBAR_CONFIGS),
        expand("results/fastp_plots_summary_lane{lane}.done", lane=detected_lanes),
        expand("results/undetermined_indices/{config_id}.csv", config_id=CONFIG_IDS),
        expand("results/read_counts_{project}.csv", project=PROJECTS),
        f"results/{LIBRARY}-count.csv",
        f"Reports/{LIBRARY}_read_counts_email.done",
        # expand("Reports/{project}/email_sent.done", project=PROJECTS),

def get_project_plot_targets(project, lane_filter=None):
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
                    
                    sample_name = str(row.get('Sample_Name', '')).strip()
                    run = str(row.get('Run', '')).strip()
                    try:
                        group = str(int(float(row.get('Group', 0))))
                    except:
                        group = str(row.get('Group', '')).strip()
                    if group.lower() == 'nan' or not group: group = "Undetermined"
                    
                    index1 = str(row.get('index', '')).strip()
                    if index1.lower() == 'nan': index1 = ""
                    index2 = str(row.get('index2', '')).strip()
                    if index2.lower() == 'nan': index2 = ""
                    
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

rule report_project:
    input:
        fastp_plots = lambda wildcards: get_project_plot_targets(wildcards.project, int(wildcards.lane))
    output:
        html = "Reports/{project}/lane{lane}/index.html",
        md5 = "Reports/{project}/lane{lane}/md5sums.txt"
    params:
        project = "{project}",
        lane = "{lane}",
        output_base = "output",
        fastp_plots_base = FASTP_PLOTS_OUTDIR,
        fastp_base = FASTP_OUTDIR,
        report_dir = "Reports/{project}/lane{lane}",
        fastq_links = lambda wildcards: get_fastq_links_for_project_lane(wildcards.project, wildcards.lane)
    shell:
        "python3 src/generate_report.py {params.project} {params.output_base} {params.fastp_plots_base} {params.fastp_base} {params.report_dir} \"{params.fastq_links}\" {params.lane}"

rule send_project_email:
    input:
        html = "Reports/{project}/index.html",
        md5 = "Reports/{project}/md5sums.txt"
    output:
        touch("Reports/{project}/email_sent.done")
    params:
        script = "src/send_email.py",
        sender = "kstachel@uci.edu",
        receiver = "kstachel@uci.edu",
        subject = lambda wildcards: f"Sequencing Report for Project {wildcards.project}"
    shell:
        "python3 {params.script} {params.sender} {params.receiver} \"{params.subject}\" {input.html} {input.md5} {params.cc_email} && touch {output}"

rule postprocess_lane:
    input:
        "output/{config_id}"
    output:
        touch("results/postprocess_{config_id}.done")
    params:
        scriptdir = SCRIPTDIR,
        script = SCRIPT,
        sample_sheet = lambda wildcards: f"src/renaming_map_{wildcards.config_id}.csv",
        num_reads = NUM_READS,
        library = LIBRARY,
        fastqdir = "output/{config_id}",
        start_s = START_S,
        dryflag = "--dryrun" if DRYRUN else "",
        lane = lambda wildcards: wildcards.config_id.split('_')[0].replace('lane', '')
    threads: 4
    conda: "perl_env"
    shell:
        """
        mkdir -p results
        perl {params.script} {params.sample_sheet} {params.num_reads} {params.lane} "{params.library}" {params.fastqdir} {params.start_s} {params.dryflag}
        touch {output}
        """

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
                if group.lower() == 'nan' or not group: group = "Undetermined"
                
                index1 = str(row.get('index', '')).strip()
                if index1.lower() == 'nan': index1 = ""
                index2 = str(row.get('index2', '')).strip()
                if index2.lower() == 'nan': index2 = ""
                
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
    if df is None: return []
    
    targets = []
    for idx, row in df.iterrows():
        project = str(row.get('Sample_Project', '')).strip()
        sample = str(row.get('Sample_Name', row.get('Sample_ID', ''))).strip()
        
        if not sample or sample.lower() == 'nan': continue

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
            if group.lower() == 'nan' or not group: group = "Undetermined"
            
            index1 = str(row.get('index', '')).strip()
            if index1.lower() == 'nan': index1 = ""
            index2 = str(row.get('index2', '')).strip()
            if index2.lower() == 'nan': index2 = ""
            
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

    # Fallback removed to ensure we use renamed files
    # If we get here, we didn't find the sample in the map
    raise ValueError(f"Could not find sample for config_id='{config_id}' and sample_path='{sample_path}' in renaming map.")
    
    # If we get here, we didn't find the sample
    # This should not happen if get_fastp_targets is consistent
    # But if it does, raising an error is better than returning empty list
    raise ValueError(f"Could not find sample for config_id='{config_id}' and sample_path='{sample_path}' in sample sheet.")

rule fastp_sample:
    input:
        "output/{config_id}",
        "output/{config_id}/.done",
        fastqs = get_fastp_sample_input
    output:
        json = "results/fastp/{config_id}/{sample_path}.json",
        html = "results/fastp/{config_id}/{sample_path}.html"
    wildcard_constraints:
        config_id = "[^/]+",
        sample_path = ".*"
    params:
        threads = FASTP_THREADS
    threads: 4
    shell:
        """
        mkdir -p $(dirname {output.json})
        
        files=({input.fastqs})
        r1="${{files[0]}}"
        
        if [ ${{#files[@]}} -gt 1 ]; then
            r2="${{files[1]}}"
            fastp -i "$r1" -I "$r2" --json "{output.json}" --html "{output.html}" -w {params.threads}
        else
            fastp -i "$r1" --json "{output.json}" --html "{output.html}" -w {params.threads}
        fi
        """

rule fastp_per_config:
    input:
        get_fastp_targets
    output:
        touch("results/fastp_{config_id}.done")
    wildcard_constraints:
        config_id = "lane.*"

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

                if group.lower() == 'nan' or not group: group = "Undetermined"
                
                index1 = str(row.get('index', '')).strip()
                if index1.lower() == 'nan': index1 = ""
                index2 = str(row.get('index2', '')).strip()
                if index2.lower() == 'nan': index2 = ""
                
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
    if df is None: return []
    
    targets = []
    for idx, row in df.iterrows():
        project = str(row.get('Sample_Project', '')).strip()
        sample = str(row.get('Sample_Name', row.get('Sample_ID', ''))).strip()
        
        if not sample or sample.lower() == 'nan': continue

        if project and project.lower() != 'nan':
            path = f"{project}/{sample}"
        else:
            path = sample
        targets.append(f"results/fastp_plots/{config_id}/{path}-mean_phred.png")
        targets.append(f"results/fastp_plots/{config_id}/{path}-base_comp.png")
    return targets

rule fastp_plots_sample:
    input:
        json = "results/fastp/{config_id}/{sample_path}.json"
    output:
        mean = "results/fastp_plots/{config_id}/{sample_path}-mean_phred.png",
        base = "results/fastp_plots/{config_id}/{sample_path}-base_comp.png"
    wildcard_constraints:
        config_id = "[^/]+",
        sample_path = ".*"
    params:
        scripts_dir = SCRIPTDIR + "/analyze",
        sample_name = lambda wildcards: wildcards.sample_path
    threads: 1
    shell:
        """
        mkdir -p $(dirname {output.mean})
        python3 {params.scripts_dir}/mean_phred_plot_fastp.py "{input.json}" --out "{output.mean}" --title "{params.sample_name}" || true
        python3 {params.scripts_dir}/base_composition_plot_fastp.py "{input.json}" --out "{output.base}" --title "{params.sample_name}" || true
        """

rule fastp_plots_per_config:
    input:
        get_fastp_plots_targets
    output:
        touch("results/fastp_plots_{config_id}.done")
    wildcard_constraints:
        config_id = "lane.*"

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
                    if group.lower() == 'nan' or not group: group = "Undetermined"
                    
                    index1 = str(row.get('index', '')).strip()
                    if index1.lower() == 'nan': index1 = ""
                    index2 = str(row.get('index2', '')).strip()
                    if index2.lower() == 'nan': index2 = ""
                    
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

rule summarize_project_reads:
    input:
        get_project_fastp_targets
    output:
        "results/read_counts_{project}.csv"
    run:
        import json
        import pandas as pd
        import os
        
        data = []
        for json_file in input:
            try:
                with open(json_file, 'r') as f:
                    j = json.load(f)
                
                # Extract info from path or json
                # Path: results/fastp/{config_id}/{project}/{stem}.json
                parts = json_file.split('/')
                # parts[-1] is filename (stem.json)
                # parts[-2] is project
                # parts[-3] is config_id
                
                config_id = parts[-3]
                filename = parts[-1]
                sample_name = os.path.splitext(filename)[0]
                
                # Get read counts
                total_reads = j.get('summary', {}).get('before_filtering', {}).get('total_reads', 0)
                passed_reads = j.get('summary', {}).get('after_filtering', {}).get('total_reads', 0)
                
                data.append({
                    'Config': config_id,
                    'Project': wildcards.project,
                    'Sample': sample_name,
                    'Total_Reads': total_reads,
                    'Passed_Reads': passed_reads
                })
            except Exception as e:
                print(f"Error processing {json_file}: {e}")
        
        df = pd.DataFrame(data)
        if not df.empty:
            df = df.sort_values(['Config', 'Sample'])
        df.to_csv(output[0], index=False)

rule compile_read_counts:
    input:
        fastp_done = expand("results/fastp_{config_id}.done", config_id=CONFIG_IDS),
        maps = expand("src/renaming_map_{config_id}.csv", config_id=CONFIG_IDS)
    output:
        csv = f"results/{LIBRARY}-count.csv"
    run:
        import csv
        import json
        import os
        import pandas as pd

        lane_counts = {}

        for map_path in input.maps:
            if not os.path.exists(map_path):
                print(f"Skipping missing renaming map {map_path}")
                continue

            config_id = os.path.basename(map_path).replace("renaming_map_", "").replace(".csv", "")

            try:
                df = pd.read_csv(map_path)
            except Exception as e:
                print(f"Could not read {map_path}: {e}")
                continue

            for idx, row in df.iterrows():
                try:
                    lane = int(float(row.get("Lane", 0)))
                except Exception:
                    continue

                project = str(row.get("Sample_Project", "")).strip()
                sample_name = str(row.get("Sample_Name", row.get("Sample_ID", ""))).strip()
                if not sample_name or sample_name.lower() == "nan":
                    sample_name = str(row.get("Sample_ID", "")).strip() or "Unknown"

                run_name = str(row.get("Run", "")).strip()
                if not run_name or run_name.lower() == "nan":
                    run_name = LIBRARY

                try:
                    group = str(int(float(row.get("Group", "")))).strip()
                except Exception:
                    group = str(row.get("Group", "")).strip()

                if not group or group.lower() == "nan":
                    group = "Undetermined"

                index1 = str(row.get("index", "")).strip()
                if index1.lower() == "nan":
                    index1 = ""

                index2 = str(row.get("index2", "")).strip()
                if index2.lower() == "nan":
                    index2 = ""

                barcode = f"{index1}-{index2}" if index2 else index1

                position = str(row.get("Position", f"P{idx + 1:03d}")).strip()

                stem = f"{run_name}-L{lane}-G{group}-{position}-{barcode}"
                sample_path = f"{project}/{stem}" if project and project.lower() != "nan" else stem

                json_path = os.path.join("results/fastp", config_id, f"{sample_path}.json")

                if not os.path.exists(json_path):
                    print(f"Missing fastp json for {sample_path}")
                    continue

                try:
                    with open(json_path, "r") as jf:
                        stats = json.load(jf)
                    reads = int(stats.get("summary", {}).get("before_filtering", {}).get("total_reads", 0))
                except Exception as e:
                    print(f"Error reading {json_path}: {e}")
                    reads = 0

                lane_counts.setdefault(lane, {})

                # Preserve metadata order grouped by Group then row index
                try:
                    group_order = int(float(row.get("Group", "")))
                except Exception:
                    group_order = float("inf")

                if sample_name not in lane_counts[lane]:
                    lane_counts[lane][sample_name] = [group_order, idx, 0]
                # Keep earliest group/index seen; always accumulate reads
                existing = lane_counts[lane][sample_name]
                existing[0] = min(existing[0], group_order)
                existing[1] = min(existing[1], idx)
                existing[2] += reads

        lanes_sorted = sorted(lane_counts.keys())

        if not lanes_sorted:
            os.makedirs(os.path.dirname(output.csv), exist_ok=True)
            open(output.csv, "w").close()
            return

        per_lane = {}
        for lane, samples in lane_counts.items():
            # sort by (group_order, row_index)
            ordered = sorted(samples.items(), key=lambda x: (x[1][0], x[1][1]))
            per_lane[lane] = [(name, total) for name, (_, _, total) in ordered]

        max_rows = max(len(v) for v in per_lane.values())

        header = [""]
        for lane in lanes_sorted:
            header.extend([f"lane{lane}", ""])

        rows = []
        for i in range(max_rows):
            row = []
            for lane in lanes_sorted:
                entries = per_lane.get(lane, [])
                if i < len(entries):
                    name, count = entries[i]
                    row.extend([name, f"{int(count):,}"])
                else:
                    row.extend(["", ""])
            rows.append(row)

        os.makedirs(os.path.dirname(output.csv), exist_ok=True)
        with open(output.csv, "w", newline="") as out_handle:
            writer = csv.writer(out_handle)
            writer.writerow(header)
            writer.writerows(rows)

rule send_read_counts_email:
    input:
        csv = f"results/{LIBRARY}-count.csv"
    output:
        touch(f"Reports/{LIBRARY}_read_counts_email.done")
    params:
        script = "src/send_email.py",
        sender = EMAIL_SENDER,
        receiver = EMAIL_RECIPIENT,
        subject = f"Read counts for {LIBRARY}",
        body = lambda wildcards: f"Attached: per-lane read counts for {LIBRARY}.",
        cc_email = EMAIL_CC
    shell:
        "python3 {params.script} {params.sender} {params.receiver} \"{params.subject}\" \"{params.body}\" {input.csv} {params.cc_email}"

def get_fastp_plots_lane_inputs(wildcards):
    lane = wildcards.lane
    prefix = f"lane{lane}_"
    relevant_configs = [cid for cid in CONFIG_IDS if cid.startswith(prefix)]
    return [f"results/fastp_plots_{cid}.done" for cid in relevant_configs]

rule fastp_plots_lane:
    input:
        get_fastp_plots_lane_inputs
    output:
        touch("results/fastp_plots_summary_lane{lane}.done")
    wildcard_constraints:
        lane = "\d+"

rule flexbar_per_config:
    input:
        bcl_dir = "output/{config_id}",
        # Expecting a barcode file named specifically for this config
        barcodes = "metadata/flexbar_barcodes_{config_id}.fasta",
        adapter = "src/flexbar/adapter.3.fa"
    conda: "perl_env"
    threads: 32
    output:
        touch("results/flexbar_{config_id}.done")
    log:
        "logs/flexbar_{config_id}.log"
    params:
        outdir = "output/{config_id}/flexbar",
        lane = lambda wildcards: wildcards.config_id.split('_')[0].replace('lane', ''),
        r1 = lambda wildcards: f"output/{wildcards.config_id}/Undetermined_S0_L00{wildcards.config_id.split('_')[0].replace('lane', '')}_R1_001.fastq.gz",
        r2 = lambda wildcards: f"output/{wildcards.config_id}/Undetermined_S0_L00{wildcards.config_id.split('_')[0].replace('lane', '')}_R2_001.fastq.gz",
        barcodes_abs = lambda wildcards, input: os.path.abspath(input.barcodes),
        adapter_abs = lambda wildcards, input: os.path.abspath(input.adapter),
        r1_abs = lambda wildcards, input: os.path.abspath(f"output/{wildcards.config_id}/Undetermined_S0_L00{wildcards.config_id.split('_')[0].replace('lane', '')}_R1_001.fastq.gz")
    shell:
        """
        (
        mkdir -p {params.outdir}
        
        echo "Starting Flexbar processing for {wildcards.config_id}"
        
        # 1. Run Flexbar on R1
        # Note: Assuming flexbar is installed and available in path
        # Using generic flexbar command structure based on description
        
        flexbar -r {params.r1_abs} -b {params.barcodes_abs} -a {params.adapter_abs} \
            --target {params.outdir}/flexbarOut -n {threads} --zip-output GZ
            
        # 2. Process R2 based on R1 results using seqtk
        # Iterate over generated R1 files
        for r1_out in {params.outdir}/flexbarOut_barcode_*.fastq.gz; do
            [ -e "$r1_out" ] || continue
            
            base_name=$(basename "$r1_out" .fastq.gz)
            # Example base_name: flexbarOut_barcode_L-0-1
            
            echo "Processing R2 for $base_name..."
            
            # Extract headers from R1
            # Logic: zcat | grep " 1:N" | remove @ | take ID
            zcat "$r1_out" | grep " 1:N" | sed 's/^@//' | cut -d ' ' -f1 > "{params.outdir}/${{base_name}}_headers.txt"
            
            # Subseq R2
            # Logic: seqtk subseq R2 headers | gzip > R2_out
            if [ -s "{params.outdir}/${{base_name}}_headers.txt" ]; then
                seqtk subseq {params.r2} "{params.outdir}/${{base_name}}_headers.txt" | gzip > "{params.outdir}/${{base_name}}_R2.fastq.gz"
            else
                echo "No reads found for $base_name"
            fi
            
            rm "{params.outdir}/${{base_name}}_headers.txt"
        done
        
        # 3. Collect stats
        curr_dir=$PWD
        cd {params.outdir}
        md5sum *.fastq.gz > md5sum.txt
        du -h *.fastq.gz > size.txt
        cd $curr_dir
        ) > {log} 2>&1
        
        touch {output}
        """

rule bcl_convert:
    input:
        sample_sheet=lambda wildcards: f"src/SampleSheet_{wildcards.config_id}.csv",
        data_dir=DATA_DIR
    output:
        output_dir = directory("output/{config_id}"),
        done_file = touch("output/{config_id}/.done")
    wildcard_constraints:
        config_id = "[^/]+"
    resources:
        serial_operation=1
    threads: 1
    params:
        lane = lambda wildcards: wildcards.config_id.split('_')[0].replace('lane', ''),
        run_info_path = RUN_INFO_PATH,
        tiles = TILES
    shell:
        """
        # Masking is now handled by OverrideCycles in the sample sheet
        
        tiles_arg=""
        if [ ! -z "{params.tiles}" ]; then
            tiles_arg="--tiles {params.tiles}"
        fi
        
        dragen --bcl-conversion-only true \
        --bcl-input-directory {input.data_dir} \
        --output-directory {output.output_dir} \
        --force \
        --bcl-sampleproject-subdirectories true \
        --sample-sheet {input.sample_sheet} \
        --strict-mode false \
        --bcl-only-lane {params.lane} \
        --run-info {params.run_info_path} \
        $tiles_arg
        
        # Rename FASTQ files
        # python3 src/rename_fastqs.py {wildcards.config_id} {output.output_dir} src/renaming_map_{wildcards.config_id}.csv
        src/run_rename.sh {wildcards.config_id} {output.output_dir} src/renaming_map_{wildcards.config_id}.csv
        
        # Delete Undetermined FASTQ files to save space
        find {output.output_dir} -name "Undetermined_S0*.fastq.gz" -delete || true
        
        touch {output.done_file}
        """

rule analyze_undetermined:
    input:
        done = "output/{config_id}/.done"
    output:
        csv = "results/undetermined_indices/{config_id}.csv"
    params:
        script = "src/analyze_undetermined_indices.py",
        input_pattern = lambda wildcards: f"output/{wildcards.config_id}/Undetermined_S0_*.fastq.gz"
    shell:
        """
        python3 {params.script} "{params.input_pattern}" --output {output.csv} --limit 15000000
        """

rule project_link:
    input:
        "output/{config_id}",
        fastq_dir = directory("output/{config_id}/{project}")
    output:
        log = "logs/project_link_{config_id}_{project}.log"
    wildcard_constraints:
        config_id = "[^/]+",
        project = "[^/]+"
    shell:
        """
        # Resolve absolute path and strip the mount prefix to get Nextcloud-relative path
        ABS_PATH=$(readlink -f "{input.fastq_dir}")
        # Assuming /staging/nextcloud is the root of the Nextcloud storage
        NC_PATH=${{ABS_PATH#/staging/nextcloud/}}
        
        curl -X POST -u "kstachel:ucightf2025" \
            -H "OCS-APIRequest: true" \
            -d "path=$NC_PATH" \
            -d "shareType=3" \
            "https://precision.biochem.uci.edu/ocs/v2.php/apps/files_sharing/api/v1/shares" \
            -o {output.log}
        """

