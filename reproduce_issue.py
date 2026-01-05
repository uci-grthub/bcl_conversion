import os
import re
import pandas as pd
import xml.etree.ElementTree as ET
from io import StringIO

# Mock config
METADATA_FILE = "metadata/251219_23G5F2LT3_10B_PE151_xR077.xlsx"
RUN_INFO_PATH = "/staging/nextcloud/NovaseqX/20251219_LH00626_0085_A23G5F2LT3/RunInfo.xml"

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
                            l = int(row['Lane'])
                            g = int(row['Group'])
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
            l = int(row['Lane'])
            g = int(row['Group'])
            return masking_lookup.get((l, g), "")
        except:
            return ""
            
    df['Masking'] = df.apply(get_sample_masking, axis=1)
    
    generated_files = {}
    
    # Ensure output directory exists
    os.makedirs(out_dir, exist_ok=True)
    
    for config in lane_configs:
        lane = config['lane']
        masking = config['masking']
        masking_sanitized = config['masking_sanitized']
        
        # Filter by Lane AND Masking
        lane_df = df[(df['Lane'] == lane) & (df['Masking'] == masking)].copy()
        
        # Remove rows with empty index if there are other rows with index
        valid_indices = lane_df['index'].fillna("").astype(str).str.strip() != ""
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
            if has_index1:
                f.write("BarcodeMismatchesIndex1,1\n")
            if has_index2:
                f.write("BarcodeMismatchesIndex2,1\n")
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
            map_df['Group'] = lane_df['Group'].values
            
            # Add Position (P001, P002, etc.)
            map_df['Position'] = [f"P{i+1:03d}" for i in range(len(ss_data))]
            
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

# Setup data
LANE_CONFIGS = []
PROJECT_LOOKUP = {}
MASKING_LOOKUP = {}

if METADATA_FILE and os.path.exists(METADATA_FILE):
    try:
        df = pd.read_excel(METADATA_FILE, sheet_name="Summary", header=2)
        
        # Build Project and Masking Lookups: (Lane, Group) -> Value
        if 'Lane' in df.columns and 'Gr' in df.columns:
             for index, row in df.iterrows():
                 try:
                     l = int(row['Lane'])
                     g = int(row['Gr'])
                     
                     if 'Project Name' in df.columns:
                        p = str(row['Project Name']).strip()
                        PROJECT_LOOKUP[(l, g)] = p
                     
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
                    lane = int(row['Lane'])
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

# Run generation
generate_lane_samplesheets(METADATA_FILE, LANE_CONFIGS, PROJECT_LOOKUP, MASKING_LOOKUP, "src", RUN_INFO_PATH)
