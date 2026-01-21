import os
import re
import subprocess
import yaml
import pandas as pd
import xml.etree.ElementTree as ET
from io import StringIO

envvars: "GMAIL_APP_PASSWORD"

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
    print(f"Loaded project-specific config: {_PROJECT_CONFIG}")
else:
    print(f"No project-specific config found ({_PROJECT_CONFIG}), using defaults")

# All config values read AFTER merge - project-specific config takes priority
SAMPLE_SHEET = config.get("sample_sheet", "src/SampleSheet_default.csv")
NUM_READS = config.get("num_reads", 2)
LIBRARY = config.get("library_name", "xR079")  # From merged config (project-specific if exists)
FASTQDIR = config.get("fastqdir", "output")
START_S = config.get("start_s", 1)
DRYRUN = config.get("dryrun", False)
RUN_INFO_PATH = config.get("run_info_path", "src/RunInfo.xml")
DATA_DIR = config.get("data_dir", "/staging/nextcloud/NovaseqX/20260115_LH00626_0088_A233NM2LT4")  # From merged config
TILES = config.get("tiles", "1_1101")

EMAIL_SENDER = config.get("email_sender", "kstachel@uci.edu")
EMAIL_RECIPIENT = config.get("email_recipient", "kstachel@uci.edu")
EMAIL_CC = config.get("email_cc", "kstachel@uci.edu")

include: "src/workflow_defs.smk"

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
PROJECT_ORDER_ID = {}

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
                         
                         if 'Order ID' in df.columns:
                            order_id = str(row['Order ID']).strip()
                            if order_id and order_id.lower() != 'nan':
                                # Normalize common casing issue (e.g., '1225i-13' -> '1225I-13')
                                order_id = order_id.replace('i', 'I')
                                ORDER_ID_LOOKUP[(l, g)] = order_id
                                if p and p.lower() != 'nan':
                                    PROJECT_ORDER_ID[p] = order_id
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

# print("LANE_CONFIGS:", LANE_CONFIGS)
# print("PROJECT_LOOKUP:", PROJECT_LOOKUP)
# print("MASKING_LOOKUP:", MASKING_LOOKUP)
# print("PROJECT_LINKS_BY_LANE:", PROJECT_LINKS_BY_LANE)
# print("ORDER_ID_LOOKUP:", ORDER_ID_LOOKUP)
# print("PROJECT_ORDER_ID:", PROJECT_ORDER_ID)

# Helper definitions are sourced from src/workflow_defs.smk

SAMPLE_SHEETS_DICT = generate_lane_samplesheets(METADATA_FILE, LANE_CONFIGS, PROJECT_LOOKUP, MASKING_LOOKUP, "src", RUN_INFO_PATH)

# print(SAMPLE_SHEETS_DICT)
# print(RUN_INFO_PATH)

CONFIG_IDS = [c['id'] for c in LANE_CONFIGS] if LANE_CONFIGS else []
# Fallback if no metadata
if not CONFIG_IDS and detected_lanes:
    CONFIG_IDS = [f"lane{l}_default" for l in detected_lanes]

FASTP_THREADS = config.get("fastp_threads", 4)
FASTP_OUTDIR = config.get("fastp_outdir", "results/fastp")
FASTP_PLOTS_OUTDIR = config.get("fastp_plots_outdir", "results/fastp_plots")

PROJECTS = get_all_projects(SAMPLE_SHEETS_DICT)

ORDER_ID_CONFIGS = get_order_id_configs(SAMPLE_SHEETS_DICT)

# If no order_id found in metadata, use a single default order_id
if not ORDER_ID_CONFIGS or all(not v for v in ORDER_ID_CONFIGS.values()):
    ORDER_ID_CONFIGS = {"default": PROJECTS}

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
PROJECT_LINK_LOGS = [f"logs/project_link_{config_id}_{project}.log" for config_id, project in CONFIG_PROJECT_PAIRS]

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
        expand("logs/project_link_{config_id}_{project}.log", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        "logs/project_links.yaml",
        f"results/{LIBRARY}-count.csv",
        f"Reports/{LIBRARY}_read_counts_email.done",
        expand("Reports/order_{order_id}/email_sent.done", order_id=ORDER_ID_CONFIGS.keys()),
        expand("logs/verify_project_link_{config_id}_{project}.txt", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        "logs/project_links.yaml"

rule bcl_convert_only:
    input:
        expand("output/{config_id}/.done", config_id=CONFIG_IDS)

rule report_order_id:
    input:
        fastp_plots = lambda wildcards: get_order_id_plot_targets(wildcards.order_id),
        md5_files = lambda wildcards: [f"output/{c}/{p}/md5sums.txt" for c, p in CONFIG_PROJECT_PAIRS if p in ORDER_ID_CONFIGS.get(wildcards.order_id, [])],
        links_yaml = "logs/project_links.yaml"
    output:
        html = "Reports/order_{order_id}/index.html",
        md5 = "Reports/order_{order_id}/md5sums.txt",
        pdf = "Reports/order_{order_id}/Download_Instructions.pdf"
    log:
        "logs/report_order_{order_id}.log"
    params:
        order_id = "{order_id}",
        output_base = "output",
        fastp_plots_base = FASTP_PLOTS_OUTDIR,
        fastp_base = FASTP_OUTDIR,
        report_dir = "Reports/order_{order_id}",
        projects = lambda wildcards: sorted(list(ORDER_ID_CONFIGS.get(wildcards.order_id, [])))
    run:
        import subprocess
        import sys
        import os
        sys.path.insert(0, workflow.basedir)
        
        order_id = params.order_id
        projects = params.projects
        report_dir = params.report_dir
        log_file = log[0]
        
        os.makedirs(report_dir, exist_ok=True)
        
        # Open log file
        with open(log_file, 'w') as lf:
            lf.write(f"Generating report for order_id: {order_id}\n")
            lf.write(f"Projects: {projects}\n\n")
        
        # Generate report for each project in this order_id
        for project in projects:
            # Get fastq links for this project in this order_id
            fastq_links = get_project_links_from_yaml(input.links_yaml, project, lane=None, order_id=order_id)
            
            # Call generate_report.py for this project
            cmd = [
                "python3", "src/generate_report.py",
                project,
                params.output_base,
                params.fastp_plots_base,
                params.fastp_base,
                report_dir,
                fastq_links,
                "None",  # lane_filter
                input.links_yaml,
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
    params:
        script = "src/send_email.py",
        sender = EMAIL_SENDER,
        receiver = EMAIL_RECIPIENT,
        cc_email = EMAIL_CC,
        subject = lambda wildcards: f"Sequencing Report for Order {wildcards.order_id}"
    shell:
        "python3 {params.script} {params.sender} {params.receiver} \"{params.subject}\" {input.html} \"{input.md5};{input.pdf}\" {params.cc_email} > {log} 2>&1 && touch {output}"

rule fastp_sample:
    input:
        done = "output/{config_id}/.done"
    output:
        json = "results/fastp/{config_id}/{sample_path}.json",
        html = "results/fastp/{config_id}/{sample_path}.html"
    log:
        "logs/fastp_sample/{config_id}/{sample_path}.log"
    wildcard_constraints:
        config_id = "[^/]+",
        sample_path = ".*"
    params:
        threads = FASTP_THREADS,
        fastqs = get_fastp_sample_input
    threads: 4
    shell:
        """
        (
        mkdir -p $(dirname {output.json})
        
        files=({params.fastqs})
        r1="${{files[0]}}"
        
        if [ ${{#files[@]}} -gt 1 ]; then
            r2="${{files[1]}}"
            fastp -i "$r1" -I "$r2" --json "{output.json}" --html "{output.html}" -w {params.threads}
        else
            fastp -i "$r1" --json "{output.json}" --html "{output.html}" -w {params.threads}
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
    wildcard_constraints:
        config_id = "lane.*"

rule summarize_project_reads:
    input:
        get_project_fastp_targets
    output:
        "results/read_counts_{project}.csv"
    log:
        "logs/summarize_project_reads_{project}.log"
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
        maps = expand("src/renaming_map_{config_id}.csv", config_id=CONFIG_IDS)
    output:
        csv = f"results/{LIBRARY}-count.csv"
    log:
        "logs/compile_read_counts.log"
    run:
        import sys
        sys.stderr = sys.stdout = open(log[0], 'w')
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

                lane_counts.setdefault(lane, {})

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

                if label not in lane_counts[lane]:
                    lane_counts[lane][label] = [group_order, idx, group, 0]
                # Keep earliest group/index seen; always accumulate read pairs
                existing = lane_counts[lane][label]
                existing[0] = min(existing[0], group_order)
                existing[1] = min(existing[1], idx)
                # Keep the group value from the earliest entry
                if existing[0] == group_order:
                    existing[2] = group
                existing[3] += read_pairs

        lanes_sorted = sorted(lane_counts.keys())

        if not lanes_sorted:
            os.makedirs(os.path.dirname(output.csv), exist_ok=True)
            open(output.csv, "w").close()
            return

        per_lane = {}
        for lane, samples in lane_counts.items():
            # sort by (group_order, row_index)
            ordered = sorted(samples.items(), key=lambda x: (x[1][0], x[1][1]))
            per_lane[lane] = [(name, group, total) for name, (_, _, group, total) in ordered]

        max_rows = max(len(v) for v in per_lane.values())

        # Include explicit column headers: lane, group, sample, counts for each lane
        header = [""]
        for lane in lanes_sorted:
            header.extend(["lane", "group", "sample", "counts"])

        rows = []
        for i in range(max_rows):
            row = [""]  # Start with empty column to match header
            for lane in lanes_sorted:
                entries = per_lane.get(lane, [])
                if i < len(entries):
                    name, group, count = entries[i]
                    row.extend([str(lane), group, name, f"{int(count):,}"])
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
        output_dir = protected(directory("output/{config_id}")),
        done_file = touch("output/{config_id}/.done")
    log:
        "logs/bcl_convert_{config_id}.log"
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
        (
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
        
        # Delete Undetermined FASTQ files to save space - DISABLED as they are needed for analysis
        # find {output.output_dir} -name "Undetermined_S0*.fastq.gz" -delete || true
        
        touch {output.done_file}
        ) > {log} 2>&1
        """

rule calculate_md5sums:
    input:
        done = "output/{config_id}/.done"
    output:
        md5 = "output/{config_id}/{project}/md5sums.txt"
    log:
        "logs/calculate_md5sums_{config_id}_{project}.log"
    wildcard_constraints:
        config_id = "[^/]+",
        project = ".+"
    shell:
        """
        (
        cd output/{wildcards.config_id}/{wildcards.project}
        find . -name '*.fastq.gz' -type f -exec md5sum {{}} \\; | sort -k2 > md5sums.txt
        echo "Generated md5sums.txt with $(wc -l < md5sums.txt) entries for {wildcards.project}"
        ) > {log} 2>&1
        """

rule analyze_undetermined:
    input:
        done = "output/{config_id}/.done"
    output:
        csv = "results/undetermined_indices/{config_id}.csv"
    log:
        "logs/analyze_undetermined_{config_id}.log"
    params:
        script = "src/analyze_undetermined_indices.py",
        input_pattern = lambda wildcards: f"output/{wildcards.config_id}/Undetermined_S0_*.fastq.gz"
    shell:
        """
        python3 {params.script} "{params.input_pattern}" --output {output.csv} --limit 15000000 > {log} 2>&1
        """

rule consolidate_project_links:
    input:
        PROJECT_LINK_LOGS,
        expand("logs/nextcloud_scan_{config_id}_{project}.done", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS])
    output:
        "logs/project_links.yaml"
    log:
        "logs/consolidate_project_links.log"
    run:
        import sys
        import glob
        sys.stderr = sys.stdout = open(log[0], 'w')
        
        links = {}
        
        # Dynamically discover all project_link logs
        log_files = glob.glob("logs/project_link_*.log")
        print(f"Found {len(log_files)} project link log files")
        
        for log_file in log_files:
            try:
                with open(log_file, 'r') as f:
                    content = f.read()
                
                # Extract project and config_id from filename
                # Format: logs/project_link_{config_id}_{project}.log
                basename = os.path.basename(log_file)
                # Remove prefix and suffix
                filename_no_prefix = basename.replace("project_link_", "").replace(".log", "")
                
                # Match against known CONFIG_IDS to extract config_id
                # config_id format: lane{N}_R{N}-{N}_I{N}-{N}_I{N}-{N}_R{N}-{N}
                config_id = None
                project = None
                
                for known_config in CONFIG_IDS:
                    if filename_no_prefix.startswith(known_config + "_"):
                        config_id = known_config
                        # Everything after config_id + "_" is the project name
                        project = filename_no_prefix[len(known_config) + 1:]
                        break
                
                if not config_id or not project:
                    print(f"Could not parse filename: {basename} (no matching config_id)")
                    continue
                
                # Extract Order ID and Group from log content
                order_id = ""
                group = ""
                lines = content.split('\n')
                for line in lines:
                    if line.startswith("Order ID:"):
                        order_id = line.split("Order ID:", 1)[1].strip()
                    elif line.startswith("Group:"):
                        group = line.split("Group:", 1)[1].strip()
                
                # If order_id not found in log or is empty, look it up from PROJECT_ORDER_ID
                if not order_id:
                    order_id = PROJECT_ORDER_ID.get(project, "")
                    if order_id:
                        print(f"Order ID for {project} not in log, using PROJECT_ORDER_ID: {order_id}")
                # Normalize casing (e.g., '1225i-13' -> '1225I-13')
                if order_id:
                    order_id = order_id.replace('i', 'I')
                
                # Try to find "Share link:" in the log content
                if "Share link:" in content:
                    for line in lines:
                        if line.startswith("Share link:"):
                            share_url = line.split("Share link:", 1)[1].strip()
                            
                            if project and config_id and share_url:
                                if project not in links:
                                    links[project] = {}
                                if config_id not in links[project]:
                                    links[project][config_id] = {}
                                
                                # Store with order_id key, or use "default" if still not found
                                order_key = order_id if order_id else "default"
                                # Store as dict with link and group
                                links[project][config_id][order_key] = {
                                    'link': share_url,
                                    'group': group
                                }
                                print(f"Found link for {project} / {config_id} / {order_key} (group: {group}): {share_url}")
                                break
            except Exception as e:
                print(f"Error processing {log_file}: {e}")
                continue
        
        os.makedirs(os.path.dirname(output[0]), exist_ok=True)
        with open(output[0], 'w') as yf:
            yaml.dump(links, yf, default_flow_style=False)
        
        print(f"Consolidated {len(links)} projects into {output[0]}")

rule project_link:
    input:
        done = "output/{config_id}/.done"
    output:
        log = "logs/project_link_{config_id}_{project}.log"
    wildcard_constraints:
        config_id = r"lane\d+_(R\d+-\d+(_[IR]\d+-\d+)*_R\d+-\d+|default)",
        project = ".+"
    params:
        work_dir = os.getcwd(),
        order_id = lambda wildcards: PROJECT_ORDER_ID.get(wildcards.project, ""),
        group = lambda wildcards: get_project_group(wildcards.project, wildcards.config_id)
    run:
        import traceback
        from pathlib import Path
        import time
        import urllib.parse
        import re
        
        config_id = wildcards.config_id
        project = wildcards.project
        order_id = params.order_id
        group = params.group
        fastq_dir = f"output/{config_id}/{project}"
        log_file = output.log
        work_dir = params.work_dir
        
        # Ensure logs directory exists
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        
        # Create log file
        with open(log_file, 'w') as f:
            f.write(f"Checking for directory: {fastq_dir}\n")
            f.write(f"Working directory: {os.getcwd()}\n")
            f.write(f"Config ID: {config_id}\n")
            f.write(f"Project: {project}\n")
            f.write(f"Order ID: {order_id}\n")
            f.write(f"Group: {group}\n")
        
        def extract_share_url(xml_text):
            if not xml_text:
                return None
            match = re.search(r'<url>(.*?)</url>', xml_text)
            return match.group(1) if match else None
        
        def check_http_status(stderr_text):
            """Extract HTTP status code from curl verbose output in stderr."""
            if not stderr_text:
                return None
            # Look for "< HTTP/2 XXX" or "< HTTP/1.1 XXX"
            match = re.search(r'<\s*HTTP/[0-9.]+\s+(\d+)', stderr_text)
            return int(match.group(1)) if match else None

        def fetch_existing_share(path, log_handle):
            """Try to fetch an existing share link for the given path."""
            encoded_path = urllib.parse.quote(path, safe="/")
            result = subprocess.run([
                'curl', '-s', '-w', '\nHTTP_CODE:%{http_code}',
                '-X', 'GET',
                '-u', 'kstachel:ucightf2025',
                '-H', 'OCS-APIRequest: true',
                f'https://precision.biochem.uci.edu/ocs/v2.php/apps/files_sharing/api/v1/shares?path={encoded_path}&reshares=true'
            ], capture_output=True, text=True, timeout=30)

            # Parse HTTP status from output
            http_code = None
            stdout_lines = result.stdout.split('\n')
            for line in stdout_lines:
                if line.startswith('HTTP_CODE:'):
                    http_code = line.split(':', 1)[1]
                    stdout_lines.remove(line)
                    break
            share_xml = '\n'.join(stdout_lines)

            log_handle.write("  GET existing share response:\n")
            log_handle.write(f"    Return code: {result.returncode}\n")
            log_handle.write(f"    HTTP status: {http_code}\n")
            if result.stderr:
                log_handle.write(f"    STDERR: {result.stderr}\n")
            log_handle.write(f"    STDOUT length: {len(share_xml)} bytes\n")
            if share_xml:
                log_handle.write(f"    Content:\n{share_xml}\n")
            else:
                log_handle.write("    Content: (empty response)\n")

            return extract_share_url(share_xml)

        try:
            if os.path.isdir(fastq_dir):
                abs_path = os.path.abspath(fastq_dir)
                with open(log_file, 'a') as f:
                    f.write(f"Absolute path: {abs_path}\n")
                
                # Extract Nextcloud path
                # Nextcloud API expects path like: /DragenExt/xR078_workflow/output/lane.../project/
                if "/nextcloud2/" in abs_path:
                    # Replace /mnt/extusb1/nextcloud2/ with /DragenExt/
                    nc_path = "/DragenExt/" + abs_path.split("/nextcloud2/", 1)[1]
                else:
                    nc_path = abs_path
                
                with open(log_file, 'a') as f:
                    f.write(f"Nextcloud path: {nc_path}\n")
                
                # Retry logic with exponential backoff
                # Start with longer delays to avoid rate limiting
                max_retries = 5
                retry_count = 0
                share_url = None
                rate_limited = False
                
                while retry_count < max_retries and not share_url:
                    retry_count += 1
                    # Longer delays: 3, 6, 12, 24, 48 seconds to avoid rate limiting
                    wait_time = 3 * (2 ** (retry_count - 1))
                    
                    # If we were rate limited before, add extra delay
                    if rate_limited and retry_count > 1:
                        extra_wait = 10
                        with open(log_file, 'a') as f:
                            f.write(f"Previous attempt was rate-limited, adding {extra_wait}s extra delay\n")
                        time.sleep(extra_wait)
                    
                    with open(log_file, 'a') as f:
                        if retry_count > 1:
                            f.write(f"\nRetry attempt {retry_count}/{max_retries} (waited {wait_time}s)...\n")
                        else:
                            f.write("Creating share link...\n")
                    
                    # Log the curl command being executed
                    with open(log_file, 'a') as f:
                        f.write(f"Executing curl command (attempt {retry_count}):\n")
                        f.write(f"  curl -s -w '\\nHTTP_CODE:%{{http_code}}' -X POST -u kstachel:*** -H 'OCS-APIRequest: true' -d 'path={nc_path}' -d 'shareType=3' https://precision.biochem.uci.edu/ocs/v2.php/apps/files_sharing/api/v1/shares\n")
                    
                    try:
                        result = subprocess.run([
                            'curl', '-s', '-w', '\nHTTP_CODE:%{http_code}',
                            '-X', 'POST',
                            '-u', 'kstachel:ucightf2025',
                            '-H', 'OCS-APIRequest: true',
                            '-d', f'path={nc_path}',
                            '-d', 'shareType=3',
                            'https://precision.biochem.uci.edu/ocs/v2.php/apps/files_sharing/api/v1/shares'
                        ], capture_output=True, text=True, timeout=30)
                        
                        # Parse HTTP status from output
                        http_code = None
                        stdout_lines = result.stdout.split('\n')
                        for line in stdout_lines:
                            if line.startswith('HTTP_CODE:'):
                                http_code = line.split(':', 1)[1]
                                stdout_lines.remove(line)
                                break
                        share_xml = '\n'.join(stdout_lines)
                        stderr_output = result.stderr
                        returncode = result.returncode
                        
                        with open(log_file, 'a') as f:
                            f.write(f"Response (attempt {retry_count}):\n")
                            f.write(f"  Return code: {returncode}\n")
                            f.write(f"  HTTP status: {http_code}\n")
                            f.write(f"  STDOUT length: {len(share_xml)} bytes\n")
                            if stderr_output:
                                f.write(f"  STDERR: {stderr_output}\n")
                            if share_xml:
                                f.write(f"  Content:\n{share_xml}\n")
                            else:
                                f.write(f"  Content: (empty response)\n")
                        
                        # Check for rate limiting (HTTP 429)
                        if http_code == '429':
                            rate_limited = True
                            with open(log_file, 'a') as f:
                                f.write(f"⚠ Rate limited (HTTP 429) - will retry with longer delay\n")
                        elif http_code and not http_code.startswith('2'):
                            # Non-2xx status code
                            with open(log_file, 'a') as f:
                                f.write(f"⚠ HTTP error status {http_code}\n")
                        
                        # Extract URL from XML
                        if share_xml and len(share_xml.strip()) > 0:
                            share_url = extract_share_url(share_xml)
                            if share_url:
                                with open(log_file, 'a') as f:
                                    f.write(f"✓ Successfully created share link on attempt {retry_count}: {share_url}\n")
                                    f.write(f"Share link: {share_url}\n")
                            else:
                                # Check if response indicates an error
                                if '<statuscode>404</statuscode>' in share_xml:
                                    with open(log_file, 'a') as f:
                                        f.write(f"✗ Path not found (404) - directory may not exist in Nextcloud\n")
                                elif '<statuscode>403</statuscode>' in share_xml:
                                    with open(log_file, 'a') as f:
                                        f.write(f"✗ Permission denied (403)\n")
                                else:
                                    with open(log_file, 'a') as f:
                                        f.write(f"Could not extract URL from response (attempt {retry_count})\n")
                        else:
                            with open(log_file, 'a') as f:
                                if http_code == '429':
                                    f.write(f"Empty response due to rate limiting (HTTP 429)\n")
                                else:
                                    f.write(f"Empty response received (attempt {retry_count})\n")
                            
                        # If POST did not yield a URL and we're not rate limited, try to find an existing share via GET
                        if not share_url and http_code != '429':
                            with open(log_file, 'a') as f:
                                f.write("Attempting to fetch existing share (GET)...\n")
                                share_url = fetch_existing_share(nc_path, f)
                                if share_url:
                                    f.write(f"✓ Found existing share link: {share_url}\n")
                                    f.write(f"Share link: {share_url}\n")
                                else:
                                    f.write("No existing share link found via GET\n")

                        # Wait before retrying (unless it's the last attempt and we already found a URL)
                        if not share_url and retry_count < max_retries:
                            with open(log_file, 'a') as f:
                                f.write(f"Waiting {wait_time} seconds before retry...\n")
                            time.sleep(wait_time)
                    
                    except subprocess.TimeoutExpired:
                        with open(log_file, 'a') as f:
                            f.write(f"Timeout on attempt {retry_count} (30s)\n")
                        if retry_count < max_retries:
                            with open(log_file, 'a') as f:
                                f.write(f"Waiting {wait_time} seconds before retry...\n")
                            time.sleep(wait_time)
                    except Exception as e:
                        with open(log_file, 'a') as f:
                            f.write(f"Error on attempt {retry_count}: {type(e).__name__}: {e}\n")
                        if retry_count < max_retries:
                            with open(log_file, 'a') as f:
                                f.write(f"Waiting {wait_time} seconds before retry...\n")
                            time.sleep(wait_time)
                
                if not share_url:
                    with open(log_file, 'a') as f:
                        f.write(f"\n✗ Failed to create share link after {max_retries} attempts\n")
                        if rate_limited:
                            f.write(f"   Reason: Rate limiting (HTTP 429 - Too Many Requests)\n")
                            f.write(f"   Suggestion: Wait a few minutes and retry manually, or increase delays in code\n")
                        f.write(f"NOTE: Rule will succeed but link was not created\n")
                        f.write(f"This project will be missing from project_links.yaml\n")
            else:
                with open(log_file, 'a') as f:
                    f.write(f"Directory {fastq_dir} does not exist, skipping link creation\n")
        except Exception as e:
            with open(log_file, 'a') as f:
                f.write(f"\nError during processing:\n")
                f.write(f"Exception type: {type(e).__name__}\n")
                f.write(f"Exception message: {str(e)}\n")
                f.write(f"Traceback:\n{traceback.format_exc()}\n")
                f.write(f"NOTE: Rule will succeed despite error\n")
        
        # Always ensure the log file exists to satisfy the output requirement
        # This makes the rule always succeed even if link creation fails
        Path(log_file).touch(exist_ok=True)

rule rescan_nextcloud:
    input:
        "logs/project_link_{config_id}_{project}.log"
    output:
        touch("logs/nextcloud_scan_{config_id}_{project}.done")
    log:
        "logs/rescan_nextcloud_{config_id}_{project}.log"
    wildcard_constraints:
        config_id = r"lane\d+_(R\d+-\d+(_[IR]\d+-\d+)*_R\d+-\d+|default)",
        project = ".+"
    params:
        nc_path = lambda wildcards: f"/DragenExt/{LIBRARY}_workflow/output/{wildcards.config_id}/{wildcards.project}"
    shell:
        """
        ssh kstachel@precision.biochem.uci.edu "docker exec --user www-data nextcloud-aio-nextcloud php occ files:scan --path='{params.nc_path}'" > {log} 2>&1
        """

rule verify_project_links:
    input:
        project_link_log = "logs/project_link_{config_id}_{project}.log",
        scan_done = "logs/nextcloud_scan_{config_id}_{project}.done"
    output:
        report = "logs/verify_project_link_{config_id}_{project}.txt"
    log:
        "logs/verify_project_link_{config_id}_{project}.log"
    wildcard_constraints:
        config_id = r"lane\d+_(R\d+-\d+(_[IR]\d+-\d+)*_R\d+-\d+|default)",
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
                        f'https://precision.biochem.uci.edu/remote.php/dav/files/kstachel/DragenExt/{LIBRARY}_workflow/output/{config_id}/{project}/'
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

