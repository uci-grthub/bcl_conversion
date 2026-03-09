
import os
import re
import subprocess
import glob
import yaml
import pandas as pd
import xml.etree.ElementTree as ET
from io import StringIO

envvars: 
    "GMAIL_APP_PASSWORD",
    "NEXTCLOUD_URL",
    "NEXTCLOUD_USER",
    "NEXTCLOUD_PASSWORD"

NEXTCLOUD_URL = os.environ.get("NEXTCLOUD_URL")
if not NEXTCLOUD_URL:
    raise SystemExit("Error: NEXTCLOUD_URL environment variable not set")

NEXTCLOUD_USER = os.environ.get("NEXTCLOUD_USER")
if not NEXTCLOUD_USER:
    raise SystemExit("Error: NEXTCLOUD_USER environment variable not set")

NEXTCLOUD_PASSWORD = os.environ.get("NEXTCLOUD_PASSWORD")
if not NEXTCLOUD_PASSWORD:
    raise SystemExit("Error: NEXTCLOUD_PASSWORD environment variable not set")

configfile: "snakemake_config.yaml"

# Load project-specific config if it exists (higher priority than default)
# Note: library_name from base config is used ONLY to determine which project-specific config to load
# After merge, all values (including library_name, data_dir, metadata) come from the merged config
_PROJECT_CONFIG = f"snakemake_config_project.yaml"

if os.path.exists(_PROJECT_CONFIG):
    import yaml as _yaml
    with open(_PROJECT_CONFIG, 'r') as _f:
        _project_config = _yaml.safe_load(_f) or {}
    # Merge: project-specific config overrides default config
    config.update(_project_config)

# All config values read AFTER merge - project-specific config takes priority
SAMPLE_SHEET = config.get("sample_sheet", "src/SampleSheet_default.csv")
NUM_READS = config.get("num_reads", 2)
LIBRARY = config.get("library_name", "xR079")  # From merged config (project-specific if exists)
START_S = config.get("start_s", 1)
DRYRUN = config.get("dryrun", False)
DATA_DIR = config.get("data_dir", "/staging/nextcloud/NovaseqX/20260115_LH00626_0088_A233NM2LT4")  # From merged config
TILES = config.get("tiles", "1_1101")

SCRATCH_DIR = config.get("scratch_dir", "")

NEXTCLOUD_DIR_NAME = config.get("nextcloud_dir_name", "DragenExt3")
NEXTCLOUD_DIR_PATH = config.get("nextcloud_dir_path", "nextcloud3")

EMAIL_SENDER = config.get("email_sender", "kstachel@uci.edu")
EMAIL_RECIPIENT = config.get("email_recipient", "kstachel@uci.edu")
EMAIL_CC = config.get("email_cc", "kstachel@uci.edu")

# Rule: rsync project to external drive specified in config.yaml
EXTERNAL_DRIVE_PATH = config.get("external_drive_path", None)

# Skip rsync if working directory is on /mnt/ path (already on external drive)
WORKING_DIR = os.getcwd()
SKIP_RSYNC = WORKING_DIR.startswith("/mnt/")

include: "src/workflow_defs.smk"

# Sanitize Masking strings for filenames: strip appended project-like suffixes
def sanitize_masking(masking):
    if not masking:
        return masking
    s = str(masking).strip()
    # Remove common project-like suffixes (e.g., _SwarV..., SwarV_..., or trailing PROJECT_Lx tokens)
    try:
        m = re.search(r'(\s|_)(SwarV[^\s_]*)', s, flags=re.IGNORECASE)
        if m:
            s = s[:m.start()].rstrip(' _-')
        m2 = re.search(r'(_|\s)[A-Z0-9]+_L\d', s)
        if m2:
            s = s[:m2.start()].rstrip(' _-')
    except Exception:
        pass
    # Normalize formatting used elsewhere in the workflow
    s = s.replace(":", "-").replace(", ", "_").replace(",", "_").replace(" ", "")
    return s

# Auto-detect lanes from data/Data/Intensities/BaseCalls
detected_lanes = []

basecalls_path = DATA_DIR + "/Data/Intensities/BaseCalls"
if os.path.exists(basecalls_path):
    detected_lanes = sorted([
        int(d[1:]) for d in os.listdir(basecalls_path) 
        if d.startswith("L") and d[1:].isdigit() and os.path.isdir(os.path.join(basecalls_path, d))
    ])

# print("detected_lanes:", detected_lanes)

# Metadata path from merged config (project-specific if exists, otherwise base config)
metadata = config.get("metadata", "metadata/SampleSheet.xlsx")
METADATA_FILE = config.get("metadata")  # From merged config
LANE_CONFIGS = []
PROJECT_LOOKUP = {}
MASKING_LOOKUP = {}
PROJECT_LINKS = {}
PROJECT_LINKS_BY_LANE = {}
ORDER_ID_LOOKUP = {}
PROJECT_ORDER_ID = {}  # keyed by (project, lane) -> order_id

if METADATA_FILE and os.path.exists(METADATA_FILE):
    try:
        # Check if this is MiSeq format (simple) or NovaSeqX format (complex with Summary sheet)
        xl = pd.ExcelFile(METADATA_FILE)
        is_miseq_format = 'Barcode Entries' in xl.sheet_names and 'Summary' not in xl.sheet_names
        
        if is_miseq_format:
            # MiSeq: simple format, assume single lane
            print("Detected MiSeq metadata format")
            # No need to parse Summary sheet, will be handled in generate_miseq_samplesheets
        else:
            # NovaSeqX: complex format with Summary sheet
            df = pd.read_excel(METADATA_FILE, sheet_name="Summary", header=2)
        
            # Build Project and Masking Lookups: (Lane, Group) -> Value
            if 'Lane' in df.columns and 'Gr' in df.columns:
                 for index, row in df.iterrows():
                     try:
                         l = int(float(row['Lane']))
                         g = int(float(row['Gr']))
                         
                         if 'Project Name' in df.columns:
                            p = str(row['Project Name']).strip().replace(' ', '_')
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
                         
                         if 'Order ID' in df.columns:
                            order_id = str(row['Order ID']).strip().replace(' ', '_')
                            if order_id and order_id.lower() != 'nan':
                                # Normalize common casing issue (e.g., '1225i-13' -> '1225I-13')
                                order_id = order_id.replace('i', 'I')
                                ORDER_ID_LOOKUP[(l, g)] = order_id
                                if p and p.lower() != 'nan':
                                    PROJECT_ORDER_ID[(p, l)] = order_id
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
                        # Sanitize masking for filename and strip appended project tokens
                        masking_sanitized = sanitize_masking(masking)
                        
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

# Read Barcode List to fill in PROJECT_ORDER_ID for projects not in Summary sheet
try:
    if METADATA_FILE and os.path.exists(METADATA_FILE):
        xl = pd.ExcelFile(METADATA_FILE)
        if 'Barcode List' in xl.sheet_names:
            df_barcode = pd.read_excel(METADATA_FILE, sheet_name='Barcode List', header=1)
            for idx, row in df_barcode.iterrows():
                try:
                    project = str(row.get('Project name', '')).strip().replace(' ', '_')
                    order_id = str(row.get('Order ID', '')).strip().replace(' ', '_')
                    lane_val = row.get('Lane', None)
                    if project and project.lower() != 'nan' and order_id and order_id.lower() != 'nan':
                        # Normalize casing (e.g., '1225i-13' -> '1225I-13')
                        order_id = order_id.replace('i', 'I')
                        # Only add if not already in PROJECT_ORDER_ID (Summary takes precedence)
                        try:
                            lane_int = int(float(lane_val))
                        except (ValueError, TypeError):
                            lane_int = 0
                        if (project, lane_int) not in PROJECT_ORDER_ID:
                            PROJECT_ORDER_ID[(project, lane_int)] = order_id
                except:
                    pass
except Exception as e:
    print(f"Note: Could not read Barcode List for order IDs: {e}")

# Build reverse lookup: order_id -> sorted list of unique lanes
ORDER_ID_TO_LANE = {}
for (_lane, _group), _oid in ORDER_ID_LOOKUP.items():
    if _oid not in ORDER_ID_TO_LANE:
        ORDER_ID_TO_LANE[_oid] = []
    if _lane not in ORDER_ID_TO_LANE[_oid]:
        ORDER_ID_TO_LANE[_oid].append(_lane)

# print("LANE_CONFIGS:", LANE_CONFIGS)
# print("PROJECT_LOOKUP:", PROJECT_LOOKUP)
# print("MASKING_LOOKUP:", MASKING_LOOKUP)
# print("PROJECT_LINKS_BY_LANE:", PROJECT_LINKS_BY_LANE)
# print("ORDER_ID_LOOKUP:", ORDER_ID_LOOKUP)
# print("PROJECT_ORDER_ID:", PROJECT_ORDER_ID)

# Helper definitions are sourced from src/workflow_defs.smk


# Function: Copy RunInfo.xml from data_dir to src/RunInfo_nn.xml and set IsReverseComplement="N" for Read Number="3"
def fix_runinfo_reverse_complement():
    import re, os
    src = os.path.join(DATA_DIR, "RunInfo.xml")
    dest = "src/RunInfo_nn.xml"
    if not os.path.exists(src):
        raise FileNotFoundError(f"Source RunInfo.xml not found: {src}")
    with open(src, "r") as f:
        content = f.read()
    pattern = r'(<Read[^>]*Number="3"[^>]*IsReverseComplement=")[YN]"'
    replacement = r'\1N"'
    new_content = re.sub(pattern, replacement, content)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "w") as f:
        f.write(new_content)
    # Optionally, log to a file
    with open("logs/fix_runinfo_reverse_complement.log", "w") as lf:
        lf.write("RunInfo.xml copied and IsReverseComplement set to N for Read Number=3\n")

# Only fix RunInfo_nn.xml if source is newer than the existing copy
_src_runinfo = os.path.join(DATA_DIR, "RunInfo.xml")
_dest_runinfo = "src/RunInfo_nn.xml"
if not os.path.exists(_dest_runinfo) or (os.path.exists(_src_runinfo) and os.path.getmtime(_src_runinfo) > os.path.getmtime(_dest_runinfo)):
    fix_runinfo_reverse_complement()

# Generate sample sheets during parse time (needed for function calls below)
# Rule generate_samplesheets will also ensure they're created as explicit dependencies
SAMPLE_SHEETS_DICT = generate_lane_samplesheets(METADATA_FILE, LANE_CONFIGS, PROJECT_LOOKUP, MASKING_LOOKUP, "results", "src/RunInfo_nn.xml", LIBRARY)

# print(SAMPLE_SHEETS_DICT)

CONFIG_IDS = list(SAMPLE_SHEETS_DICT.keys()) if SAMPLE_SHEETS_DICT else []
# Fallback if no metadata
if not CONFIG_IDS and detected_lanes:
    CONFIG_IDS = [f"lane{l}_default" for l in detected_lanes]

FASTP_THREADS = config.get("fastp_threads", 4)

PROJECTS = get_all_projects(SAMPLE_SHEETS_DICT)

ORDER_ID_CONFIGS = get_order_id_configs(SAMPLE_SHEETS_DICT)

# If no order_id found in metadata, use a single default order_id
if not ORDER_ID_CONFIGS or all(not v for v in ORDER_ID_CONFIGS.values()):
    ORDER_ID_CONFIGS = {"default": PROJECTS}

# Ensure all order_ids from PROJECT_ORDER_ID are included in ORDER_ID_CONFIGS
# even if they don't have samples yet (they might be added later or have been filtered)
if PROJECT_ORDER_ID:
    all_order_ids = set(PROJECT_ORDER_ID.values())
    for oid in all_order_ids:
        if oid and oid not in ORDER_ID_CONFIGS:
            # Add empty list for order_ids not yet in configs
            ORDER_ID_CONFIGS[oid] = []

ORDER_ID_REPORTS = [f"Reports/order_{oid}/index.html" for oid in ORDER_ID_CONFIGS.keys()]
ORDER_ID_MD5S = [f"Reports/order_{oid}/md5sums.txt" for oid in ORDER_ID_CONFIGS.keys()]

PROJECT_LANES = get_project_lane_pairs(SAMPLE_SHEETS_DICT)
PROJECT_LANE_REPORTS = [f"Reports/{p}/lane{l}/index.html" for p, l in PROJECT_LANES]
PROJECT_LANE_MD5S = [f"Reports/{p}/lane{l}/md5sums.txt" for p, l in PROJECT_LANES]

FLEXBAR_CONFIGS = []
for config in LANE_CONFIGS:
    barcode_path = os.path.join("metadata", f"flexbar_barcodes_{config['id']}.fasta")
    if os.path.exists(barcode_path):
        FLEXBAR_CONFIGS.append(config['id'])

CONFIG_PROJECT_PAIRS = get_config_project_pairs(SAMPLE_SHEETS_DICT)
PROJECT_LINK_LOGS = [f"logs/project_link_{config_id}---{project}.log" for config_id, project in CONFIG_PROJECT_PAIRS]

# print("CONFIG_PROJECT_PAIRS:", CONFIG_PROJECT_PAIRS)

rule all:
    input:
        expand("results/fastp_plots_{config_id}.done", config_id=CONFIG_IDS),
        expand("output/{config_id}/.done", config_id=CONFIG_IDS),
        expand("output/{config_id}/{project}/md5sums.txt", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        ORDER_ID_REPORTS,
        ORDER_ID_MD5S,
        # expand("results/flexbar_{config_id}.done", config_id=FLEXBAR_CONFIGS),
        expand("results/fastp_plots_summary_lane{lane}.done", lane=detected_lanes),
        expand("results/undetermined_indices/{config_id}.csv", config_id=CONFIG_IDS),
        expand("results/read_counts_{project}.csv", project=PROJECTS),
        # expand("logs/project_link_{config_id}_{project}.log", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        expand("logs/project_links_{config_id}---{project}.yaml", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        f"results/{LIBRARY}-count.csv",
        f"Reports/{LIBRARY}_read_counts_email.done",
        expand("Reports/order_{order_id}/email_sent.done", order_id=ORDER_ID_CONFIGS.keys()),
        expand("logs/verify_project_link_{config_id}---{project}.txt", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        # "logs/rsync_to_external_drive.done",
        # "results/check_index_rc_swap.txt"
    benchmark:
        "benchmarks/all.bench"

rule bcl_convert_only:
    input:
        expand("output/{config_id}/.done", config_id=CONFIG_IDS)
    benchmark:
        "benchmarks/bcl_convert_only.bench"

rule report_order_id:
    input:
        fastp_plots = lambda wildcards: get_order_id_plot_targets(wildcards.order_id),
        md5_files = lambda wildcards: [
            f"output/{c}/{p}/md5sums.txt" for c, p in CONFIG_PROJECT_PAIRS
            if p in ORDER_ID_CONFIGS.get(wildcards.order_id, [])
            and (
                not ORDER_ID_TO_LANE.get(wildcards.order_id)
                or (re.match(r'lane(\d+)', c) and int(re.match(r'lane(\d+)', c).group(1)) in ORDER_ID_TO_LANE.get(wildcards.order_id, []))
            )
        ],
        links_yamls = lambda wildcards: [
            f"logs/project_links_{c}---{p}.yaml"
            for c, p in CONFIG_PROJECT_PAIRS
            if p in ORDER_ID_CONFIGS.get(wildcards.order_id, [])
            and (
                not ORDER_ID_TO_LANE.get(wildcards.order_id)
                or (re.match(r'lane(\d+)', c) and int(re.match(r'lane(\d+)', c).group(1)) in ORDER_ID_TO_LANE.get(wildcards.order_id, []))
            )
        ]
    output:
        html = "Reports/order_{order_id}/index.html",
        md5 = "Reports/order_{order_id}/md5sums.txt",
        pdf = "Reports/order_{order_id}/Download_Instructions.pdf"
    log:
        "logs/report_order_{order_id}.log"
    benchmark:
        "benchmarks/report_order_id_{order_id}.bench"
    params:
        order_id = "{order_id}",
        output_base = "output",
        fastp_plots_base = "results/fastp_plots",
        fastp_base = "results/fastp",
        report_dir = "Reports/order_{order_id}"
    run:
        import subprocess
        import sys
        import os
        sys.path.insert(0, workflow.basedir)
        
        import yaml as _yaml

        order_id = params.order_id
        report_dir = params.report_dir
        log_file = log[0]

        # Determine lane filter: if this order_id maps to a single lane, filter by it
        _lanes_for_order = ORDER_ID_TO_LANE.get(order_id, [])
        lane_arg = ",".join(str(l) for l in _lanes_for_order) if _lanes_for_order else "None"

        os.makedirs(report_dir, exist_ok=True)

        # Merge individual per-project yaml files into a single dict
        merged_links = {}
        for yaml_path in input.links_yamls:
            if os.path.exists(yaml_path):
                with open(yaml_path) as _yf:
                    _data = _yaml.safe_load(_yf) or {}
                for _proj, _proj_data in _data.items():
                    for _cfg, _cfg_data in _proj_data.items():
                        # Only include configs that have an entry for this order_id
                        if isinstance(_cfg_data, dict) and order_id not in _cfg_data:
                            continue
                        if _proj not in merged_links:
                            merged_links[_proj] = {}
                        merged_links[_proj][_cfg] = _cfg_data
        merged_yaml_path = os.path.join(report_dir, "_merged_links.yaml")
        with open(merged_yaml_path, 'w') as _yf:
            _yaml.dump(merged_links, _yf, default_flow_style=False)

        # Derive projects from merged input yamls (robust to subprocess re-evaluation
        # of ORDER_ID_CONFIGS without the original --configfile)
        projects = sorted(merged_links.keys())

        # Open log file
        with open(log_file, 'w') as lf:
            lf.write(f"Generating report for order_id: {order_id}\n")
            lf.write(f"Projects: {projects}\n\n")

        # Generate report for each project in this order_id
        for project in projects:
            # Get fastq links for this project in this order_id
            fastq_links = get_project_links_from_yaml(merged_yaml_path, project, lane=None, order_id=order_id)

            # Call generate_report.py for this project
            cmd = [
                "python3", "src/generate_report.py",
                project,
                params.output_base,
                params.fastp_plots_base,
                params.fastp_base,
                report_dir,
                fastq_links,
                lane_arg,  # lane_filter
                merged_yaml_path,
                order_id,
                LIBRARY,  # library_name
                str(config.get('plots_total_width', 900)),
                str(config.get('plots_quality', 35))
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            with open(log_file, 'a') as f:
                f.write(f"\n=== Report generation for project {project} ===\n")
                f.write(result.stdout)
                if result.stderr:
                    f.write(f"STDERR: {result.stderr}\n")
        
        # Consolidate md5 sums from all projects in this order_id
        all_md5s = []
        for md5_file in input.md5_files:
            try:
                with open(md5_file, 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line:
                            all_md5s.append(line)
            except Exception as e:
                with open(log_file, 'a') as f:
                    f.write(f"Warning: Could not read {md5_file}: {e}\n")
        
        # Sort consolidated md5s by filename
        all_md5s.sort(key=lambda x: x.split()[1] if len(x.split()) > 1 else x)
        
        # Write consolidated md5sums.txt
        md5_file = os.path.join(report_dir, "md5sums.txt")
        with open(md5_file, 'w') as f:
            for line in all_md5s:
                f.write(line + '\n')
        
        with open(log_file, 'a') as f:
            f.write(f"\nConsolidated {len(all_md5s)} md5 entries into {md5_file}\n")

rule send_order_email:
    input:
        html = "Reports/order_{order_id}/index.html",
        md5 = "Reports/order_{order_id}/md5sums.txt",
        pdf = "Reports/order_{order_id}/Download_Instructions.pdf"
    output:
        touch("Reports/order_{order_id}/email_sent.done")
    log:
        "logs/send_order_email_{order_id}.log"
    benchmark:
        "benchmarks/send_order_email_{order_id}.bench"
    params:
        script = "src/send_email.py",
        sender = EMAIL_SENDER,
        receiver = EMAIL_RECIPIENT,
        cc_email = EMAIL_CC,
        subject = lambda wildcards: f"Sequencing Report for Order {wildcards.order_id}"
    shell:
        "python3 src/send_email_retry.py {params.script} {params.sender} {params.receiver} \"{params.subject}\" {input.html} \"{input.md5};{input.pdf}\" {params.cc_email} {wildcards.order_id} > {log} 2>&1 && touch {output}"

rule fastp_sample:
    input:
        done = lambda wildcards: f"output/{wildcards.config_id}/{wildcards.sample_path.split('/')[0]}/.project_done"
    output:
        json = "results/fastp/{config_id}/{sample_path}.json",
        html = "results/fastp/{config_id}/{sample_path}.html"
    log:
        "logs/fastp_sample/{config_id}/{sample_path}.log"
    benchmark:
        "benchmarks/fastp_sample_{config_id}_{sample_path}.bench"
    wildcard_constraints:
        config_id = "[^/]+",
        sample_path = ".*"
    params:
        threads = FASTP_THREADS,
        fastqs = get_fastp_sample_input,
    threads: 4
    shell:
        """
        (
        mkdir -p $(dirname {output.json})

        files=({params.fastqs})
        r1="${{files[0]}}"

        if [ ${{#files[@]}} -gt 1 ]; then
            r2="${{files[1]}}"
            fastp -i "$r1" -I "$r2" --json "{output.json}" --html "{output.html}" -w {threads}
        else
            fastp -i "$r1" --json "{output.json}" --html "{output.html}" -w {threads}
        fi
        ) > {log} 2>&1
        """

rule fastp_per_config:
    input:
        get_fastp_targets
    output:
        touch("results/fastp_{config_id}.done")
    log:
        "logs/fastp_per_config_{config_id}.log"
    benchmark:
        "benchmarks/fastp_per_config_{config_id}.bench"
    wildcard_constraints:
        config_id = "lane.*"

rule fastp_plots_sample:
    input:
        json = "results/fastp/{config_id}/{sample_path}.json"
    output:
        mean = "results/fastp_plots/{config_id}/{sample_path}-mean_phred.png",
        base = "results/fastp_plots/{config_id}/{sample_path}-base_comp.png"
    log:
        "logs/fastp_plots_sample/{config_id}/{sample_path}.log"
    benchmark:
        "benchmarks/fastp_plots_sample_{config_id}_{sample_path}.bench"
    wildcard_constraints:
        config_id = "[^/]+",
        sample_path = ".*"
    params:
        mean_script = "src/mean_phred_plot_fastp.py",
        base_script = "src/base_composition_plot_fastp.py",
        sample_name = lambda wildcards: wildcards.sample_path
    threads: 1
    shell:
        """
        mkdir -p $(dirname {output.mean})
        (
        python3 {params.mean_script} "{input.json}" --out "{output.mean}" --title "{params.sample_name}" || true
        python3 {params.base_script} "{input.json}" --out "{output.base}" --title "{params.sample_name}" || true
        ) > {log} 2>&1
        """

rule fastp_plots_per_config:
    input:
        get_fastp_plots_targets
    output:
        touch("results/fastp_plots_{config_id}.done")
    log:
        "logs/fastp_plots_per_config_{config_id}.log"
    benchmark:
        "benchmarks/fastp_plots_per_config_{config_id}.bench"
    wildcard_constraints:
        config_id = "lane.*"

rule summarize_project_reads:
    input:
        get_project_fastp_targets
    output:
        "results/read_counts_{project}.csv"
    log:
        "logs/summarize_project_reads_{project}.log"
    benchmark:
        "benchmarks/summarize_project_reads_{project}.bench"
    run:
        import sys
        sys.stderr = sys.stdout = open(log[0], 'w')
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
        maps = expand("results/renaming_map_{config_id}.csv", config_id=CONFIG_IDS)
    output:
        csv = f"results/{LIBRARY}-count.csv"
    log:
        "logs/compile_read_counts.log"
    benchmark:
        "benchmarks/compile_read_counts.bench"
    run:
        import sys
        sys.stderr = sys.stdout = open(log[0], 'w')
        import csv
        import json
        import os
        import pandas as pd

        lane_group_counts = {}

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

                # Build both possible fastp JSON paths:
                # 1) Default renamed stem path
                stem = f"{run_name}-L{lane}-G{group}-{position}-{barcode}"
                sample_path_default = f"{project}/{stem}" if project and project.lower() != "nan" else stem
                json_path_default = os.path.join("results/fastp", config_id, f"{sample_path_default}.json")

                # 2) Illumina naming path for 10x/Parse/BD projects
                sample_path_illumina = f"{project}/{sample_name}" if project and project.lower() != "nan" else sample_name
                json_path_illumina = os.path.join("results/fastp", config_id, f"{sample_path_illumina}.json")

                # Prefer default path if it exists; otherwise fall back to Illumina naming
                if os.path.exists(json_path_default):
                    json_path = json_path_default
                elif os.path.exists(json_path_illumina):
                    json_path = json_path_illumina
                else:
                    print(f"Missing fastp json for default '{sample_path_default}' and illumina '{sample_path_illumina}'")
                    continue


                try:
                    with open(json_path, "r") as jf:
                        stats = json.load(jf)
                    # fastp reports total_reads as the number of reads, not pairs
                    # For paired-end data, number of pairs = total_reads // 2
                    reads = int(stats.get("summary", {}).get("before_filtering", {}).get("total_reads", 0))
                    read_pairs = reads // 2
                except Exception as e:
                    print(f"Error reading {json_path}: {e}")
                    read_pairs = 0

                lane_group_key = (lane, group)
                lane_group_counts.setdefault(lane_group_key, {})

                # Preserve metadata order grouped by Group then row index
                try:
                    group_order = int(float(row.get("Group", "")))
                except Exception:
                    group_order = float("inf")

                # Determine display label: use Illumina sample name for 10x/Parse/BD; otherwise use stem (includes barcode)
                try:
                    is_special = is_parse_or_10x(project)
                except Exception:
                    is_special = False
                label = sample_name if is_special else stem

                if label not in lane_group_counts[lane_group_key]:
                    lane_group_counts[lane_group_key][label] = [group_order, idx, group, 0]
                # Keep earliest group/index seen; always accumulate read pairs
                existing = lane_group_counts[lane_group_key][label]
                existing[0] = min(existing[0], group_order)
                existing[1] = min(existing[1], idx)
                # Keep the group value from the earliest entry
                if existing[0] == group_order:
                    existing[2] = group
                existing[3] += read_pairs

        lane_group_pairs_sorted = sorted(lane_group_counts.keys())

        if not lane_group_pairs_sorted:
            os.makedirs(os.path.dirname(output.csv), exist_ok=True)
            open(output.csv, "w").close()
            return

        per_lane_group = {}
        for (lane, group), samples in lane_group_counts.items():
            # sort by (group_order, row_index)
            ordered = sorted(samples.items(), key=lambda x: (x[1][0], x[1][1]))
            per_lane_group[(lane, group)] = [(name, group, total) for name, (_, _, group, total) in ordered]

        max_rows = max(len(v) for v in per_lane_group.values())

        # Include explicit column headers: lane, group, sample, counts for each lane-group pair
        header = [""]
        for (lane, group) in lane_group_pairs_sorted:
            header.extend(["lane", "group", "sample", "counts"])

        rows = []
        for i in range(max_rows):
            row = [""]  # Start with empty column to match header
            for (lane, group) in lane_group_pairs_sorted:
                entries = per_lane_group.get((lane, group), [])
                if i < len(entries):
                    name, grp, count = entries[i]
                    row.extend([str(lane), grp, name, f"{int(count):,}"])
                else:
                    row.extend(["", "", "", ""])
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
    log:
        f"logs/send_read_counts_email.log"
    benchmark:
        "benchmarks/send_read_counts_email.bench"
    params:
        script = "src/send_email.py",
        sender = EMAIL_SENDER,
        receiver = EMAIL_RECIPIENT,
        subject = f"Read counts for {LIBRARY}",
        body = lambda wildcards: f"Attached: per-lane read counts for {LIBRARY}.",
        cc_email = EMAIL_CC
    shell:
        "python3 {params.script} {params.sender} {params.receiver} \"{params.subject}\" \"{params.body}\" {input.csv} {params.cc_email} > {log} 2>&1"

rule fastp_plots_lane:
    input:
        get_fastp_plots_lane_inputs
    output:
        touch("results/fastp_plots_summary_lane{lane}.done")
    log:
        "logs/fastp_plots_lane{lane}.log"
    benchmark:
        "benchmarks/fastp_plots_lane_{lane}.bench"
    wildcard_constraints:
        lane = r"\d+"

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
    benchmark:
        "benchmarks/flexbar_per_config_{config_id}.bench"
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

rule generate_samplesheets:
    input:
        metadata = METADATA_FILE if METADATA_FILE else [],
        run_info = "src/RunInfo_nn.xml"
    output:
        expand("results/SampleSheet_{config_id}.csv", config_id=CONFIG_IDS),
        expand("logs/generate_samplesheets_{config_id}.done", config_id=CONFIG_IDS)
    log:
        "logs/generate_samplesheets.log"
    benchmark:
        "benchmarks/generate_samplesheets.bench"
    params:
        lane_configs = LANE_CONFIGS,
        project_lookup = PROJECT_LOOKUP,
        masking_lookup = MASKING_LOOKUP,
        output_dir = "results",
        library = LIBRARY
    run:
        import sys
        sys.stderr = sys.stdout = open(log[0], 'w')
        import hashlib
        
        # Get metadata timestamp if it exists
        metadata_mtime = os.path.getmtime(input.metadata) if input.metadata and os.path.exists(input.metadata) else 0
        
        def get_file_hash(filepath):
            """Calculate MD5 hash of file content."""
            if not os.path.exists(filepath):
                return None
            hasher = hashlib.md5()
            with open(filepath, 'rb') as f:
                hasher.update(f.read())
            return hasher.hexdigest()
        
        # Use configured lane configs; if empty, fall back to CONFIG_IDS (e.g., MiSeq)
        lane_configs = params.lane_configs or [{"id": cid} for cid in CONFIG_IDS]

        print(f"Checking sample sheets and updating only changed configs...")
        
        # Track which configs need regeneration
        configs_to_generate = []
        
        for config in lane_configs:
            config_id = config['id']
            samplesheet_path = f"results/SampleSheet_{config_id}.csv"
            done_marker = f"logs/generate_samplesheets_{config_id}.done"
            
            needs_generation = False
            
            # Check if sample sheet exists
            if not os.path.exists(samplesheet_path):
                print(f"Missing sample sheet: {samplesheet_path}")
                needs_generation = True
            else:
                # Check if done marker exists and is newer than sample sheet
                if not os.path.exists(done_marker):
                    print(f"Missing done marker: {done_marker}")
                    needs_generation = True
                else:
                    # Check if metadata is newer than done marker
                    done_marker_mtime = os.path.getmtime(done_marker)
                    if metadata_mtime > done_marker_mtime:
                        print(f"Metadata newer than done marker for {config_id}")
                        needs_generation = True
            
            if needs_generation:
                configs_to_generate.append(config)
        
        # If no configs need generation, just ensure all done markers exist
        if not configs_to_generate:
            print(f"All sample sheets up to date, ensuring done markers exist...")
            for config in lane_configs:
                config_id = config['id']
                done_marker = f"logs/generate_samplesheets_{config_id}.done"
                if not os.path.exists(done_marker):
                    os.makedirs(os.path.dirname(done_marker), exist_ok=True)
                    open(done_marker, 'w').close()
                    print(f"Created done marker: {done_marker}")
            sys.exit(0)
        
        # If metadata doesn't exist, create placeholders only for missing files
        if not input.metadata or not os.path.exists(input.metadata):
            print(f"No metadata file found, creating placeholder sample sheets")
            for config in configs_to_generate:
                config_id = config['id']
                samplesheet_path = f"results/SampleSheet_{config_id}.csv"
                done_marker = f"logs/generate_samplesheets_{config_id}.done"
                
                os.makedirs(os.path.dirname(samplesheet_path), exist_ok=True)
                open(samplesheet_path, 'w').close()
                
                os.makedirs(os.path.dirname(done_marker), exist_ok=True)
                open(done_marker, 'w').close()
            sys.exit(0)
        
        # Generate sample sheets and track which ones actually changed
        try:
            print(f"Generating sample sheets for {len(configs_to_generate)} configs...")
            
            # Get hashes before generation
            old_hashes = {}
            for config in configs_to_generate:
                config_id = config['id']
                samplesheet_path = f"results/SampleSheet_{config_id}.csv"
                old_hashes[config_id] = get_file_hash(samplesheet_path)
            
            # Generate all sample sheets
            generated_sheets = generate_lane_samplesheets(
                input.metadata,
                lane_configs,
                params.project_lookup,
                params.masking_lookup,
                params.output_dir,
                input.run_info,
                params.library
            )
            
            print(f"Generated sample sheets: {generated_sheets}")
            
            # Check which sample sheets actually changed and update only their done markers
            for config in lane_configs:
                config_id = config['id']
                samplesheet_path = f"results/SampleSheet_{config_id}.csv"
                done_marker = f"logs/generate_samplesheets_{config_id}.done"
                
                # Ensure sample sheet exists
                if not os.path.exists(samplesheet_path):
                    print(f"Warning: Expected sample sheet not created: {samplesheet_path}")
                    os.makedirs(os.path.dirname(samplesheet_path), exist_ok=True)
                    open(samplesheet_path, 'w').close()
                
                # Only update done marker if this config was regenerated
                if config in configs_to_generate:
                    new_hash = get_file_hash(samplesheet_path)
                    old_hash = old_hashes.get(config_id)
                    
                    if new_hash != old_hash:
                        # Content changed, update done marker
                        os.makedirs(os.path.dirname(done_marker), exist_ok=True)
                        open(done_marker, 'w').close()
                        print(f"Updated done marker for {config_id} (content changed)")
                    else:
                        # Content unchanged, only touch if done marker doesn't exist
                        if not os.path.exists(done_marker):
                            os.makedirs(os.path.dirname(done_marker), exist_ok=True)
                            open(done_marker, 'w').close()
                            print(f"Created done marker for {config_id} (content unchanged)")
                        else:
                            print(f"Skipped done marker update for {config_id} (content unchanged)")
                else:
                    # Config was not in generation list, ensure done marker exists without updating timestamp
                    if not os.path.exists(done_marker):
                        os.makedirs(os.path.dirname(done_marker), exist_ok=True)
                        open(done_marker, 'w').close()
                        print(f"Created done marker for {config_id} (not regenerated)")
                
        except Exception as e:
            print(f"Error generating sample sheets: {e}")
            import traceback
            traceback.print_exc()
            # Create placeholders for configs that were supposed to be generated
            for config in configs_to_generate:
                config_id = config['id']
                samplesheet_path = f"results/SampleSheet_{config_id}.csv"
                done_marker = f"logs/generate_samplesheets_{config_id}.done"
                
                os.makedirs(os.path.dirname(samplesheet_path), exist_ok=True)
                open(samplesheet_path, 'w').close()
                
                os.makedirs(os.path.dirname(done_marker), exist_ok=True)
                open(done_marker, 'w').close()



# Generate renaming map by copying from generate_samplesheets output
rule generate_renaming_map:
    input:
        sample_sheet = "results/SampleSheet_{config_id}.csv"
    output:
        map = "results/renaming_map_{config_id}.csv"
    log:
        "logs/generate_renaming_map_{config_id}.log"
    benchmark:
        "benchmarks/generate_renaming_map_{config_id}.bench"
    params:
        lane_configs = LANE_CONFIGS,
        project_lookup = PROJECT_LOOKUP,
        masking_lookup = MASKING_LOOKUP,
        metadata = METADATA_FILE,
        run_info = "src/RunInfo_nn.xml",
        out_dir = "results",
        library = LIBRARY
    run:
        import sys
        sys.stderr = sys.stdout = open(log[0], 'w')
        import os
        import pandas as pd
        from io import StringIO

        required_cols = {"Sample_Name", "Sample_Project", "Lane", "index", "index2", "Run", "Group", "Position"}

        def has_required_columns(path):
            if not os.path.exists(path):
                return False
            try:
                df = pd.read_csv(path)
                return required_cols.issubset(set(df.columns))
            except Exception:
                return False

        def build_map_from_samplesheet(samplesheet_path, out_path, default_run):
            if not os.path.exists(samplesheet_path):
                print(f"SampleSheet not found: {samplesheet_path}")
                return False

            with open(samplesheet_path, 'r') as f:
                lines = f.readlines()

            header_row = -1
            for i, line in enumerate(lines):
                if line.strip().startswith("[BCLConvert_Data]") or line.strip().startswith("[Data]"):
                    header_row = i + 1
                    break

            if header_row == -1 or header_row >= len(lines):
                print("Could not find [BCLConvert_Data] or [Data] section in SampleSheet.")
                return False

            data_str = "".join(lines[header_row:])
            try:
                ss_df = pd.read_csv(StringIO(data_str))
            except Exception as e:
                print(f"Error parsing SampleSheet data section: {e}")
                return False

            # Normalize columns
            if "Sample_Project" not in ss_df.columns and "Project" in ss_df.columns:
                ss_df["Sample_Project"] = ss_df["Project"]
            if "Sample_Name" not in ss_df.columns and "Sample_ID" in ss_df.columns:
                ss_df["Sample_Name"] = ss_df["Sample_ID"]

            for col in ["index", "index2", "Lane", "Sample_Project", "Sample_Name"]:
                if col not in ss_df.columns:
                    ss_df[col] = ""

            map_df = pd.DataFrame()
            map_df["Sample_Name"] = ss_df["Sample_Name"]
            map_df["Sample_Project"] = ss_df["Sample_Project"]
            map_df["Lane"] = ss_df["Lane"]
            map_df["index"] = ss_df["index"]
            map_df["index2"] = ss_df["index2"]
            map_df["Run"] = default_run
            map_df["Group"] = "Undetermined"

            positions = []
            for i in range(len(map_df)):
                positions.append(f"P{i+1:03d}")
            map_df["Position"] = positions

            map_df.to_csv(out_path, index=False)
            print(f"Generated fallback renaming map from SampleSheet: {out_path}")
            return True

        # If map already exists and looks valid, keep it
        if has_required_columns(output.map):
            print(f"Renaming map already valid: {output.map}")
            return

        # Attempt to regenerate via metadata-driven function (preferred)
        if params.metadata and os.path.exists(params.metadata):
            try:
                generate_lane_samplesheets(
                    params.metadata,
                    params.lane_configs,
                    params.project_lookup,
                    params.masking_lookup,
                    params.out_dir,
                    params.run_info,
                    params.library
                )
                if has_required_columns(output.map):
                    print(f"Regenerated renaming map using metadata: {output.map}")
                    return
            except Exception as e:
                print(f"Error regenerating renaming map from metadata: {e}")

        # Fallback: derive from SampleSheet data section
        build_map_from_samplesheet(input.sample_sheet, output.map, params.library)

rule bcl_convert:
    input:
        sample_sheet=lambda wildcards: f"results/SampleSheet_{wildcards.config_id}.csv",
        renaming_map = "results/renaming_map_{config_id}.csv",
        data_dir=DATA_DIR,
        _sheet_done=lambda wildcards: f"logs/generate_samplesheets_{wildcards.config_id}.done",
        run_info = "src/RunInfo_nn.xml"
    output:
        output_dir = directory("output/{config_id}"),
        done_file = touch("output/{config_id}/.done")
    log:
        "logs/bcl_convert_{config_id}.log"
    benchmark:
        "benchmarks/bcl_convert_{config_id}.bench"
    wildcard_constraints:
        config_id = "[^/]+"
    priority: 100
    resources:
        serial_operation=1
    threads: 1
    params:
        lane = lambda wildcards: wildcards.config_id.split('_')[0].replace('lane', ''),
        run_info_path = "src/RunInfo_nn.xml",
        tiles = TILES,
        scratch_dir = SCRATCH_DIR
    shell:
        """
        (
        # Masking is now handled by OverrideCycles in the sample sheet

        tiles_arg=""
        if [ ! -z "{params.tiles}" ]; then
            tiles_arg="--tiles {params.tiles}"
        fi

        # Use fast local scratch for DRAGEN output if configured, to avoid
        # watchdog timeouts caused by slow writes to JBOD storage.
        if [ ! -z "{params.scratch_dir}" ]; then
            dragen_out="{params.scratch_dir}/{wildcards.config_id}"
        else
            dragen_out="{output.output_dir}"
        fi

        find "$dragen_out" -name "*.fastq.gz" -delete 2>/dev/null || true
        mkdir -p "$dragen_out"

        timeout 7200 dragen --bcl-conversion-only true \
        --bcl-input-directory {input.data_dir} \
        --output-directory "$dragen_out" \
        --force \
        --bcl-sampleproject-subdirectories true \
        --sample-sheet {input.sample_sheet} \
        --strict-mode false \
        --bcl-only-lane {params.lane} \
        --run-info {params.run_info_path} \
        $tiles_arg

        # Transfer from scratch to final output dir using rsync with checksum
        # verification to catch any corruption, with up to 3 retries.
        if [ ! -z "{params.scratch_dir}" ]; then
            echo "Syncing from scratch to output with checksum verification..."
            mkdir -p "{output.output_dir}"
            sync_ok=false
            for attempt in 1 2 3; do
                if rsync -a --checksum --delete "$dragen_out/" "{output.output_dir}/"; then
                    sync_ok=true
                    break
                fi
                echo "rsync attempt $attempt failed, retrying..."
            done
            if [ "$sync_ok" != "true" ]; then
                echo "ERROR: rsync failed after 3 attempts. Scratch data preserved at $dragen_out"
                exit 1
            fi
            rm -rf "$dragen_out"
            echo "Scratch data removed after successful sync."
        fi

        # Delete Undetermined reads
        find "{output.output_dir}" -name "Undetermined*" -delete
        echo "Undetermined reads deleted"

        # Rename FASTQ files
        src/run_rename.sh {wildcards.config_id} "{output.output_dir}" {input.renaming_map}

        # If BD Rhapsody ATACseq, run additional renaming for R1/R2/R3
        if grep -q "BD Rhapsody_ATACseq\\|BD_Rhapsody_ATACseq\\|BD_ATAC" {input.sample_sheet}; then
            echo "Running BD Rhapsody ATACseq renaming for {wildcards.config_id}..."
            bash src/rename_bd_rhapsody_atac.sh "{output.output_dir}"
        fi

        touch {output.done_file}
        ) > {log} 2>&1
        """

rule bcl_project_done:
    """Per-project sentinel created after bcl_convert completes.

    Uses ancient() on the lane .done so that re-running bcl_convert for one
    project does NOT re-trigger downstream rules for projects whose
    .project_done already exists.
    """
    input:
        done = ancient("output/{config_id}/.done")
    output:
        sentinel = touch("output/{config_id}/{project}/.project_done")
    wildcard_constraints:
        config_id = "[^/]+",
        project = "[^/]+"

rule calculate_md5sums:
    input:
        done = "output/{config_id}/{project}/.project_done"
    output:
        md5 = "output/{config_id}/{project}/md5sums.txt"
    log:
        "logs/calculate_md5sums_{config_id}_{project}.log"
    benchmark:
        "benchmarks/calculate_md5sums_{config_id}_{project}.bench"
    wildcard_constraints:
        # Relaxed to accept any lane-prefixed config with additional underscore-separated tokens
        config_id = "[^/]+",
        project = ".+"
    shell:
        """
        (
        cd output/{wildcards.config_id}/{wildcards.project}
        find . -name '*.fastq.gz' -type f -print0 | xargs -0 -P 8 md5sum | sort -k2 > md5sums.txt
        echo "Generated md5sums.txt with $(wc -l < md5sums.txt) entries for {wildcards.project}"
        ) > {log} 2>&1
        """

# Rule: generate exclude-indexes file for each config_id
rule generate_exclude_indexes:
    input:
        samplesheets = lambda wildcards: [f"results/SampleSheet_{other_id}.csv" for other_id in get_config_ids_for_lane(get_lane_for_config(wildcards.config_id)) if other_id != wildcards.config_id]
    output:
        txt = "results/exclude_indexes_{config_id}.txt"
    benchmark:
        "benchmarks/generate_exclude_indexes_{config_id}.bench"
    run:
        import sys
        indexes = set()
        for sheet in input.samplesheets:
            indexes.update(get_index_sequences_from_samplesheet(sheet))
        with open(output.txt, 'w') as f:
            for idx in sorted(indexes):
                f.write(f"{idx}\n")
        import os; os.utime(output.txt)
        print(f"Wrote {len(indexes)} exclude indexes for {wildcards.config_id}")

rule analyze_undetermined:
    input:
        done = "output/{config_id}/.done"
    output:
        csv = "results/undetermined_indices/{config_id}.csv"
    log:
        "logs/analyze_undetermined_{config_id}.log"
    benchmark:
        "benchmarks/analyze_undetermined_{config_id}.bench"
    params:
        barcodes = lambda wildcards: f"output/{wildcards.config_id}/Reports/Top_Unknown_Barcodes.csv"
    run:
        import csv as csv_mod
        import os

        with open(log[0], 'w') as logf:
            rows = []
            with open(params.barcodes) as f:
                reader = csv_mod.DictReader(f)
                for r in reader:
                    idx1 = r.get('index', '').strip()
                    idx2 = r.get('index2', '').strip()
                    count = int(r.get('# Reads', '0'))
                    seq = f"{idx1}+{idx2}" if idx2 else idx1
                    index_type = "Dual" if idx2 else "Single"
                    rows.append((count, index_type, seq))

            os.makedirs(os.path.dirname(output.csv), exist_ok=True)
            with open(output.csv, 'w', newline='') as f:
                writer = csv_mod.writer(f)
                writer.writerow(['Count', 'Type', 'Index Sequence'])
                for count, itype, seq in rows:
                    writer.writerow([count, itype, seq])

            logf.write(f"Converted {len(rows)} barcodes from {params.barcodes}\n")

rule check_index_rc_swap:
    """Run the index reverse-complement/swap analysis script across generated
    SampleSheet CSVs and undetermined indices CSVs.
    """
    input:
        samples = lambda wildcards: sorted(glob.glob("results/SampleSheet_*.csv")),
        undetermined = lambda wildcards: sorted(glob.glob("results/undetermined_indices/*.csv"))
    output:
        "results/check_index_rc_swap.txt"
    log:
        "logs/check_index_rc_swap.log"
    params:
        script = "scripts/check_index_rc_swap.py"
    threads: 1
    shell:
        """
        python3 {params.script} --samples {input.samples} --undetermined {input.undetermined} > {output} 2> {log}
        """

rule project_link:
    input:
        done = "output/{config_id}/{project}/.project_done"
    output:
        log = "logs/project_link_{config_id}---{project}.log",
        yaml_file = "logs/project_links_{config_id}---{project}.yaml"
    benchmark:
        "benchmarks/project_link_{config_id}---{project}.bench"
    wildcard_constraints:
        # Relaxed to accept any lane-prefixed config with additional underscore-separated tokens
        config_id = "[^/]+",
        project = ".+"
    params:
        work_dir = os.getcwd(),
        order_id = lambda wildcards: PROJECT_ORDER_ID.get((wildcards.project, int(m.group(1))) if (m := re.match(r'lane(\d+)', wildcards.config_id)) else (wildcards.project, 0), ""),
        group = lambda wildcards: get_project_group(wildcards.project, wildcards.config_id)
    run:
        import traceback
        import subprocess
        from pathlib import Path
        import time
        import urllib.parse
        import re
        import os
        import shlex
        
        config_id = wildcards.config_id
        project = wildcards.project
        order_id = params.order_id
        group = params.group
        fastq_dir = f"output/{config_id}/{project}"
        log_file = output.log
        yaml_file = output.yaml_file

        os.makedirs(os.path.dirname(log_file), exist_ok=True)

        yaml_data = {project: {config_id: {}}}
        
        # Helper: Extract Browser URL
        def extract_share_url(xml_text):
            if not xml_text: return None
            match = re.search(r'<url>(.*?)</url>', xml_text)
            return match.group(1) if match else None

        # Helper: Extract Token (This is your WebDAV Username)
        def extract_share_token(xml_text):
            if not xml_text: return None
            match = re.search(r'<token>(.*?)</token>', xml_text)
            return match.group(1) if match else None

        def extract_share_owner(xml_text):
            if not xml_text: return None
            m = re.search(r'<uid_owner>(.*?)</uid_owner>', xml_text)
            if m:
                return m.group(1)
            # fallback: sometimes owner is in <id> or <owner>
            m2 = re.search(r'<owner>(.*?)</owner>', xml_text)
            if m2:
                return m2.group(1)
            return None

        def extract_internal_path(xml_text):
            if not xml_text: return None
            m = re.search(r'<path>(.*?)</path>', xml_text)
            if m:
                return m.group(1)
            # fallback: sometimes in <folder>
            m2 = re.search(r'<folder>(.*?)</folder>', xml_text)
            if m2:
                return m2.group(1)
            return None

        # Capture executed commands for logging
        executed_cmds = []

        def fetch_existing_share(path, log_handle):
            encoded_path = urllib.parse.quote(path, safe="/")
            cmd = [
                'curl', '-s', '-X', 'GET',
                '-u', f'{NEXTCLOUD_USER}:{NEXTCLOUD_PASSWORD}',
                '-H', 'OCS-APIRequest: true',
                f'{NEXTCLOUD_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares?path={encoded_path}&reshares=true'
            ]
            executed_cmds.append(cmd)
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            return result.stdout

        try:
            if os.path.isdir(fastq_dir):
                abs_path = os.path.abspath(fastq_dir)
                nc_path = f"/{NEXTCLOUD_DIR_NAME}/" + abs_path.split(f"/{NEXTCLOUD_DIR_PATH}/", 1)[1] if f"/{NEXTCLOUD_DIR_PATH}/" in abs_path else abs_path
                
                max_retries = 30  # Retry up to 30 times with exponential backoff
                retry_count = 0
                share_url = None
                share_token = None
                rate_limited = False
                last_error = None
                
                while retry_count < max_retries and not share_url:
                    retry_count += 1
                    wait_time = 3 * (2 ** (retry_count - 1))
                    if rate_limited: time.sleep(10)
                    
                    try:
                        cmd = [
                            'curl', '-s', '-w', '\nHTTP_CODE:%{http_code}',
                            '-X', 'POST',
                            '-u', f'{NEXTCLOUD_USER}:{NEXTCLOUD_PASSWORD}',
                            '-H', 'OCS-APIRequest: true',
                            '-d', f'path={nc_path}',
                            '-d', 'shareType=3', # 3 = Public Link
                            f'{NEXTCLOUD_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares'
                        ]
                        executed_cmds.append(cmd)
                        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                        
                        stdout_split = result.stdout.split('\n')
                        http_code = next((l.split(':')[1] for l in stdout_split if l.startswith('HTTP_CODE:')), None)
                        share_xml = '\n'.join([l for l in stdout_split if not l.startswith('HTTP_CODE:')])

                        if http_code == '429':
                            rate_limited = True
                            last_error = f"Rate limited (HTTP {http_code})"
                        elif http_code == '200' or http_code == '201':
                            # Success - extract data from response
                            share_url = extract_share_url(share_xml)
                            share_token = extract_share_token(share_xml)
                            if share_url and share_token:
                                try:
                                    owner = extract_share_owner(share_xml)
                                    internal_path = extract_internal_path(share_xml)
                                except Exception:
                                    owner = None
                                    internal_path = None
                                share_owner = owner
                                share_internal_path = internal_path
                                break
                            else:
                                last_error = f"Valid response but could not extract URL/token (HTTP {http_code})"
                        elif http_code == '400' or http_code == '403':
                            # 403 usually means "already exists" - try GET to fetch existing share
                            share_xml = fetch_existing_share(nc_path, None)
                            share_url = extract_share_url(share_xml)
                            share_token = extract_share_token(share_xml)
                            if share_url and share_token:
                                try:
                                    owner = extract_share_owner(share_xml)
                                    internal_path = extract_internal_path(share_xml)
                                except Exception:
                                    owner = None
                                    internal_path = None
                                share_owner = owner
                                share_internal_path = internal_path
                                break
                            else:
                                last_error = f"Share may exist but could not fetch via GET (HTTP {http_code})"
                        else:
                            last_error = f"HTTP {http_code}: {share_xml[:100] if share_xml else 'No response'}"

                        if retry_count < max_retries and not share_url:
                            time.sleep(wait_time)

                    except subprocess.TimeoutExpired:
                        last_error = "Request timed out (30 seconds)"
                        if retry_count < max_retries:
                            time.sleep(wait_time)
                    except Exception as e:
                        last_error = f"Exception: {str(e)}"
                        if retry_count < max_retries:
                            time.sleep(wait_time)

                # --- LOGGING WEB DAV CREDENTIALS AND EXECUTED COMMANDS ---
                with open(log_file, 'w') as f:
                    f.write(f"Project: {project}\n")
                    f.write(f"Config ID: {config_id}\n")
                    # Always write Order ID and Group (needed for report generation)
                    f.write(f"Order ID: {order_id}\n")
                    f.write(f"Group: {group}\n")
                    # Write the Nextcloud path we attempted to share (for rescan parsing)
                    try:
                        f.write(f"NC_PATH: {nc_path}\n")
                    except Exception:
                        pass
                    if share_url and share_token:
                        f.write(f"Status: SUCCESS\n")
                        f.write(f"Browser URL: {share_url}\n")
                        f.write(f"WebDAV URL: {NEXTCLOUD_URL}/public.php/dav/\n")
                        f.write(f"WebDAV Token: {share_token}\n")
                        # If available, record Nextcloud owner and internal storage path
                        try:
                            if share_owner:
                                f.write(f"NC_OWNER: {share_owner}\n")
                            if share_internal_path:
                                f.write(f"NC_INTERNAL_PATH: {share_internal_path}\n")
                        except Exception:
                            pass
                        # Populate individual project yaml
                        order_key = order_id if order_id else "default"
                        yaml_data[project][config_id][order_key] = {"link": share_url, "group": group}
                    else:
                        f.write(f"Status: FAILED\n")
                        f.write(f"Reason: {last_error}\n")
                        f.write(f"Retries: {retry_count}/{max_retries}\n")

                    # Record the actual commands executed (quoted for copy/paste)
                    if executed_cmds:
                        f.write("\nCommands executed:\n")
                        for c in executed_cmds:
                            try:
                                quoted = shlex.join(c)
                            except Exception:
                                quoted = ' '.join(shlex.quote(p) for p in c)
                            f.write(quoted + "\n")
            else:
                Path(log_file).write_text(f"Directory {fastq_dir} not found.")

        except Exception as e:
            Path(log_file).write_text(f"Error: {str(e)}\n{traceback.format_exc()}")

        Path(log_file).touch(exist_ok=True)

        # Write individual project yaml (empty dict if sharing failed)
        import yaml as _yaml
        with open(yaml_file, 'w') as yf:
            _yaml.dump(yaml_data, yf, default_flow_style=False)

rule rescan_nextcloud:
    input:
        "logs/project_link_{config_id}---{project}.log"
    output:
        touch("logs/nextcloud_scan_{config_id}---{project}.done")
    log:
        "logs/rescan_nextcloud_{config_id}_{project}.log"
    benchmark:
        "benchmarks/rescan_nextcloud_{config_id}_{project}.bench"
    wildcard_constraints:
        # Relaxed to accept any lane-prefixed config with additional underscore-separated tokens
        config_id = "[^/]+",
        project = ".+"
    params:
        nc_path = lambda wildcards: f"/{NEXTCLOUD_DIR_NAME}/{LIBRARY}/output/{wildcards.config_id}/{wildcards.project}"
    shell:
        """
        # Read NC_PATH from the project_link log (written by project_link rule) and use that for scanning.
        nc_log={input}
        nc_path=$(grep '^NC_PATH:' "$nc_log" | sed 's/^NC_PATH: //') || true
        nc_owner=$(grep '^NC_OWNER:' "$nc_log" | sed 's/^NC_OWNER: //') || true
        nc_internal=$(grep '^NC_INTERNAL_PATH:' "$nc_log" | sed 's/^NC_INTERNAL_PATH: //') || true

        # Prefer owner+internal_path if available (construct users/<owner>/files/<internal>)
        if [ -n "$nc_owner" ] && [ -n "$nc_internal" ]; then
            # strip leading slashes from internal
            internal=$(echo "$nc_internal" | sed 's@^/*@@')
            occ_path="users/$nc_owner/files/$internal"
        elif [ -n "$nc_path" ]; then
            occ_path="$nc_path"
        else
            echo "NC path information not found in $nc_log" > {log}
            exit 1
        fi

        ssh kstachel@precision.biochem.uci.edu "docker exec --user www-data nextcloud-aio-nextcloud php occ files:scan --path='$occ_path'" > {log} 2>&1
        """



rule verify_project_links:
    input:
        project_link_log = "logs/project_link_{config_id}---{project}.log",
        scan_done = "logs/nextcloud_scan_{config_id}---{project}.done"
    output:
        report = "logs/verify_project_link_{config_id}---{project}.txt"
    log:
        "logs/verify_project_link_{config_id}---{project}.log"
    benchmark:
        "benchmarks/verify_project_link_{config_id}---{project}.bench"
    wildcard_constraints:
        # Relaxed to accept any lane-prefixed config with additional underscore-separated tokens
        config_id = "[^/]+",
        project = ".+"
    run:
        import subprocess
        import re
        import os
        
        config_id = wildcards.config_id
        project = wildcards.project
        local_dir = f"output/{config_id}/{project}"
        
        # Read the project_link log to extract the share URL
        share_url = None
        with open(input.project_link_log, 'r') as f:
            content = f.read()
            match = re.search(r'Share link: (https://.*)', content)
            if match:
                share_url = match.group(1).strip()
        
        report = []
        report.append(f"Project Link Verification Report")
        report.append(f"Config ID: {config_id}")
        report.append(f"Project: {project}")
        report.append(f"Local Directory: {local_dir}")
        report.append(f"Share URL: {share_url if share_url else 'NOT FOUND'}")
        report.append("")
        
        # Get local fastq.gz files
        local_fastqs = []
        if os.path.isdir(local_dir):
            try:
                local_fastqs = sorted([f for f in os.listdir(local_dir) if f.endswith('.fastq.gz')])
            except Exception as e:
                report.append(f"ERROR reading local directory: {e}")
        else:
            report.append(f"Local directory does not exist: {local_dir}")
        
        report.append(f"Local FASTQ files ({len(local_fastqs)}):")
        for f in local_fastqs:
            report.append(f"  - {f}")
        report.append("")
        
        # Query Nextcloud share for files if URL is available
        remote_fastqs = []
        if share_url:
            try:
                # Extract the share token from the URL
                # URL format: https://precision.biochem.uci.edu/s/SHARETOKEN
                match = re.search(r'/s/([a-zA-Z0-9]+)', share_url)
                if match:
                    share_token = match.group(1)
                    
                    # Query the WebDAV API to list files in the share
                    # Using curl to query the share with basic auth
                    cmd = [
                        'curl', '-s',
                        '-u', 'kstachel:ucightf2025',
                        '-X', 'PROPFIND',
                        '-H', 'Depth: 1',
                        f'https://precision.biochem.uci.edu/remote.php/dav/files/kstachel/{NEXTCLOUD_DIR_NAME}/{LIBRARY}/output/{config_id}/{project}/'
                    ]
                    
                    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                    
                    # Parse XML response to extract filenames
                    if result.stdout:
                        # Extract hrefs from the PROPFIND response
                        hrefs = re.findall(r'<d:href>(.*?)</d:href>', result.stdout)
                        for href in hrefs:
                            # Extract just the filename from the full path
                            filename = href.split('/')[-1]
                            if filename and filename.endswith('.fastq.gz'):
                                remote_fastqs.append(filename)
                        remote_fastqs = sorted(set(remote_fastqs))
            except Exception as e:
                report.append(f"ERROR querying Nextcloud: {e}")
        
        if remote_fastqs:
            report.append(f"Remote FASTQ files ({len(remote_fastqs)}):")
            for f in remote_fastqs:
                report.append(f"  - {f}")
            report.append("")
        
        # Compare files
        local_set = set(local_fastqs)
        remote_set = set(remote_fastqs)
        
        report.append("VERIFICATION RESULTS:")
        if local_set == remote_set:
            report.append("✓ SUCCESS: Local and remote files match perfectly")
            report.append(f"  Total files: {len(local_set)}")
        else:
            report.append("✗ MISMATCH: Local and remote files differ")
            
            missing_remote = local_set - remote_set
            if missing_remote:
                report.append(f"\n  Files in local but NOT in remote ({len(missing_remote)}):")
                for f in sorted(missing_remote):
                    report.append(f"    - {f}")
            
            missing_local = remote_set - local_set
            if missing_local:
                report.append(f"\n  Files in remote but NOT in local ({len(missing_local)}):")
                for f in sorted(missing_local):
                    report.append(f"    - {f}")
            
            common = local_set & remote_set
            if common:
                report.append(f"\n  Files in both ({len(common)}):")
                for f in sorted(common):
                    report.append(f"    - {f}")
        
        # Write report
        os.makedirs(os.path.dirname(output.report), exist_ok=True)
        with open(output.report, 'w') as f:
            f.write('\n'.join(report))
        
        # Also write to log
        with open(log[0], 'w') as f:
            f.write('\n'.join(report))


# Diagnostic rule: print expected and actual .done and .log files for project_link
rule debug_project_link_files:
    benchmark:
        "benchmarks/debug_project_link_files.bench"
    run:
        import os
        print("\n=== DIAGNOSTIC: CONFIG_PROJECT_PAIRS ===")
        for config_id, project in CONFIG_PROJECT_PAIRS:
            print(f"PAIR: config_id={config_id}, project={project}")
        print("\n=== DIAGNOSTIC: Expected .done files ===")
        for config_id, project in CONFIG_PROJECT_PAIRS:
            done_path = f"output/{config_id}/.done"
            print(f"{done_path}: {'EXISTS' if os.path.exists(done_path) else 'MISSING'}")
        print("\n=== DIAGNOSTIC: Expected .log files ===")
        for config_id, project in CONFIG_PROJECT_PAIRS:
            log_path = f"logs/project_link_{config_id}_{project}.log"
            print(f"{log_path}: {'EXISTS' if os.path.exists(log_path) else 'MISSING'}")
        print("\n=== DIAGNOSTIC: All files in logs/ matching project_link_*.log ===")
        for fname in sorted(os.listdir('logs')):
                if fname.startswith('project_link_') and fname.endswith('.log'):
                    print(fname)


rule rsync_to_external_drive:
    input:
        # Ensure all reports are generated before running rsync
        reports = ORDER_ID_REPORTS,
        md5s = ORDER_ID_MD5S,
    output:
        touch("logs/rsync_to_external_drive.done")
    log:
        "logs/rsync_to_external_drive.log"
    benchmark:
        "benchmarks/rsync_to_external_drive.bench"
    params:
        dest_dir = EXTERNAL_DRIVE_PATH,
        project_name = LIBRARY,
        src_dir = lambda wildcards: os.getcwd()
    run:
        import sys
        sys.stderr = sys.stdout = open(log[0], 'w')
        if SKIP_RSYNC:
            print(f"Working directory {WORKING_DIR} is on /mnt/ path. Skipping rsync.")
            with open(output[0], 'w') as f:
                f.write('SKIPPED: Already on /mnt/ path')
            return
        if not params.dest_dir:
            print("No external_drive_path specified in config.yaml. Skipping rsync.")
            with open(output[0], 'w') as f:
                f.write('SKIPPED')
            return
        src = os.path.abspath(params.src_dir)
        dest = os.path.join(params.dest_dir, params.project_name)
        print(f"Rsyncing {src} to {dest}")
        os.makedirs(dest, exist_ok=True)
        # Use resume-friendly rsync flags so interrupted transfers can be resumed.
        # --partial preserves partially transferred files; --append-verify resumes and verifies.
        cmd = [
            "rsync", "-aW", "--delete", "--exclude='.snakemake/'", src + "/", dest + "/", "--exclude", "*Undetermined*"
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)
        with open(output[0], 'w') as f:
            f.write('DONE')