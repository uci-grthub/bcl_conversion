
import os
import re
import subprocess
import glob
import yaml
import pandas as pd
import xml.etree.ElementTree as ET
from io import StringIO

# NOTE: do NOT declare these as `envvars:`. Snakemake's envvars directive re-exports
# the values inline into every spawned --mode subprocess command line and echoes that
# command into .snakemake/log, leaking secrets. The values are read via os.environ
# below and inherited by child processes from the launching shell, so the directive
# is unnecessary. Ensure they are exported before invoking snakemake.
_REQUIRED_ENV = ("GMAIL_APP_PASSWORD", "NEXTCLOUD_URL", "NEXTCLOUD_USER", "NEXTCLOUD_PASSWORD")
_missing_env = [_v for _v in _REQUIRED_ENV if not os.environ.get(_v)]
if _missing_env:
    raise SystemExit(f"Error: required environment variable(s) not set: {', '.join(_missing_env)}")

NEXTCLOUD_URL = os.environ.get("NEXTCLOUD_URL")
if not NEXTCLOUD_URL:
    raise SystemExit("Error: NEXTCLOUD_URL environment variable not set")

NEXTCLOUD_USER = os.environ.get("NEXTCLOUD_USER")
if not NEXTCLOUD_USER:
    raise SystemExit("Error: NEXTCLOUD_USER environment variable not set")

NEXTCLOUD_PASSWORD = os.environ.get("NEXTCLOUD_PASSWORD")
if not NEXTCLOUD_PASSWORD:
    raise SystemExit("Error: NEXTCLOUD_PASSWORD environment variable not set")

# SSH target for `occ files:scan` on the Nextcloud host. Defaults to the same
# user/host as NEXTCLOUD_URL; override via env for a different admin account.
NEXTCLOUD_SSH_HOST = os.environ.get("NEXTCLOUD_SSH_HOST")
if NEXTCLOUD_SSH_HOST is None:
    from urllib.parse import urlparse as _urlparse
    NEXTCLOUD_SSH_HOST = f"{NEXTCLOUD_USER}@{_urlparse(NEXTCLOUD_URL).hostname}"

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

# Fail fast if required config values are missing or empty
_required = {"library_name", "metadata", "data_dir"}
_missing = [k for k in _required if not config.get(k, "")]
if _missing:
    raise SystemExit(f"Error: required config value(s) are empty or missing: {', '.join(sorted(_missing))}")

SAMPLE_SHEET = config.get("sample_sheet", "src/SampleSheet_default.csv")
NUM_READS = config.get("num_reads", 2)
LIBRARY = config.get("library_name", "xR079")  # From merged config (project-specific if exists)
START_S = config.get("start_s", 1)
DRYRUN = config.get("dryrun", False)
DATA_DIR = config.get("data_dir", "/staging/nextcloud/NovaseqX/20260115_LH00626_0088_A233NM2LT4")  # From merged config
TILES = config.get("tiles", "1_1101")
FLEXBAR_BIN = config.get("flexbar_bin", "")
USE_ANCIENT = config.get("use_ancient", True)
REPORT_UNDETERMINED_CONFIGS = config.get("report_undetermined_configs", [])
_effective_keep = list(config.get("keep_undetermined_configs", []))
for _c in REPORT_UNDETERMINED_CONFIGS:
    if _c not in _effective_keep:
        _effective_keep.append(_c)
KEEP_UNDETERMINED_CONFIGS = " ".join(_effective_keep)

def maybe_ancient(path):
    return ancient(path) if USE_ANCIENT else path

SCRATCH_DIR = config.get("scratch_dir", "")

# When true, force CreateFastqForIndexReads=1 in every generated SampleSheet so DRAGEN
# emits index reads as FASTQs (no index-based demultiplexing). Default: false.
NO_DEMUX = bool(config.get("no_demux", False))

NEXTCLOUD_DIR_NAME = config.get("nextcloud_dir_name", "DragenExt3")
NEXTCLOUD_DIR_PATH = config.get("nextcloud_dir_path", "nextcloud3")

EMAIL_SENDER = config.get("email_sender", "kstachel@uci.edu")
EMAIL_RECIPIENT = config.get("email_recipient", "kstachel@uci.edu")
EMAIL_CC = config.get("email_cc", "kstachel@uci.edu")
LOW_READS_THRESHOLD = config.get("low_reads_threshold", 1000)

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

_restrict_lanes = config.get("lanes", [])
if _restrict_lanes:
    detected_lanes = [l for l in detected_lanes if l in _restrict_lanes]

# print("detected_lanes:", detected_lanes)

# Metadata path from merged config (project-specific if exists, otherwise base config)
metadata = config.get("metadata", "metadata/SampleSheet.xlsx")
METADATA_FILE = config.get("metadata")  # From merged config
VALIDATION_XLSX = f"metadata/metadata_validation_{os.path.splitext(os.path.basename(metadata))[0]}.xlsx" if metadata else None
LANE_CONFIGS = []
PROJECT_LOOKUP = {}
MASKING_LOOKUP = {}
PROJECT_LINKS = {}
PROJECT_LINKS_BY_LANE = {}
ORDER_ID_LOOKUP = {}
LAB_ID_LOOKUP = {}   # keyed by (lane, group) -> lab_id  (group-aware, unlike PROJECT_LAB_ID)
PROJECT_ORDER_ID = {}  # keyed by (project, lane) -> order_id
PROJECT_LAB_ID = {}  # keyed by (project, lane) -> lab_id
IS_MISEQ_FORMAT = False

if METADATA_FILE and os.path.exists(METADATA_FILE):
    try:
        # Check if this is MiSeq format (simple) or NovaSeqX format (complex with Summary sheet)
        xl = pd.ExcelFile(METADATA_FILE)
        is_miseq_format = 'Barcode Entries' in xl.sheet_names and 'Summary' not in xl.sheet_names
        IS_MISEQ_FORMAT = is_miseq_format

        if is_miseq_format:
            # MiSeq: simple format, assume single lane
            print("Detected MiSeq metadata format")
            # Infer order IDs and project->order mappings from the first tab.
            # Lab ID commonly contains both project labels (e.g., PaegB) and
            # order IDs (e.g., 0326I-54) in MiSeq sheets.
            try:
                first_tab = xl.sheet_names[0]
                df_first = pd.read_excel(METADATA_FILE, sheet_name=first_tab, header=None)
                header_row = None
                lab_id_col = None
                project_col = None

                for i, row in df_first.iterrows():
                    vals = [str(v).strip() for v in row.tolist() if str(v).strip() and str(v).strip().lower() != 'nan']
                    if not vals:
                        continue
                    for j, v in enumerate(row.tolist()):
                        if str(v).strip().lower() == 'lab id':
                            header_row = i
                            lab_id_col = j
                            break
                    if lab_id_col is not None:
                        break

                if lab_id_col is not None:
                    # Detect project column in the same header row when present.
                    for j, v in enumerate(df_first.iloc[header_row].tolist()):
                        h = str(v).strip().lower()
                        if h in {
                            'project', 'project name', 'sample_project',
                            'sample project', 'sample name', 'sample_name'
                        }:
                            project_col = j
                            break

                    def _uniq_keep_order(items):
                        seen = set()
                        out = []
                        for x in items:
                            if x in seen:
                                continue
                            seen.add(x)
                            out.append(x)
                        return out

                    order_ids = []
                    project_candidates = []

                    for v in df_first.iloc[header_row + 1:, lab_id_col].tolist():
                        s = str(v).strip()
                        if not s or s.lower() == 'nan':
                            continue
                        m = re.match(r'^(?:order_)?(\d+[iI]-\d+)$', s)
                        if m:
                            order_ids.append(m.group(1).replace('i', 'I'))
                        else:
                            project_candidates.append(s.replace(' ', '_'))

                    if project_col is not None:
                        for v in df_first.iloc[header_row + 1:, project_col].tolist():
                            s = str(v).strip()
                            if not s or s.lower() == 'nan':
                                continue
                            project_candidates.append(s.replace(' ', '_'))

                    order_ids = _uniq_keep_order(order_ids)
                    project_candidates = _uniq_keep_order(project_candidates)

                    for oid in order_ids:
                        # Keep synthetic keys so report-order fallback still sees IDs.
                        PROJECT_ORDER_ID[(f"__MISEQ_ORDERID_{oid}", 0)] = oid

                    # Lane is fixed to lane1 for MiSeq in this workflow.
                    if len(order_ids) == 1:
                        oid = order_ids[0]
                        for proj in project_candidates:
                            PROJECT_ORDER_ID[(proj, 1)] = oid
                        if project_candidates:
                            ORDER_ID_LOOKUP[(1, 1)] = oid
                    elif len(order_ids) > 1 and len(order_ids) == len(project_candidates):
                        for proj, oid in zip(project_candidates, order_ids):
                            PROJECT_ORDER_ID[(proj, 1)] = oid
            except Exception as _e:
                print(f"Note: Could not infer MiSeq order IDs from Lab ID column: {_e}")
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

                         if 'Lab ID' in df.columns:
                            lab_id_val = str(row['Lab ID']).strip()
                            if lab_id_val and lab_id_val.lower() != 'nan':
                                LAB_ID_LOOKUP[(l, g)] = lab_id_val
                                if p and p.lower() != 'nan':
                                    PROJECT_LAB_ID[(p, l)] = lab_id_val
                     except:
                         pass
            
            if 'Lane' in df.columns:
                # Collect unique lanes (masking groups are merged into a single SampleSheet per lane)
                unique_lanes = sorted(df['Lane'].dropna().apply(lambda x: int(float(x))).unique())
                if _restrict_lanes:
                    unique_lanes = [l for l in unique_lanes if l in _restrict_lanes]
                for lane in unique_lanes:
                    LANE_CONFIGS.append({
                        'lane': lane,
                        'id': f"lane{lane}"
                    })
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

VALIDATE_CONFIG_ID_PATTERN = "[^/]+" if IS_MISEQ_FORMAT else r"lane\d+"

ruleorder: validate_barcode_hamming_distances_rc > validate_barcode_hamming_distances
ruleorder: flexbar_stage_project > bcl_project_done
ruleorder: flexbar_stage_project > normalize_project_fastq_names
ruleorder: fqtk_stage_project > bcl_project_done
ruleorder: fqtk_stage_project > normalize_project_fastq_names

# Build project directory rename map: (config_id, old_project) -> new_folder_name
# Format: {LabID}_{OrderID}_{library_name}_L{lane}_G{group}
PROJECT_RENAME_MAP = {}      # (config_id, old_project) -> new_folder_name
PROJECT_RENAME_MAP_INV = {}  # (config_id, new_folder_name) -> old_project
for (lane, group), project in PROJECT_LOOKUP.items():
    config_id = f"lane{lane}"
    # Use (lane, group)-keyed lookups so duplicate project names on the same lane
    # each get their own order_id/lab_id rather than sharing the last-written value.
    order_id = ORDER_ID_LOOKUP.get((lane, group), "") or PROJECT_ORDER_ID.get((project, lane), "")
    lab_id = LAB_ID_LOOKUP.get((lane, group), "") or PROJECT_LAB_ID.get((project, lane), "")
    if lab_id and order_id:
        new_name = f"{lab_id}_{order_id}_{LIBRARY}_L{lane}_G{group}"
        PROJECT_RENAME_MAP[(config_id, project)] = new_name
        PROJECT_RENAME_MAP_INV[(config_id, new_name)] = project

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
    CONFIG_IDS = [f"lane{l}" for l in detected_lanes]

# Optional preferred bcl_convert sequencing by config_id.
# Example in config YAML:
# bcl_convert_order:
#   - lane3
#   - lane1
#   - lane2
_preferred_bcl_order = [str(x) for x in config.get("bcl_convert_order", [])]
_preferred_bcl_order = [cid for cid in _preferred_bcl_order if cid in CONFIG_IDS]
BCL_CONVERT_ORDER = _preferred_bcl_order + [cid for cid in CONFIG_IDS if cid not in _preferred_bcl_order]
# Only chain sequential dependencies when the user explicitly provided an order.
# An empty bcl_convert_order means "run all lanes in parallel".
if _preferred_bcl_order:
    BCL_CONVERT_PREV = {
        cid: (BCL_CONVERT_ORDER[i - 1] if i > 0 else None)
        for i, cid in enumerate(BCL_CONVERT_ORDER)
    }
else:
    BCL_CONVERT_PREV = {}

def get_prev_bcl_done(wildcards):
    prev_cid = BCL_CONVERT_PREV.get(wildcards.config_id)
    if not prev_cid:
        return []
    if os.path.exists(f".output/{wildcards.config_id}/.done"):
        return []
    return [maybe_ancient(f".output/{prev_cid}/.done")]

FASTP_THREADS = config.get("fastp_threads", 4)

PROJECTS = get_all_projects(SAMPLE_SHEETS_DICT)

ORDER_ID_CONFIGS = get_order_id_configs(SAMPLE_SHEETS_DICT)

# If order_id was not propagated into sample sheets, fall back to IDs inferred
# from metadata parsing (Summary / Barcode List) before using a generic default.
if not ORDER_ID_CONFIGS or all(not v for v in ORDER_ID_CONFIGS.values()):
    inferred_order_ids = sorted({oid for oid in PROJECT_ORDER_ID.values() if oid and str(oid).strip()})
    if inferred_order_ids:
        ORDER_ID_CONFIGS = {oid: list(PROJECTS) for oid in inferred_order_ids}
    else:
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

# NOTE: do not name the loop variable `config` here. Python leaks loop variables into
# the enclosing scope, so that would rebind Snakemake's global `config` dict to the last
# lane dict and make every later config.get(...) silently fall back to its default.
FLEXBAR_CONFIGS = []
for _lane_cfg in LANE_CONFIGS:
    if _lane_cfg['id'] not in CONFIG_IDS:
        continue
    barcode_path = os.path.join("metadata", f"flexbar_barcodes_{_lane_cfg['id']}.txt")
    if os.path.exists(barcode_path):
        FLEXBAR_CONFIGS.append(_lane_cfg['id'])

FQTK_CONFIGS = []
for _lane_cfg in LANE_CONFIGS:
    if _lane_cfg['id'] not in CONFIG_IDS:
        continue
    fqtk_tsv = os.path.join("metadata", f"fqtk_barcodes_{_lane_cfg['id']}.tsv")
    if os.path.exists(fqtk_tsv):
        FQTK_CONFIGS.append(_lane_cfg['id'])

# _CONFIG_PROJECT_PAIRS_RAW keeps the *original* Sample_Project names from the
# renaming-map CSVs.  These are the names under which fastp JSONs and BCL
# staging directories are stored, so they must remain unchanged here.
_CONFIG_PROJECT_PAIRS_RAW = get_config_project_pairs(SAMPLE_SHEETS_DICT)

# Build CONFIG_PROJECT_PAIRS with per-group expansion for projects whose name is
# shared across multiple groups on the same lane.  For those projects
# PROJECT_RENAME_MAP only holds the last-written entry, so we expand them
# explicitly here using ORDER_ID_LOOKUP / LAB_ID_LOOKUP instead.
CONFIG_PROJECT_PAIRS = []
for _cid, _p in _CONFIG_PROJECT_PAIRS_RAW:
    _lm = re.match(r'lane(\d+)', _cid)
    if _lm:
        _lane = int(_lm.group(1))
        _groups = [g for (l, g), proj in PROJECT_LOOKUP.items() if l == _lane and proj == _p]
        if len(_groups) > 1:
            for _g in _groups:
                _oid = ORDER_ID_LOOKUP.get((_lane, _g), "")
                _lid = LAB_ID_LOOKUP.get((_lane, _g), "")
                if _lid and _oid:
                    CONFIG_PROJECT_PAIRS.append((_cid, f"{_lid}_{_oid}_{LIBRARY}_L{_lane}_G{_g}"))
            continue
    CONFIG_PROJECT_PAIRS.append((_cid, PROJECT_RENAME_MAP.get((_cid, _p), _p)))

# Translate old Sample_Project names in ORDER_ID_CONFIGS to new renamed folder names.
# Use CONFIG_PROJECT_PAIRS (which already handles multi-group expansion) so that
# each per-group renamed folder is mapped to the correct order_id.
for _oid in list(ORDER_ID_CONFIGS.keys()):
    _old_projects = set(ORDER_ID_CONFIGS[_oid])
    _new_projects = set()
    for _cid, _renamed in CONFIG_PROJECT_PAIRS:
        _old_p = PROJECT_RENAME_MAP_INV.get((_cid, _renamed), _renamed)
        if _old_p not in _old_projects:
            continue
        # For multi-group projects verify the encoded group's order_id matches _oid.
        _lm = re.match(r'lane(\d+)', _cid)
        _gm = re.search(r'_G(\d+)$', _renamed)
        if _lm and _gm:
            _actual_oid = ORDER_ID_LOOKUP.get((int(_lm.group(1)), int(_gm.group(1))), "")
            if _actual_oid and _actual_oid != _oid:
                continue
        _new_projects.add(_renamed)
    if _new_projects:
        ORDER_ID_CONFIGS[_oid] = _new_projects
    # else leave as-is (projects with no rename entry keep old names)

# Only build order-level report targets for order IDs that resolve to at least
# one project present in CONFIG_PROJECT_PAIRS. This prevents report_order_id
# jobs from starting with empty dynamic inputs.
_projects_in_pairs = {p for _, p in CONFIG_PROJECT_PAIRS}
ACTIVE_ORDER_IDS = [
    oid for oid, projects in ORDER_ID_CONFIGS.items()
    if set(projects or []).intersection(_projects_in_pairs)
]
ORDER_ID_REPORTS = [f"Reports/order_{oid}/index.html" for oid in ACTIVE_ORDER_IDS]
ORDER_ID_MD5S = [f"Reports/order_{oid}/md5sums.txt" for oid in ACTIVE_ORDER_IDS]

# Exclude order IDs (and their projects) from all targets in rule all.
EXCLUDE_ORDER_IDS = set(config.get("exclude_order_ids", []))
if EXCLUDE_ORDER_IDS:
    _exclude_projects = set()
    for _oid in EXCLUDE_ORDER_IDS:
        _exclude_projects.update(ORDER_ID_CONFIGS.pop(_oid, []))
    ACTIVE_ORDER_IDS = [oid for oid in ACTIVE_ORDER_IDS if oid not in EXCLUDE_ORDER_IDS]
    ORDER_ID_REPORTS = [f"Reports/order_{oid}/index.html" for oid in ACTIVE_ORDER_IDS]
    ORDER_ID_MD5S = [f"Reports/order_{oid}/md5sums.txt" for oid in ACTIVE_ORDER_IDS]
    CONFIG_PROJECT_PAIRS = [(c, p) for c, p in CONFIG_PROJECT_PAIRS if p not in _exclude_projects]
    PROJECTS = [p for p in PROJECTS if p not in _exclude_projects]

PROJECT_LINK_LOGS = [f"logs/{config_id}/project_link_{config_id}---{project}.log" for config_id, project in CONFIG_PROJECT_PAIRS]

# Build flexbar order ID map: config_id -> order_id
# Flexbar projects appear in PROJECT_LOOKUP for a flexbar lane but not in any BCL convert samplesheet.
FLEXBAR_ORDER_ID_MAP = {}   # config_id -> order_id
FLEXBAR_ORDER_ID_PROJECT = {}  # config_id -> original project name from metadata
_bcl_raw_projects_by_config = {}
for _cid, _p in _CONFIG_PROJECT_PAIRS_RAW:
    _bcl_raw_projects_by_config.setdefault(_cid, set()).add(_p)
for _fconfig in FLEXBAR_CONFIGS:
    _lane = int(_fconfig.replace('lane', ''))
    _bcl_projs = _bcl_raw_projects_by_config.get(_fconfig, set())
    for (_l, _), _proj in PROJECT_LOOKUP.items():
        if _l == _lane and _proj not in _bcl_projs:
            _oid = PROJECT_ORDER_ID.get((_proj, _lane), '')
            if _oid and _oid not in EXCLUDE_ORDER_IDS:
                FLEXBAR_ORDER_ID_MAP[_fconfig] = _oid
                FLEXBAR_ORDER_ID_PROJECT[_fconfig] = _proj
FLEXBAR_CONFIG_BY_ORDER_ID = {}  # order_id -> [config_id, ...]
for _k, _v in FLEXBAR_ORDER_ID_MAP.items():
    FLEXBAR_CONFIG_BY_ORDER_ID.setdefault(_v, []).append(_k)
FLEXBAR_ACTIVE_ORDER_IDS = list(FLEXBAR_ORDER_ID_MAP.values())
FLEXBAR_ORDER_REPORTS = [f"Reports/order_{oid}/index.html" for oid in FLEXBAR_ACTIVE_ORDER_IDS]

# Build flexbar renaming map: config_id -> list of row dicts (one per barcode/sample).
# This allows flexbar-demuxed samples to flow through fastp and report_order_id.
FLEXBAR_CONFIG_RENAMING_MAP = {}
for _fconfig, _forder_id in FLEXBAR_ORDER_ID_MAP.items():
    _flane = int(_fconfig.replace('lane', ''))
    _fbarcode_path = f"metadata/flexbar_barcodes_{_fconfig}.txt"
    if not os.path.exists(_fbarcode_path):
        continue
    _fproj = FLEXBAR_ORDER_ID_PROJECT.get(_fconfig)
    if not _fproj:
        continue
    _fgroup = None
    for (_fl, _fg), _fp in PROJECT_LOOKUP.items():
        if _fl == _flane and _fp == _fproj:
            _fgroup = _fg
            break
    if _fgroup is None:
        continue
    _frows = []
    with open(_fbarcode_path) as _fbf:
        for _fi, _fbline in enumerate(_fbf):
            _fparts = _fbline.strip().split('\t')
            if len(_fparts) >= 2 and _fparts[0].strip() and _fparts[1].strip():
                _frows.append({
                    'Sample_Project': _fproj,
                    'Sample_Name': _fparts[0].strip(),
                    'Run': LIBRARY,
                    'Lane': _flane,
                    'Group': _fgroup,
                    'index': _fparts[1].strip(),
                    'index2': '',
                    'Position': f'P{_fi+1:03d}',
                })
    if _frows:
        FLEXBAR_CONFIG_RENAMING_MAP[_fconfig] = _frows

# Inject flexbar projects into CONFIG_PROJECT_PAIRS, ORDER_ID_CONFIGS, ACTIVE_ORDER_IDS
# so they are processed through fastp, md5sums, project_link, and report_order_id.
for _fconfig, _frows in FLEXBAR_CONFIG_RENAMING_MAP.items():
    _forig_proj = _frows[0]['Sample_Project']
    _frenamed_proj = PROJECT_RENAME_MAP.get((_fconfig, _forig_proj), _forig_proj)
    _fpair = (_fconfig, _frenamed_proj)
    if _fpair not in CONFIG_PROJECT_PAIRS:
        CONFIG_PROJECT_PAIRS.append(_fpair)
    _projects_in_pairs.add(_frenamed_proj)
    _forder_id = FLEXBAR_ORDER_ID_MAP[_fconfig]
    if _forder_id not in ORDER_ID_CONFIGS:
        ORDER_ID_CONFIGS[_forder_id] = set()
    elif not isinstance(ORDER_ID_CONFIGS.get(_forder_id), set):
        ORDER_ID_CONFIGS[_forder_id] = set(ORDER_ID_CONFIGS.get(_forder_id, []))
    ORDER_ID_CONFIGS[_forder_id].add(_frenamed_proj)
    if _forder_id not in ACTIVE_ORDER_IDS:
        ACTIVE_ORDER_IDS.append(_forder_id)

# Integrated flexbar orders are now handled by report_order_id; remove from FLEXBAR_ACTIVE_ORDER_IDS
FLEXBAR_ACTIVE_ORDER_IDS = [oid for oid in FLEXBAR_ACTIVE_ORDER_IDS if oid not in ACTIVE_ORDER_IDS]
FLEXBAR_ORDER_REPORTS = [f"Reports/order_{oid}/index.html" for oid in FLEXBAR_ACTIVE_ORDER_IDS]

# Rebuild order-level targets to include newly added flexbar orders
ORDER_ID_REPORTS = [f"Reports/order_{oid}/index.html" for oid in ACTIVE_ORDER_IDS]
ORDER_ID_MD5S = [f"Reports/order_{oid}/md5sums.txt" for oid in ACTIVE_ORDER_IDS]

# Build fqtk order ID map: config_id -> order_id
# fqtk projects appear in PROJECT_LOOKUP for their lane but not in any BCL Convert samplesheet.
FQTK_ORDER_ID_MAP = {}    # config_id -> order_id
FQTK_ORDER_ID_PROJECT = {}  # config_id -> original project name from metadata
for _qconfig in FQTK_CONFIGS:
    _qlane = int(_qconfig.replace('lane', ''))
    _qbcl_projs = _bcl_raw_projects_by_config.get(_qconfig, set())
    for (_ql, _), _qproj in PROJECT_LOOKUP.items():
        if _ql == _qlane and _qproj not in _qbcl_projs:
            _qoid = PROJECT_ORDER_ID.get((_qproj, _qlane), '')
            if _qoid and _qoid not in EXCLUDE_ORDER_IDS:
                FQTK_ORDER_ID_MAP[_qconfig] = _qoid
                FQTK_ORDER_ID_PROJECT[_qconfig] = _qproj

# Build fqtk renaming map: config_id -> list of row dicts (one per barcode/sample).
# The TSV has a header row (sample_id\tbarcode) followed by data rows.
FQTK_CONFIG_RENAMING_MAP = {}
for _qconfig, _qorder_id in FQTK_ORDER_ID_MAP.items():
    _qlane = int(_qconfig.replace('lane', ''))
    _qtsv_path = f"metadata/fqtk_barcodes_{_qconfig}.tsv"
    if not os.path.exists(_qtsv_path):
        continue
    _qproj = FQTK_ORDER_ID_PROJECT.get(_qconfig)
    if not _qproj:
        continue
    _qgroup = None
    for (_ql, _qg), _qp in PROJECT_LOOKUP.items():
        if _ql == _qlane and _qp == _qproj:
            _qgroup = _qg
            break
    if _qgroup is None:
        continue
    _qrows = []
    _qdata_idx = 0
    with open(_qtsv_path) as _qtf:
        for _qi, _qtline in enumerate(_qtf):
            if _qi == 0:
                continue  # skip header
            _qparts = _qtline.strip().split('\t')
            if len(_qparts) >= 2 and _qparts[0].strip() and _qparts[1].strip():
                _qrows.append({
                    'Sample_Project': _qproj,
                    'Sample_Name': _qparts[0].strip(),
                    'Run': LIBRARY,
                    'Lane': _qlane,
                    'Group': _qgroup,
                    'index': _qparts[1].strip(),
                    'index2': '',
                    'Position': f'P{_qdata_idx+1:03d}',
                })
                _qdata_idx += 1
    if _qrows:
        FQTK_CONFIG_RENAMING_MAP[_qconfig] = _qrows

# Inject fqtk projects into CONFIG_PROJECT_PAIRS, ORDER_ID_CONFIGS, ACTIVE_ORDER_IDS
for _qconfig, _qrows in FQTK_CONFIG_RENAMING_MAP.items():
    _qorig_proj = _qrows[0]['Sample_Project']
    _qrenamed_proj = PROJECT_RENAME_MAP.get((_qconfig, _qorig_proj), _qorig_proj)
    _qpair = (_qconfig, _qrenamed_proj)
    if _qpair not in CONFIG_PROJECT_PAIRS:
        CONFIG_PROJECT_PAIRS.append(_qpair)
    _projects_in_pairs.add(_qrenamed_proj)
    _qorder_id = FQTK_ORDER_ID_MAP[_qconfig]
    if _qorder_id not in ORDER_ID_CONFIGS:
        ORDER_ID_CONFIGS[_qorder_id] = set()
    elif not isinstance(ORDER_ID_CONFIGS.get(_qorder_id), set):
        ORDER_ID_CONFIGS[_qorder_id] = set(ORDER_ID_CONFIGS.get(_qorder_id, []))
    ORDER_ID_CONFIGS[_qorder_id].add(_qrenamed_proj)
    if _qorder_id not in ACTIVE_ORDER_IDS:
        ACTIVE_ORDER_IDS.append(_qorder_id)

# Rebuild order-level targets to include newly added fqtk orders
ORDER_ID_REPORTS = [f"Reports/order_{oid}/index.html" for oid in ACTIVE_ORDER_IDS]
ORDER_ID_MD5S = [f"Reports/order_{oid}/md5sums.txt" for oid in ACTIVE_ORDER_IDS]

# print("CONFIG_PROJECT_PAIRS:", CONFIG_PROJECT_PAIRS)

rule all:
    input:
        expand("results/{config_id}/fastp_plots_{config_id}.done", config_id=CONFIG_IDS),
        expand(".output/{config_id}/.done", config_id=CONFIG_IDS),
        expand("output/{config_id}/{project}/md5sums.txt", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        ORDER_ID_REPORTS,
        ORDER_ID_MD5S,
        expand("results/lane{lane}/fastp_plots_summary_lane{lane}.done", lane=detected_lanes),
        expand("results/undetermined_indices/{config_id}.csv", config_id=CONFIG_IDS),
        expand("results/{config_id}/{project}/read_counts_{project}.csv", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        # expand("logs/{config_id}/project_link_{config_id}_{project}.log", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        expand("logs/{config_id}/project_links_{config_id}---{project}.yaml", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        f"results/{LIBRARY}-count.csv",
        f"Reports/{LIBRARY}_read_counts_email.done",
        expand("Reports/order_{order_id}/email_sent.done", order_id=ACTIVE_ORDER_IDS + FLEXBAR_ACTIVE_ORDER_IDS),
        expand("output/{config_id}/{project}/.low_reads_checked", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        expand("output/{config_id}/{project}/.plots_copied", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        expand("logs/{config_id}/verify_project_link_{config_id}---{project}.txt", zip, config_id=[c for c, p in CONFIG_PROJECT_PAIRS], project=[p for c, p in CONFIG_PROJECT_PAIRS]),
        ([VALIDATION_XLSX] if VALIDATION_XLSX else []),
        expand("results/{config_id}/flexbar_{config_id}.done", config_id=FLEXBAR_CONFIGS),
        expand("results/{config_id}/fqtk_{config_id}.done", config_id=FQTK_CONFIGS),
        # "logs/rsync_to_external_drive.done",
        # "results/check_index_rc_swap.txt"
    benchmark:
        "benchmarks/all.bench"

rule bcl_convert_only:
    input:
        expand(".output/{config_id}/.done", config_id=CONFIG_IDS)
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
            f"logs/{c}/project_links_{c}---{p}.yaml"
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
        fastp_plots_base = "results",
        fastp_base = "results",
        report_dir = "Reports/order_{order_id}"
    run:
        import subprocess
        import sys
        import os
        sys.path.insert(0, workflow.basedir)
        
        import yaml as _yaml

        def _as_file_list(value):
            """Normalize Snakemake named inputs to a list of file paths.

            With a single upstream file, named inputs can be exposed as a scalar path.
            """
            if value is None:
                return []
            if isinstance(value, (str, os.PathLike)):
                return [str(value)]
            try:
                return [str(v) for v in value]
            except TypeError:
                return [str(value)]

        order_id = params.order_id
        report_dir = params.report_dir
        log_file = log[0]

        # Determine lane filter: if this order_id maps to a single lane, filter by it
        _lanes_for_order = ORDER_ID_TO_LANE.get(order_id, [])
        lane_arg = ",".join(str(l) for l in _lanes_for_order) if _lanes_for_order else "None"

        os.makedirs(report_dir, exist_ok=True)

        # Merge individual per-project yaml files into a single dict
        merged_links = {}
        links_yaml_files = _as_file_list(input.links_yamls)
        if not links_yaml_files:
            # Fallback: glob for yaml files whose name encodes this order_id.
            # This handles Snakemake subprocess mode where named input lambdas
            # may resolve to [] even though the files exist on disk.
            import glob as _glob
            links_yaml_files = sorted(_glob.glob(f"logs/**/project_links_*---*_{order_id}_*.yaml", recursive=True))
        for yaml_path in links_yaml_files:
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

        # Build renamed→original project name mapping for all projects in this order_id.
        # generate_report.py uses this to display original metadata names in the HTML.
        import json as _json
        project_name_map = {}
        for _proj in projects:
            _orig = next(
                (p for cid, p in _CONFIG_PROJECT_PAIRS_RAW
                 if PROJECT_RENAME_MAP.get((cid, p), p) == _proj),
                None
            )
            # For multi-group projects, PROJECT_RENAME_MAP only stores the
            # last-written entry so the forward scan above may miss earlier
            # groups.  Fall back to the inverse map which has an entry for
            # every per-group renamed folder name.
            if _orig is None:
                _orig = next(
                    (orig for (_, _rn), orig in PROJECT_RENAME_MAP_INV.items()
                     if _rn == _proj),
                    _proj
                )
            project_name_map[_proj] = _orig

        # Flexbar/fqtk projects are injected into CONFIG_PROJECT_PAIRS after the main
        # rename map is built, so they are not present in _CONFIG_PROJECT_PAIRS_RAW.
        # Add explicit renamed->original mappings here so generate_report.py can
        # find the fastp JSONs under the original project directory.
        for _fconfig in FLEXBAR_CONFIGS:
            _forig = FLEXBAR_ORDER_ID_PROJECT.get(_fconfig)
            if not _forig:
                continue
            _frenamed = PROJECT_RENAME_MAP.get((_fconfig, _forig), _forig)
            if _frenamed in projects:
                project_name_map[_frenamed] = _forig
        for _qconfig in FQTK_CONFIGS:
            _qorig = FQTK_ORDER_ID_PROJECT.get(_qconfig)
            if not _qorig:
                continue
            _qrenamed = PROJECT_RENAME_MAP.get((_qconfig, _qorig), _qorig)
            if _qrenamed in projects:
                project_name_map[_qrenamed] = _qorig
        project_name_map_json = _json.dumps(project_name_map)

        # Open log file
        with open(log_file, 'w') as lf:
            lf.write(f"Generating report for order_id: {order_id}\n")
            lf.write(f"Link YAML inputs: {links_yaml_files}\n")
            lf.write(f"Projects: {projects}\n")
            lf.write(f"Project name map: {project_name_map}\n\n")

        # Generate report for each project in this order_id
        for project in projects:
            orig_project = project_name_map.get(project, project)

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
                str(config.get('plots_quality', 35)),
                orig_project,          # orig_project_name for fastp lookups
                project_name_map_json, # full renamed→original map for report display
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            with open(log_file, 'a') as f:
                f.write(f"\n=== Report generation for project {project} ===\n")
                f.write(result.stdout)
                if result.stderr:
                    f.write(f"STDERR: {result.stderr}\n")
        
        # Consolidate md5 sums from all projects in this order_id
        all_md5s = []
        md5_input_files = _as_file_list(input.md5_files)
        for md5_file in md5_input_files:
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

        # Always generate Download Instructions PDF so rule outputs are complete,
        # even when project discovery returns an empty set.
        pdf_file = os.path.join(report_dir, "Download_Instructions.pdf")
        pdf_cmd = ["python3", "src/generate_download_instructions_pdf.py", pdf_file]
        pdf_result = subprocess.run(pdf_cmd, capture_output=True, text=True)
        with open(log_file, 'a') as f:
            f.write("\n=== Download Instructions PDF generation ===\n")
            f.write(pdf_result.stdout)
            if pdf_result.stderr:
                f.write(f"PDF STDERR: {pdf_result.stderr}\n")
        if pdf_result.returncode != 0:
            raise RuntimeError(f"PDF generation failed for order {order_id}")

        # Ensure HTML output exists if no per-project report was generated.
        if not os.path.exists(output.html):
            with open(output.html, 'w') as f:
                f.write(f"<html><body><h1>Order {order_id}</h1><p>No project report entries were generated.</p></body></html>\n")

rule flexbar_project_link:
    """Create a Nextcloud share for the flexbar output directory and record the link."""
    input:
        done = "results/{config_id}/flexbar_{config_id}.done"
    output:
        link_log  = "logs/{config_id}/flexbar_project_link_{config_id}.log",
        yaml_file = "logs/{config_id}/flexbar_project_links_{config_id}.yaml"
    benchmark:
        "benchmarks/flexbar_project_link_{config_id}.bench"
    wildcard_constraints:
        config_id = "[^/]+"
    resources:
        serial_operation = 1
    params:
        work_dir  = os.getcwd(),
        order_id  = lambda wildcards: FLEXBAR_ORDER_ID_MAP.get(wildcards.config_id, ""),
        project   = lambda wildcards: FLEXBAR_ORDER_ID_PROJECT.get(wildcards.config_id, "flexbar"),
    run:
        import traceback, subprocess, time, urllib.parse, re, os, shlex
        from pathlib import Path
        import yaml as _yaml

        config_id = wildcards.config_id
        order_id  = params.order_id
        project   = params.project
        fastq_dir = f"output/{config_id}/flexbar"
        log_file  = output.link_log
        yaml_file = output.yaml_file

        if not str(order_id).strip():
            msg = (
                f"Missing order_id for flexbar project link generation "
                f"(config_id={config_id}, project={project}). "
                "Check metadata order-id mapping for this config."
            )
            Path(log_file).write_text(msg + "\n")
            raise RuntimeError(msg)

        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        yaml_data = {project: {config_id: {}}}

        def extract_share_url(xml_text):
            if not xml_text: return None
            m = re.search(r'<url>(.*?)</url>', xml_text)
            return m.group(1) if m else None

        def extract_share_token(xml_text):
            if not xml_text: return None
            m = re.search(r'<token>(.*?)</token>', xml_text)
            return m.group(1) if m else None

        def extract_share_owner(xml_text):
            if not xml_text: return None
            for pattern in [r'<uid_owner>(.*?)</uid_owner>', r'<owner>(.*?)</owner>']:
                m = re.search(pattern, xml_text)
                if m: return m.group(1)
            return None

        def extract_internal_path(xml_text):
            if not xml_text: return None
            for pattern in [r'<path>(.*?)</path>', r'<folder>(.*?)</folder>']:
                m = re.search(pattern, xml_text)
                if m: return m.group(1)
            return None

        def fetch_existing_share(path):
            encoded = urllib.parse.quote(path, safe="/")
            cmd = ['curl', '-s', '-X', 'GET',
                   '-u', f'{NEXTCLOUD_USER}:{NEXTCLOUD_PASSWORD}',
                   '-H', 'OCS-APIRequest: true',
                   f'{NEXTCLOUD_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares?path={encoded}&reshares=true']
            return subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout

        executed_cmds = []
        try:
            if os.path.isdir(fastq_dir):
                abs_path = os.path.abspath(fastq_dir)
                nc_path = f"/{NEXTCLOUD_DIR_NAME}/" + abs_path.split(f"/{NEXTCLOUD_DIR_PATH}/", 1)[1] \
                          if f"/{NEXTCLOUD_DIR_PATH}/" in abs_path else abs_path

                max_retries, retry_count = 30, 0
                share_url = share_token = share_owner = share_internal_path = None
                rate_limited, last_error = False, None

                while retry_count < max_retries and not share_url:
                    retry_count += 1
                    wait_time = min(3 * (2 ** (retry_count - 1)), 60)
                    if rate_limited: time.sleep(10)
                    try:
                        cmd = ['curl', '-s', '-w', '\nHTTP_CODE:%{http_code}',
                               '-X', 'POST',
                               '-u', f'{NEXTCLOUD_USER}:{NEXTCLOUD_PASSWORD}',
                               '-H', 'OCS-APIRequest: true',
                               '-d', f'path={nc_path}', '-d', 'shareType=3',
                               f'{NEXTCLOUD_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares']
                        executed_cmds.append(cmd)
                        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                        lines = result.stdout.split('\n')
                        http_code = next((l.split(':')[1] for l in lines if l.startswith('HTTP_CODE:')), None)
                        share_xml = '\n'.join(l for l in lines if not l.startswith('HTTP_CODE:'))
                        if http_code == '429':
                            rate_limited = True; last_error = f"Rate limited (HTTP 429)"
                        elif http_code in ('200', '201'):
                            share_url   = extract_share_url(share_xml)
                            share_token = extract_share_token(share_xml)
                            if share_url and share_token:
                                share_owner         = extract_share_owner(share_xml)
                                share_internal_path = extract_internal_path(share_xml)
                                break
                            else:
                                last_error = f"Valid response but could not extract URL/token (HTTP {http_code})"
                        elif http_code in ('400', '403'):
                            share_xml   = fetch_existing_share(nc_path)
                            share_url   = extract_share_url(share_xml)
                            share_token = extract_share_token(share_xml)
                            if share_url and share_token:
                                share_owner         = extract_share_owner(share_xml)
                                share_internal_path = extract_internal_path(share_xml)
                                break
                            else:
                                last_error = f"Share may exist but could not fetch via GET (HTTP {http_code})"
                        else:
                            last_error = f"HTTP {http_code}: {share_xml[:100] if share_xml else 'No response'}"
                        if retry_count < max_retries and not share_url:
                            time.sleep(wait_time)
                    except subprocess.TimeoutExpired:
                        last_error = "Request timed out (30 seconds)"
                        if retry_count < max_retries: time.sleep(wait_time)
                    except Exception as e:
                        last_error = f"Exception: {str(e)}"
                        if retry_count < max_retries: time.sleep(wait_time)

                with open(log_file, 'w') as f:
                    f.write(f"Project: {project}\nConfig ID: {config_id}\nOrder ID: {order_id}\n")
                    try: f.write(f"NC_PATH: {nc_path}\n")
                    except Exception: pass
                    if share_url and share_token:
                        f.write(f"Status: SUCCESS\nBrowser URL: {share_url}\n")
                        f.write(f"WebDAV URL: {NEXTCLOUD_URL}/public.php/dav/\nWebDAV Token: {share_token}\n")
                        if share_owner:         f.write(f"NC_OWNER: {share_owner}\n")
                        if share_internal_path: f.write(f"NC_INTERNAL_PATH: {share_internal_path}\n")
                        yaml_data[project][config_id][order_id] = {"link": share_url, "group": "flexbar"}
                    else:
                        f.write(f"Status: FAILED\nReason: {last_error}\nRetries: {retry_count}/{max_retries}\n")
                    if executed_cmds:
                        f.write("\nCommands executed:\n")
                        for c in executed_cmds:
                            try:    f.write(shlex.join(c) + "\n")
                            except: f.write(' '.join(shlex.quote(p) for p in c) + "\n")
            else:
                Path(log_file).write_text(f"Directory {fastq_dir} not found.")
        except Exception as e:
            Path(log_file).write_text(f"Error: {str(e)}\n{traceback.format_exc()}")

        Path(log_file).touch(exist_ok=True)
        with open(yaml_file, 'w') as yf:
            _yaml.dump(yaml_data, yf, default_flow_style=False)


        # Generate Download Instructions PDF
        pdf_cmd = ["python3", "src/generate_download_instructions_pdf.py",
                   os.path.join(report_dir, "Download_Instructions.pdf")]
        pdf_result = subprocess.run(pdf_cmd, capture_output=True, text=True)
        with open(log_file, 'a') as f:
            f.write(pdf_result.stdout)
            if pdf_result.stderr:
                f.write(f"PDF STDERR: {pdf_result.stderr}\n")


rule collect_flexbar_report_extras:
    input:
        done = "results/{config_id}/flexbar_{config_id}.done"
    output:
        flexbar_log = "Reports/order_{order_id}/flexbarOut_{config_id}.log",
        barcodes    = "Reports/order_{order_id}/flexbar_barcodes_{config_id}.txt",
        filesizes   = "Reports/order_{order_id}/flexbar_filesizes_{config_id}.txt"
    wildcard_constraints:
        config_id = "[^/]+"
    run:
        import shutil, os, re
        config_id = wildcards.config_id
        os.makedirs(f"Reports/order_{wildcards.order_id}", exist_ok=True)
        shutil.copy(f"output/{config_id}/flexbar/flexbarOut.log", output.flexbar_log)

        # Build sample_name -> renamed stem mapping from FLEXBAR_CONFIG_RENAMING_MAP
        name_map = {}
        for _row in FLEXBAR_CONFIG_RENAMING_MAP.get(config_id, []):
            _sname = _row['Sample_Name']
            _idx1 = str(_row.get('index', '') or '')
            _idx2 = str(_row.get('index2', '') or '')
            _bc = f"{_idx1}-{_idx2}" if _idx2 and _idx2.lower() != 'nan' else _idx1
            name_map[_sname] = f"{_row['Run']}-L{_row['Lane']}-G{_row['Group']}-{_row['Position']}-{_bc}"

        # Write barcodes file with renamed sample names in column 1
        with open(f"metadata/flexbar_barcodes_{config_id}.txt") as _fin, \
             open(output.barcodes, 'w') as _fout:
            for _line in _fin:
                _parts = _line.rstrip('\n').split('\t')
                if _parts and _parts[0].strip() in name_map:
                    _parts[0] = name_map[_parts[0].strip()]
                _fout.write('\t'.join(_parts) + '\n')

        # Write filesizes file with renamed FASTQ names
        with open(f"output/{config_id}/flexbar/size.txt") as _fin, \
             open(output.filesizes, 'w') as _fout:
            for _line in _fin:
                _parts = _line.rstrip('\n').split('\t')
                if len(_parts) >= 2:
                    _m = re.match(r'flexbarOut_barcode_(.+?)(_R2)?\.fastq\.gz$', _parts[1].strip())
                    if _m:
                        _sname, _r2 = _m.group(1), _m.group(2)
                        _rtype = 'R2' if _r2 else 'R1'
                        if _sname in name_map:
                            _parts[1] = f"{name_map[_sname]}-{_rtype}.fastq.gz"
                _fout.write('\t'.join(_parts) + '\n')


rule send_order_email:
    input:
        html = "Reports/order_{order_id}/index.html",
        md5  = "Reports/order_{order_id}/md5sums.txt",
        pdf  = "Reports/order_{order_id}/Download_Instructions.pdf",
        flexbar_extras = lambda wildcards: [
            f"Reports/order_{wildcards.order_id}/{prefix}_{cid}.{ext}"
            for cid in FLEXBAR_CONFIG_BY_ORDER_ID.get(wildcards.order_id, [])
            for prefix, ext in [("flexbarOut", "log"), ("flexbar_barcodes", "txt"), ("flexbar_filesizes", "txt")]
        ]
    output:
        touch("Reports/order_{order_id}/email_sent.done")
    log:
        "logs/send_order_email_{order_id}.log"
    benchmark:
        "benchmarks/send_order_email_{order_id}.bench"
    params:
        script   = "src/send_email.py",
        sender   = EMAIL_SENDER,
        receiver = EMAIL_RECIPIENT,
        cc_email = EMAIL_CC,
        subject  = lambda wildcards: f"Sequencing Report for Order {wildcards.order_id}"
    run:
        import subprocess, os
        order_id = wildcards.order_id
        attachments = f"{input.md5};{input.pdf}"
        for cid in FLEXBAR_CONFIG_BY_ORDER_ID.get(order_id, []):
            for prefix, ext in [("flexbarOut", "log"), ("flexbar_barcodes", "txt"), ("flexbar_filesizes", "txt")]:
                extra = f"Reports/order_{order_id}/{prefix}_{cid}.{ext}"
                if os.path.exists(extra):
                    attachments += f";{extra}"
        cmd = [
            "python3", "src/send_email_retry.py",
            params.script, params.sender, params.receiver,
            params.subject, input.html, attachments,
            params.cc_email, order_id
        ]
        with open(log[0], "w") as logf:
            result = subprocess.run(cmd, stdout=logf, stderr=logf)
        if result.returncode != 0:
            raise RuntimeError(f"Email send failed (see {log[0]})")

rule fastp_sample:
    input:
        done = lambda wildcards: (
            lambda orig: f"output/{wildcards.config_id}/{PROJECT_RENAME_MAP.get((wildcards.config_id, orig), orig)}/.fastq_names_done"
        )(wildcards.sample_path.split('/')[0])
    output:
        json = "results/{config_id}/{sample_path}.fastp.json",
        html = "results/{config_id}/{sample_path}.fastp.html"
    log:
        "logs/{config_id}/fastp_sample/{config_id}/{sample_path}.log"
    benchmark:
        "benchmarks/fastp_sample_{config_id}_{sample_path}.bench"
    wildcard_constraints:
        config_id = "[^/]+",
        sample_path = ".*"
    params:
        fastqs = get_fastp_sample_input,
    threads: 2
    shell:
        """
        (
        mkdir -p $(dirname {output.json})

        files=({params.fastqs})
        r1="${{files[0]}}"

        if [ ${{#files[@]}} -gt 1 ]; then
            r2="${{files[1]}}"
            fastp -i "$r1" -I "$r2" -A -Q -L --reads_to_process 2000000 --json "{output.json}" --html "{output.html}" -w {threads}
        else
            fastp -i "$r1" -A -Q -L --reads_to_process 2000000 --json "{output.json}" --html "{output.html}" -w {threads}
        fi
        ) > {log} 2>&1
        """

rule normalize_project_fastq_names:
    input:
        done = "output/{config_id}/{project}/.project_done",
        renaming_map = "results/{config_id}/renaming_map_{config_id}.csv"
    output:
        sentinel = touch("output/{config_id}/{project}/.fastq_names_done")
    wildcard_constraints:
        config_id = "[^/]+",
        project = ".+"
    run:
        import os
        import shutil

        config_id = wildcards.config_id
        new_project = wildcards.project
        old_project = PROJECT_RENAME_MAP_INV.get((config_id, new_project), new_project)
        project_dir = os.path.abspath(f"output/{config_id}/{new_project}")

        if not os.path.isdir(project_dir):
            os.makedirs(project_dir, exist_ok=True)
            return

        check_name = old_project or new_project
        lowered = check_name.lower()
        if any(token in lowered for token in ["10x", "parse", "bd"]):
            return

        def _materialize_and_backlink(src_abs, dst_abs):
            if os.path.lexists(dst_abs) and os.path.islink(dst_abs):
                os.unlink(dst_abs)
            if not os.path.exists(dst_abs):
                try:
                    os.link(src_abs, dst_abs)
                except Exception:
                    shutil.copy2(src_abs, dst_abs)
            if os.path.lexists(src_abs):
                try:
                    if os.path.islink(src_abs) and os.path.realpath(src_abs) == os.path.realpath(dst_abs):
                        return
                    os.unlink(src_abs)
                except Exception:
                    pass
            os.symlink(os.path.abspath(dst_abs), src_abs)

        _all_flex_rows = globals().get('FLEXBAR_CONFIG_RENAMING_MAP', {}).get(config_id, [])
        _flexbar_orig_proj = globals().get('FLEXBAR_ORDER_ID_PROJECT', {}).get(config_id, '')
        _flexbar_proj = PROJECT_RENAME_MAP.get((config_id, _flexbar_orig_proj), _flexbar_orig_proj)
        flex_rows = _all_flex_rows if new_project == _flexbar_proj else []
        for idx, row in enumerate(flex_rows):
            sample_name = str(row.get("Sample_Name", "")).strip()
            if not sample_name or sample_name.lower() == "nan":
                continue

            run_name = str(row.get("Run", "")).strip()
            lane = int(row.get("Lane", 0))
            try:
                group = str(int(float(row.get("Group", 0))))
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

            src_r1 = os.path.abspath(f"output/{config_id}/flexbar/flexbarOut_barcode_{sample_name}.fastq.gz")
            dst_r1 = os.path.abspath(f"{project_dir}/{stem}-R1.fastq.gz")
            if os.path.exists(src_r1) or os.path.islink(src_r1):
                _materialize_and_backlink(src_r1, dst_r1)

            if NUM_READS > 1:
                src_r2 = os.path.abspath(f"output/{config_id}/flexbar/flexbarOut_barcode_{sample_name}_R2.fastq.gz")
                dst_r2 = os.path.abspath(f"{project_dir}/{stem}-R2.fastq.gz")
                if os.path.exists(src_r2) or os.path.islink(src_r2):
                    _materialize_and_backlink(src_r2, dst_r2)

        df = pd.read_csv(input.renaming_map)
        project_rows = df[df["Sample_Project"].astype(str).str.strip() == old_project]

        for idx, row in project_rows.iterrows():
            sample_name = str(row.get("Sample_Name", "")).strip()
            if not sample_name or sample_name.lower() == "nan":
                continue

            try:
                lane = int(float(row.get("Lane", 0)))
            except Exception:
                lane = 0

            try:
                group = str(int(float(row.get("Group", 0))))
            except Exception:
                group = str(row.get("Group", "")).strip()
            if not group or group.lower() == "nan":
                group = "Undetermined"

            run_name = str(row.get("Run", "")).strip()
            index1 = str(row.get("index", "")).strip()
            if index1.lower() == "nan":
                index1 = ""
            index2 = str(row.get("index2", "")).strip()
            if index2.lower() == "nan":
                index2 = ""
            barcode = f"{index1}-{index2}" if index2 else index1
            position = str(row.get("Position", f"P{idx + 1:03d}")).strip()
            s_num = idx + 1
            stem = f"{run_name}-L{lane}-G{group}-{position}-{barcode}"

            for read_type in ["R1", "R2", "I1", "I2"]:
                legacy_name = f"{sample_name}_S{s_num}_L{lane:03d}_{read_type}_001.fastq.gz"
                canonical_name = f"{stem}-{read_type}.fastq.gz"
                legacy_path = os.path.join(project_dir, legacy_name)
                canonical_path = os.path.join(project_dir, canonical_name)

                if os.path.exists(canonical_path):
                    continue
                if not os.path.exists(legacy_path):
                    continue
                os.rename(legacy_path, canonical_path)

rule fastp_per_config:
    input:
        get_fastp_targets
    output:
        touch("results/{config_id}/fastp_{config_id}.done")
    log:
        "logs/{config_id}/fastp_per_config_{config_id}.log"
    benchmark:
        "benchmarks/fastp_per_config_{config_id}.bench"
    wildcard_constraints:
        config_id = "lane.*"

rule fastp_plots_sample:
    input:
        json = "results/{config_id}/{sample_path}.fastp.json"
    output:
        mean = "results/{config_id}/{sample_path}-mean_phred.png",
        base = "results/{config_id}/{sample_path}-base_comp.png"
    log:
        "logs/{config_id}/fastp_plots_sample/{config_id}/{sample_path}.log"
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
        touch("results/{config_id}/fastp_plots_{config_id}.done")
    log:
        "logs/{config_id}/fastp_plots_per_config_{config_id}.log"
    benchmark:
        "benchmarks/fastp_plots_per_config_{config_id}.bench"
    wildcard_constraints:
        config_id = "lane.*"


rule summarize_project_reads:
    input:
        project_done = "output/{config_id}/{project}/.project_done",
        bcl_done = ".output/{config_id}/.done"
    output:
        "results/{config_id}/{project}/read_counts_{project}.csv"
    log:
        "logs/{config_id}/summarize_project_reads_{config_id}_{project}.log"
    benchmark:
        "benchmarks/summarize_project_reads_{config_id}_{project}.bench"
    run:
        import sys
        sys.stderr = sys.stdout = open(log[0], 'w')
        import pandas as pd
        import os

        # The demux stats may use the pre-rename project name
        target_projects = {wildcards.project}
        for (cid, old_project), new_project in PROJECT_RENAME_MAP.items():
            if cid == wildcards.config_id:
                if old_project == wildcards.project:
                    target_projects.add(new_project)
                elif new_project == wildcards.project:
                    target_projects.add(old_project)

        demux_path = f"output/{wildcards.config_id}/Reports/Demultiplex_Stats.csv"
        data = []

        if not os.path.exists(demux_path):
            print(f"Skipping missing {demux_path}")
        else:
            try:
                demux_df = pd.read_csv(demux_path)
            except Exception as e:
                print(f"Error reading {demux_path}: {e}")
                demux_df = pd.DataFrame()

            if 'Sample_Project' in demux_df.columns:
                matches = demux_df[demux_df['Sample_Project'].astype(str).isin(target_projects)]
                for _, row in matches.iterrows():
                    sample_name = str(row.get('SampleID', row.get('Sample_ID', ''))).strip()
                    read_pairs = int(row.get('# Reads', 0))
                    data.append({
                        'Config': wildcards.config_id,
                        'Project': wildcards.project,
                        'Sample': sample_name,
                        'Total_Reads': read_pairs,
                        'Passed_Reads': read_pairs,
                    })

                # If this project owns the lane's Undetermined pseudo-sample
                # (report_undetermined_configs), include its count too. The
                # Undetermined demux row has Sample_Project='Undetermined', so it
                # isn't captured by the project filter above.
                if wildcards.config_id in REPORT_UNDETERMINED_CONFIGS:
                    map_path = f"results/{wildcards.config_id}/renaming_map_{wildcards.config_id}.csv"
                    owns_undetermined = False
                    if os.path.exists(map_path):
                        try:
                            _m = pd.read_csv(map_path)
                            owns_undetermined = (
                                (_m['Sample_Name'].astype(str).str.strip() == 'Undetermined')
                                & (_m['Sample_Project'].astype(str).str.strip() == wildcards.project)
                            ).any()
                        except Exception as e:
                            print(f"Could not check undetermined ownership in {map_path}: {e}")
                    if owns_undetermined:
                        u_rows = demux_df[demux_df['SampleID'].astype(str).str.strip() == 'Undetermined']
                        for _, row in u_rows.iterrows():
                            read_pairs = int(row.get('# Reads', 0))
                            data.append({
                                'Config': wildcards.config_id,
                                'Project': wildcards.project,
                                'Sample': 'Undetermined',
                                'Total_Reads': read_pairs,
                                'Passed_Reads': read_pairs,
                            })
            else:
                print(f"Missing Sample_Project column in {demux_path}")

        df = pd.DataFrame(data)
        if not df.empty:
            df = df.sort_values(['Sample'])
        df.to_csv(output[0], index=False)

rule compile_read_counts:
    input:
        done = expand(".output/{config_id}/.done", config_id=CONFIG_IDS),
        projects_done = expand(
            "output/{config_id}/{project}/.project_done",
            zip,
            config_id=[c for c, p in CONFIG_PROJECT_PAIRS],
            project=[p for c, p in CONFIG_PROJECT_PAIRS],
        ),
        maps = expand("results/{config_id}/renaming_map_{config_id}.csv", config_id=CONFIG_IDS),
        flexbar_done = expand("results/{config_id}/flexbar_{config_id}.done", config_id=FLEXBAR_CONFIGS),
        fqtk_done    = expand("results/{config_id}/fqtk_{config_id}.done", config_id=FQTK_CONFIGS)
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
            
            # Read Demultiplex_Stats.csv for this config_id.
            # Prefer the renamed/organized copy under output/, but fall back to the
            # raw DRAGEN output under .output/ — some lanes (e.g. per-group demultiplexed
            # lanes) never get a Reports/ dir copied into output/, so the renamed copy is
            # absent even though the raw stats exist and carry the same Sample_Project/SampleID.
            demux_stats_candidates = [
                os.path.join("output", config_id, "Reports", "Demultiplex_Stats.csv"),
                os.path.join(".output", config_id, "Reports", "Demultiplex_Stats.csv"),
            ]
            demux_stats_path = next((p for p in demux_stats_candidates if os.path.exists(p)), None)
            if demux_stats_path is None:
                print(f"Skipping missing Demultiplex_Stats.csv: tried {', '.join(demux_stats_candidates)}")
                continue
            
            try:
                demux_df = pd.read_csv(demux_stats_path)
            except Exception as e:
                print(f"Could not read {demux_stats_path}: {e}")
                continue

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

                # Look up read count in Demultiplex_Stats.csv
                # Match by Lane, Sample_Project, and SampleID
                read_pairs = 0
                try:
                    if sample_name == "Undetermined":
                        # Undetermined is its own SampleID/Sample_Project in
                        # Demultiplex_Stats even though we attach it to a real
                        # project directory; match on the lane's Undetermined row.
                        matches = demux_df[
                            (demux_df['Lane'] == lane) &
                            (demux_df['SampleID'] == 'Undetermined')
                        ]
                    else:
                        # Filter by lane and project
                        matches = demux_df[
                            (demux_df['Lane'] == lane) &
                            (demux_df['Sample_Project'] == project) &
                            (demux_df['SampleID'] == sample_name)
                        ]

                    if len(matches) > 0:
                        # BCL Convert reports '# Reads' as read pairs (clusters), not individual reads
                        read_pairs = int(matches.iloc[0]['# Reads'])
                    else:
                        print(f"No match in Demultiplex_Stats.csv for L{lane} {project} {sample_name}")
                except Exception as e:
                    print(f"Error looking up read count for {sample_name} in {demux_stats_path}: {e}")
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

        # Parse flexbar logs and add per-barcode read counts as a "flexbar" group
        import re as _re
        for config_id in FLEXBAR_CONFIGS:
            lane_num = None
            try:
                m = _re.match(r'lane(\d+)', config_id)
                if m:
                    lane_num = int(m.group(1))
            except Exception:
                pass
            if lane_num is None:
                continue

            flexbar_log = os.path.join("output", config_id, "flexbar", "flexbarOut.log")
            if not os.path.exists(flexbar_log):
                print(f"Skipping missing flexbar log: {flexbar_log}")
                continue

            lane_group_key = (lane_num, "flexbar")
            lane_group_counts.setdefault(lane_group_key, {})

            current_barcode = None
            with open(flexbar_log) as _fh:
                for _line in _fh:
                    _line = _line.strip()
                    m_file = _re.search(r'flexbarOut_barcode_(.+)\.fastq\.gz$', _line)
                    if m_file:
                        current_barcode = m_file.group(1)
                        continue
                    m_reads = _re.match(r'written reads\s+(\d+)', _line)
                    if m_reads and current_barcode and current_barcode != "unassigned":
                        reads = int(m_reads.group(1))
                        label = current_barcode
                        if label not in lane_group_counts[lane_group_key]:
                            lane_group_counts[lane_group_key][label] = [0, 0, "flexbar", 0]
                        lane_group_counts[lane_group_key][label][3] += reads
                        current_barcode = None

        # Parse fqtk demux-metrics.txt and add per-sample read counts as a "fqtk" group
        for config_id in FQTK_CONFIGS:
            lane_num = None
            try:
                m = _re.match(r'lane(\d+)', config_id)
                if m:
                    lane_num = int(m.group(1))
            except Exception:
                pass
            if lane_num is None:
                continue

            fqtk_metrics = os.path.join("output", config_id, "fqtk", "demux-metrics.txt")
            if not os.path.exists(fqtk_metrics):
                print(f"Skipping missing fqtk metrics: {fqtk_metrics}")
                continue

            lane_group_key = (lane_num, "fqtk")
            lane_group_counts.setdefault(lane_group_key, {})

            try:
                with open(fqtk_metrics) as _fh:
                    header_line = None
                    for _line in _fh:
                        _line = _line.rstrip('\n')
                        if not _line or _line.startswith('#'):
                            continue
                        parts = _line.split('\t')
                        if header_line is None:
                            header_line = parts
                            continue
                        row_dict = dict(zip(header_line, parts))
                        sample = row_dict.get('barcode_name', row_dict.get('sample_id', ''))
                        if not sample or sample.lower() in ('unmatched', 'undetermined', ''):
                            continue
                        try:
                            reads = int(row_dict.get('templates', row_dict.get('reads', 0)))
                        except (ValueError, TypeError):
                            reads = 0
                        label = sample
                        if label not in lane_group_counts[lane_group_key]:
                            lane_group_counts[lane_group_key][label] = [0, 0, "fqtk", 0]
                        lane_group_counts[lane_group_key][label][3] += reads
            except Exception as _e:
                print(f"Warning: could not parse fqtk metrics {fqtk_metrics}: {_e}")

        lane_group_pairs_sorted = sorted(lane_group_counts.keys())

        if not lane_group_pairs_sorted:
            raise ValueError(
                "No read counts were compiled. Final Demultiplex_Stats.csv files were missing or contained no matching rows."
            )

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
        csv = f"results/{LIBRARY}-count.csv",
        order_reports = ORDER_ID_REPORTS
    output:
        touch(f"Reports/{LIBRARY}_read_counts_email.done")
    log:
        f"logs/send_read_counts_email.log"
    benchmark:
        "benchmarks/send_read_counts_email.bench"
    priority: 80
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
        touch("results/{config_id}/fastp_plots_summary_lane{lane}.done")
    log:
        "logs/{config_id}/fastp_plots_lane{lane}.log"
    wildcard_constraints:
        lane = r"\d+"

rule flexbar_per_config:
    input:
        bcl_done = ".output/{config_id}/.done",
        raw_barcodes = "metadata/flexbar_barcodes_{config_id}.txt",
        adapter = "src/flexbar/adapter.3.fa"
    threads: 32
    priority: 99
    output:
        touch("results/{config_id}/flexbar_demux_{config_id}.done")
    log:
        "logs/{config_id}/flexbar_{config_id}.log"
    benchmark:
        "benchmarks/flexbar_per_config_{config_id}.bench"
    params:
        outdir = "output/{config_id}/flexbar",
        lane = lambda wildcards: wildcards.config_id.split('_')[0].replace('lane', ''),
        r1 = lambda wildcards: f".output/{wildcards.config_id}/Undetermined_S0_L00{wildcards.config_id.split('_')[0].replace('lane', '')}_R1_001.fastq.gz",
        r2 = lambda wildcards: f".output/{wildcards.config_id}/Undetermined_S0_L00{wildcards.config_id.split('_')[0].replace('lane', '')}_R2_001.fastq.gz",
        raw_barcodes_abs = lambda wildcards, input: os.path.abspath(input.raw_barcodes),
        barcodes_abs = lambda wildcards: os.path.abspath(f"metadata/flexbar_barcodes_{wildcards.config_id}.fasta"),
        adapter_abs = lambda wildcards, input: os.path.abspath(input.adapter),
        r1_abs = lambda wildcards, input: os.path.abspath(f".output/{wildcards.config_id}/Undetermined_S0_L00{wildcards.config_id.split('_')[0].replace('lane', '')}_R1_001.fastq.gz"),
        flexbar_bin = FLEXBAR_BIN,
        retry_min_reads = config.get("flexbar_retry_min_reads", 1000000),
        barcode_leader = config.get("flexbar_barcode_leader_n", 0)
    shell:
        """
        (
        mkdir -p {params.outdir}

        echo "Starting Flexbar processing for {wildcards.config_id}"

        flexbar_cmd="{params.flexbar_bin}"
        if [ -z "$flexbar_cmd" ]; then
            flexbar_cmd="flexbar"
            if ! command -v "$flexbar_cmd" >/dev/null 2>&1; then
                echo "ERROR: flexbar not found in PATH and config.flexbar_bin is empty"
                exit 1
            fi
        else
            if [ ! -x "$flexbar_cmd" ]; then
                echo "ERROR: configured flexbar_bin is not executable: $flexbar_cmd"
                exit 1
            fi
        fi


        # If any assigned barcode falls below this many reads after the primary
        # run, retry with the opposite index orientation and keep whichever
        # orientation assigns the most reads overall.
        retry_min_reads={params.retry_min_reads}

        # Build the barcode FASTA from the raw tab-delimited barcodes.
        # $1 = orientation: "rc" reverse-complements each listed barcode
        # (historical default), "fwd" uses each barcode as listed. $2 = output FASTA.
        #
        # The pattern is "<lead N's><barcode>", matched at the read start (LTAIL).
        # `lead` is the number of leading bases (e.g. a UMI) before the inline
        # barcode; it comes from config.flexbar_barcode_leader_n and defaults to 0
        # because the active KY26SPI libraries carry the 6 bp index at R1 position 1
        # with no leader. A non-zero leader was only correct for the PAREseq (U5I6)
        # libraries, which have since moved to BCL Convert inline extraction.
        build_barcode_fasta() {{
            awk -F'\t' -v orient="$1" -v lead="{params.barcode_leader}" '
            NF >= 2 {{
                name = $1
                barcode = $2
                gsub(/\r/, "", name)
                gsub(/\r/, "", barcode)
                gsub(/ /, "_", name)
                gsub(/[^a-zA-Z0-9_]/, "", name)
                if (orient == "rc") {{
                    gsub(/A/, "X", barcode)
                    gsub(/T/, "A", barcode)
                    gsub(/X/, "T", barcode)
                    gsub(/C/, "Y", barcode)
                    gsub(/G/, "C", barcode)
                    gsub(/Y/, "G", barcode)
                    reversed = ""
                    for (i = length(barcode); i >= 1; i--) {{
                        reversed = reversed substr(barcode, i, 1)
                    }}
                    barcode = reversed
                }}
                leader = ""
                for (i = 0; i < lead + 0; i++) leader = leader "N"
                print ">" name
                print leader barcode
            }}
            ' {params.raw_barcodes_abs} > "$2"
        }}

        # Run flexbar with the shared arguments. $1 = barcode FASTA, $2 = target prefix.
        run_flexbar() {{
            "$flexbar_cmd" -r {params.r1_abs} -b "$1" \
                --barcode-trim-end LTAIL \
                --barcode-error-rate 0 \
                --adapters {params.adapter_abs} \
                --adapter-error-rate 0.1 \
                --adapter-min-overlap 1 \
                --adapter-trim-end RIGHT \
                --zip-output GZ \
                --barcode-unassigned \
                --min-read-length 15 \
                --umi-tags \
                --target "$2" -n {threads}
        }}

        # Emit "barcode<TAB>written_reads" for each assigned (non-unassigned)
        # barcode parsed from a flexbar log. $1 = log path.
        assigned_counts() {{
            awk '
            /Read file:/ {{
                name=$NF
                sub(/.*flexbarOut_barcode_/,"",name)
                sub(/[.]fastq[.]gz$/,"",name)
                if ($NF ~ /flexbarOut_barcode_/) cur=name; else cur=""
                next
            }}
            /written reads/ {{
                if (cur!="" && cur!="unassigned") print cur"\t"$3
                cur=""
            }}
            ' "$1"
        }}

        # Summarize a flexbar log into globals TOTAL_ASSIGNED and MAX_ASSIGNED
        # (MAX_ASSIGNED is the highest per-barcode read count, empty when no
        # assigned barcodes are present). $1 = log path.
        summarize_log() {{
            TOTAL_ASSIGNED=0
            MAX_ASSIGNED=""
            while IFS=$'\t' read -r _bc _cnt; do
                [ -n "$_cnt" ] || continue
                TOTAL_ASSIGNED=$((TOTAL_ASSIGNED + _cnt))
                if [ -z "$MAX_ASSIGNED" ] || [ "$_cnt" -gt "$MAX_ASSIGNED" ]; then
                    MAX_ASSIGNED=$_cnt
                fi
            done < <(assigned_counts "$1")
        }}

        # --- Primary run: forward (as-listed) orientation ---
        build_barcode_fasta fwd {params.barcodes_abs}
        run_flexbar {params.barcodes_abs} {params.outdir}/flexbarOut
        summarize_log {params.outdir}/flexbarOut.log
        primary_total=$TOTAL_ASSIGNED
        primary_max=$MAX_ASSIGNED
        echo "Primary (forward) orientation: total assigned=$primary_total, max per-barcode=${{primary_max:-NA}}"

        # An orientation is "good" if at least one sample exceeds the threshold.
        # If the primary orientation already has such a sample, proceed with it
        # and skip the second flexbar pass. Otherwise try the opposite orientation
        # and proceed with it if it has a sample above the threshold; if neither
        # orientation qualifies, fall back to whichever assigned the most reads.
        if [ -n "$primary_max" ] && [ "$primary_max" -gt "$retry_min_reads" ]; then
            echo "Primary orientation has a sample above ${{retry_min_reads}} reads; proceeding with it."
        else
            echo "No primary sample exceeds ${{retry_min_reads}} reads; trying the opposite index orientation."
            alt_dir={params.outdir}/_rc_alt
            alt_fasta={params.outdir}/flexbar_barcodes_alt.fasta
            rm -rf "$alt_dir"
            mkdir -p "$alt_dir"
            build_barcode_fasta rc "$alt_fasta"
            run_flexbar "$alt_fasta" "$alt_dir"/flexbarOut
            summarize_log "$alt_dir"/flexbarOut.log
            alt_total=$TOTAL_ASSIGNED
            alt_max=$MAX_ASSIGNED
            echo "Alt (RC) orientation: total assigned=$alt_total, max per-barcode=${{alt_max:-NA}}"

            adopt_alt=0
            if [ -n "$alt_max" ] && [ "$alt_max" -gt "$retry_min_reads" ]; then
                echo "Alt orientation has a sample above ${{retry_min_reads}} reads; adopting it."
                adopt_alt=1
            elif [ "${{alt_total:-0}}" -gt "${{primary_total:-0}}" ]; then
                echo "Neither orientation exceeds ${{retry_min_reads}} reads; adopting alt by higher total assigned ($alt_total > $primary_total)."
                adopt_alt=1
            else
                echo "Neither orientation exceeds ${{retry_min_reads}} reads; retaining primary forward orientation ($primary_total >= $alt_total)."
            fi

            if [ "$adopt_alt" -eq 1 ]; then
                rm -f {params.outdir}/flexbarOut*.fastq.gz {params.outdir}/flexbarOut.log
                mv "$alt_dir"/flexbarOut* {params.outdir}/
                cp "$alt_fasta" {params.barcodes_abs}
            fi
            rm -rf "$alt_dir" "$alt_fasta"
        fi

        # Drop the large unassigned FASTQ now that orientation is settled. It is
        # not needed downstream (read counts are read from the log, not the file)
        # and mirrors fqtk_per_config's removal of unmatched reads. This keeps the
        # scratch dir from accumulating tens of GB of unassigned reads.
        rm -f {params.outdir}/flexbarOut_barcode_unassigned*.fastq.gz
        ) > {log} 2>&1

        touch {output}
        """


rule flexbar_pair_r2:
    """Pull the R2 mates for each flexbar-assigned R1 and checksum the results.

    Split out of flexbar_per_config so that a failure here (e.g. a missing seqkit,
    or an OOM on the read-ID list) does not discard the hours-long demultiplexing
    pass. The R1 FASTQs and the settled orientation are already committed by the
    flexbar_demux sentinel; this rule only adds the paired R2 files.
    """
    input:
        demux_done = "results/{config_id}/flexbar_demux_{config_id}.done"
    threads: 32
    priority: 99
    output:
        touch("results/{config_id}/flexbar_{config_id}.done")
    log:
        "logs/{config_id}/flexbar_pair_r2_{config_id}.log"
    benchmark:
        "benchmarks/flexbar_pair_r2_{config_id}.bench"
    params:
        outdir = "output/{config_id}/flexbar",
        r2 = lambda wildcards: f".output/{wildcards.config_id}/Undetermined_S0_L00{wildcards.config_id.split('_')[0].replace('lane', '')}_R2_001.fastq.gz"
    shell:
        """
        (
        # Recover the R2 mates in a single pass over R2. The previous approach ran
        # `seqkit grep` once per barcode, re-reading the whole 32 GB / 417M-read R2
        # file every time (6 passes) and holding a 40M+ entry ID hash in memory.
        # pair_r2_stream.py exploits flexbar's order-preserving output to merge-walk
        # R2 against the per-barcode R1 streams in one pass with O(1) memory, and
        # produces byte-identical output.
        python3 src/flexbar/pair_r2_stream.py \
            --r2 "{params.r2}" \
            --outdir "{params.outdir}" \
            --threads {threads}

        curr_dir=$PWD
        cd {params.outdir}
        md5sum *.fastq.gz > md5sum.txt
        count=$(wc -l < md5sum.txt)
        echo "Generated md5sum.txt with $count entries for {wildcards.config_id}"
        if [ "$count" -eq 0 ]; then
            echo "ERROR: md5sum.txt is empty, no .fastq.gz files found in {params.outdir}" >&2
            exit 1
        fi
        du -h *.fastq.gz > size.txt
        cd $curr_dir
        ) > {log} 2>&1

        touch {output}
        """

def _make_flexbar_stage_constraints():
    if not FLEXBAR_CONFIG_RENAMING_MAP:
        return "NOMATCH", "NOMATCH"
    cfg = "|".join(re.escape(fc) for fc in FLEXBAR_CONFIG_RENAMING_MAP)
    projs = "|".join(
        re.escape(PROJECT_RENAME_MAP.get((fc, FLEXBAR_ORDER_ID_PROJECT[fc]), FLEXBAR_ORDER_ID_PROJECT[fc]))
        for fc in FLEXBAR_CONFIG_RENAMING_MAP
        if fc in FLEXBAR_ORDER_ID_PROJECT
    )
    return cfg, projs or "NOMATCH"
_FLEXBAR_STAGE_CONFIG_CONSTRAINT, _FLEXBAR_STAGE_PROJECT_CONSTRAINT = _make_flexbar_stage_constraints()

rule flexbar_stage_project:
    """Stage flexbar-demuxed files into per-project directory with canonical names.

    Moves flexbarOut_barcode_{name}.fastq.gz files into the renamed project directory
    as {stem}-R1/2.fastq.gz. Writes .project_done / .fastq_names_done sentinels so
    downstream rules (calculate_md5sums, fastp_sample, project_link) treat this like
    a normal project.
    """
    input:
        done = "results/{config_id}/flexbar_{config_id}.done"
    output:
        project_done = "output/{config_id}/{project}/.project_done",
        names_done   = "output/{config_id}/{project}/.fastq_names_done"
    log:
        "logs/{config_id}/flexbar_stage_project_{config_id}_{project}.log"
    wildcard_constraints:
        config_id = _FLEXBAR_STAGE_CONFIG_CONSTRAINT,
        project   = _FLEXBAR_STAGE_PROJECT_CONSTRAINT
    run:
        import os
        import shutil
        config_id = wildcards.config_id
        project   = wildcards.project
        rows      = FLEXBAR_CONFIG_RENAMING_MAP.get(config_id, [])
        proj_dir  = f"output/{config_id}/{project}"
        os.makedirs(proj_dir, exist_ok=True)
        log_lines = [f"Staging flexbar project {project} for {config_id}\n"]

        def _move_fastq(src_abs, dst_abs):
            if os.path.exists(dst_abs):
                log_lines.append(f"Kept existing {dst_abs}\n")
                return
            try:
                os.rename(src_abs, dst_abs)
                log_lines.append(f"Moved {src_abs} -> {dst_abs}\n")
            except OSError:
                shutil.move(src_abs, dst_abs)
                log_lines.append(f"Moved (cross-device) {src_abs} -> {dst_abs}\n")

        for row in rows:
            name    = row['Sample_Name']
            run     = row['Run']
            lane    = row['Lane']
            group   = str(row['Group'])
            pos     = row['Position']
            barcode = row['index']
            stem    = f"{run}-L{lane}-G{group}-{pos}-{barcode}"
            src_r1  = os.path.abspath(f"output/{config_id}/flexbar/flexbarOut_barcode_{name}.fastq.gz")
            dst_r1  = os.path.abspath(f"{proj_dir}/{stem}-R1.fastq.gz")
            if os.path.exists(src_r1):
                _move_fastq(src_r1, dst_r1)
            if NUM_READS > 1:
                src_r2 = os.path.abspath(f"output/{config_id}/flexbar/flexbarOut_barcode_{name}_R2.fastq.gz")
                dst_r2 = os.path.abspath(f"{proj_dir}/{stem}-R2.fastq.gz")
                if os.path.exists(src_r2):
                    _move_fastq(src_r2, dst_r2)

        # Sweep the flexbar scratch dir of any remaining FASTQs so demuxed reads
        # live only in the project dir. This removes the unassigned file (if the
        # demux rule kept one) and any orphans left by an interrupted or re-run
        # flexbar pass (e.g. stranded _rc_alt scratch from the orientation retry).
        # Logs and metadata (flexbarOut.log, size.txt, md5sum.txt) are preserved
        # for the report rules.
        flex_dir = os.path.abspath(f"output/{config_id}/flexbar")
        alt_dir  = os.path.join(flex_dir, "_rc_alt")
        if os.path.isdir(alt_dir):
            shutil.rmtree(alt_dir, ignore_errors=True)
            log_lines.append(f"Removed stale scratch dir {alt_dir}\n")
        if os.path.isdir(flex_dir):
            for fname in os.listdir(flex_dir):
                if fname.endswith(".fastq.gz"):
                    fpath = os.path.join(flex_dir, fname)
                    try:
                        os.remove(fpath)
                        log_lines.append(f"Removed leftover scratch FASTQ {fpath}\n")
                    except OSError as exc:
                        log_lines.append(f"Could not remove {fpath}: {exc}\n")

        with open(log[0], 'w') as lf:
            lf.writelines(log_lines)
        with open(output.project_done, 'w') as f:
            f.write("flexbar project staged\n")
        with open(output.names_done, 'w') as f:
            f.write("flexbar canonical names done\n")


def _make_fqtk_stage_constraints():
    if not FQTK_CONFIG_RENAMING_MAP:
        return "NOMATCH", "NOMATCH"
    cfg = "|".join(re.escape(fc) for fc in FQTK_CONFIG_RENAMING_MAP)
    projs = "|".join(
        re.escape(PROJECT_RENAME_MAP.get((fc, FQTK_ORDER_ID_PROJECT[fc]), FQTK_ORDER_ID_PROJECT[fc]))
        for fc in FQTK_CONFIG_RENAMING_MAP
        if fc in FQTK_ORDER_ID_PROJECT
    )
    return cfg, projs or "NOMATCH"
_FQTK_STAGE_CONFIG_CONSTRAINT, _FQTK_STAGE_PROJECT_CONSTRAINT = _make_fqtk_stage_constraints()


rule fqtk_per_config:
    """Demultiplex SMK/fqtk samples from a lane's Undetermined reads using fqtk.

    Reads Undetermined R1/I1/R2 from .output/{config_id}/, probes I1 length to
    determine the read structure, and runs fqtk demux with the barcode TSV from
    metadata/fqtk_barcodes_{config_id}.tsv.  Outputs to output/{config_id}/fqtk/.
    """
    input:
        bcl_done    = ".output/{config_id}/.done",
        barcode_tsv = "metadata/fqtk_barcodes_{config_id}.tsv"
    output:
        touch("results/{config_id}/fqtk_{config_id}.done")
    log:
        "logs/{config_id}/fqtk_{config_id}.log"
    benchmark:
        "benchmarks/fqtk_per_config_{config_id}.bench"
    params:
        outdir  = "output/{config_id}/fqtk",
        lane    = lambda wildcards: wildcards.config_id.replace('lane', ''),
        lane_pad = lambda wildcards: f"{int(wildcards.config_id.replace('lane', '')):03d}",
        r1      = lambda wildcards: f".output/{wildcards.config_id}/Undetermined_S0_L{int(wildcards.config_id.replace('lane', '')):03d}_R1_001.fastq.gz",
        i1      = lambda wildcards: f".output/{wildcards.config_id}/Undetermined_S0_L{int(wildcards.config_id.replace('lane', '')):03d}_I1_001.fastq.gz",
        r2      = lambda wildcards: f".output/{wildcards.config_id}/Undetermined_S0_L{int(wildcards.config_id.replace('lane', '')):03d}_R2_001.fastq.gz",
    shell:
        """
        (
        mkdir -p {params.outdir}

        R1="{params.r1}"
        I1="{params.i1}"
        R2="{params.r2}"

        for f in "$R1" "$I1" "$R2"; do
            if [ ! -f "$f" ]; then
                echo "ERROR: expected Undetermined file not found: $f"
                echo "  Ensure Pass-1 BCL Convert ran with CreateFastqForIndexReads=1."
                exit 1
            fi
        done

        # Probe I1 read length to build the correct read structure.
        I1_LEN=$(set +o pipefail; zcat "$I1" | awk 'NR==2{{print length($0); exit}}')
        if [ "$I1_LEN" -ge 10 ]; then
            I1_READ_STRUCT="8B$(( I1_LEN - 8 ))S"
        else
            I1_READ_STRUCT="8B"
        fi
        echo "I1 read length: ${{I1_LEN}}bp -> read structure: $I1_READ_STRUCT"

        fqtk demux \
            --inputs "$R1" "$I1" "$R2" \
            --read-structures "151T" "$I1_READ_STRUCT" "151T" \
            --sample-metadata {input.barcode_tsv} \
            --output {params.outdir} \
            --max-mismatches 1 \
            --min-mismatch-delta 2

        echo "fqtk demux complete"
        cat "{params.outdir}/demux-metrics.txt" 2>/dev/null || true

        # Remove unmatched reads — not needed downstream and can be large.
        rm -f "{params.outdir}"/unmatched.*.fq.gz

        curr_dir=$PWD
        cd {params.outdir}
        md5sum *.fq.gz > md5sum.txt 2>/dev/null || true
        du -h *.fq.gz > size.txt 2>/dev/null || true
        cd "$curr_dir"
        ) > {log} 2>&1

        touch {output}
        """


rule fqtk_stage_project:
    """Stage fqtk-demuxed files into per-project directory with canonical names.

    BD/10x projects get DRAGEN-style names: {sample}_S{n}_L{lane:03d}_R1_001.fastq.gz
    Other projects get stem-based names: {stem}-R1.fastq.gz (same as flexbar).
    Writes .project_done and .fastq_names_done sentinels.
    """
    input:
        done = "results/{config_id}/fqtk_{config_id}.done"
    output:
        project_done = "output/{config_id}/{project}/.project_done",
        names_done   = "output/{config_id}/{project}/.fastq_names_done"
    log:
        "logs/{config_id}/fqtk_stage_project_{config_id}_{project}.log"
    wildcard_constraints:
        config_id = _FQTK_STAGE_CONFIG_CONSTRAINT,
        project   = _FQTK_STAGE_PROJECT_CONSTRAINT
    run:
        import os
        import shutil
        config_id = wildcards.config_id
        project   = wildcards.project
        rows      = FQTK_CONFIG_RENAMING_MAP.get(config_id, [])
        proj_dir  = f"output/{config_id}/{project}"
        os.makedirs(proj_dir, exist_ok=True)
        log_lines = [f"Staging fqtk project {project} for {config_id}\n"]

        def _materialize_and_backlink(src_abs, dst_abs):
            if os.path.lexists(dst_abs) and os.path.islink(dst_abs):
                os.unlink(dst_abs)
            if not os.path.exists(dst_abs):
                try:
                    os.link(src_abs, dst_abs)
                    log_lines.append(f"Hardlinked {dst_abs} <- {src_abs}\n")
                except Exception:
                    shutil.copy2(src_abs, dst_abs)
                    log_lines.append(f"Copied {src_abs} -> {dst_abs}\n")
            else:
                log_lines.append(f"Kept existing destination {dst_abs}\n")
            if os.path.lexists(src_abs):
                try:
                    if os.path.islink(src_abs):
                        if os.path.realpath(src_abs) == os.path.realpath(dst_abs):
                            return
                    os.unlink(src_abs)
                except Exception:
                    pass
            os.symlink(os.path.abspath(dst_abs), src_abs)
            log_lines.append(f"Linked {src_abs} -> {dst_abs}\n")

        # Resolve original project name (before rename) to check is_parse_or_10x
        project_orig = rows[0].get('Sample_Project', project) if rows else project

        # Compute global S-number offset: count BCL Convert rows for this config
        # so fqtk samples continue the numbering (e.g. BCL=84 rows → fqtk gets S85, S86)
        import pandas as _pd
        _map_path = f"results/{config_id}/renaming_map_{config_id}.csv"
        _s_num_offset = 0
        if os.path.exists(_map_path):
            try:
                _s_num_offset = len(_pd.read_csv(_map_path))
            except Exception:
                pass

        for _fqtk_i, row in enumerate(rows):
            name    = row['Sample_Name']
            run     = row['Run']
            lane    = int(row['Lane'])
            group   = str(row['Group'])
            pos     = row['Position']
            barcode = row['index']
            s_num   = _s_num_offset + _fqtk_i + 1
            src_r1  = os.path.abspath(f"output/{config_id}/fqtk/{name}.R1.fq.gz")
            src_r2  = os.path.abspath(f"output/{config_id}/fqtk/{name}.R2.fq.gz")
            if is_parse_or_10x(project_orig):
                dst_r1 = os.path.abspath(f"{proj_dir}/{name}_S{s_num}_L{lane:03d}_R1_001.fastq.gz")
                dst_r2 = os.path.abspath(f"{proj_dir}/{name}_S{s_num}_L{lane:03d}_R2_001.fastq.gz")
            else:
                stem   = f"{run}-L{lane}-G{group}-{pos}-{barcode}"
                dst_r1 = os.path.abspath(f"{proj_dir}/{stem}-R1.fastq.gz")
                dst_r2 = os.path.abspath(f"{proj_dir}/{stem}-R2.fastq.gz")
            if os.path.exists(src_r1) or os.path.islink(src_r1):
                _materialize_and_backlink(src_r1, dst_r1)
            if os.path.exists(src_r2) or os.path.islink(src_r2):
                _materialize_and_backlink(src_r2, dst_r2)
        with open(log[0], 'w') as lf:
            lf.writelines(log_lines)
        with open(output.project_done, 'w') as f:
            f.write("fqtk project staged\n")
        with open(output.names_done, 'w') as f:
            f.write("fqtk canonical names done\n")


rule generate_samplesheets:
    input:
        metadata = METADATA_FILE if METADATA_FILE else [],
        run_info = "src/RunInfo_nn.xml"
    output:
        expand("results/{config_id}/SampleSheet_{config_id}.csv", config_id=CONFIG_IDS),
        expand("logs/{config_id}/generate_samplesheets_{config_id}.done", config_id=CONFIG_IDS)
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
            samplesheet_path = f"results/{config_id}/SampleSheet_{config_id}.csv"
            done_marker = f"logs/{config_id}/generate_samplesheets_{config_id}.done"
            
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
                done_marker = f"logs/{config_id}/generate_samplesheets_{config_id}.done"
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
                samplesheet_path = f"results/{config_id}/SampleSheet_{config_id}.csv"
                done_marker = f"logs/{config_id}/generate_samplesheets_{config_id}.done"
                
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
                samplesheet_path = f"results/{config_id}/SampleSheet_{config_id}.csv"
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
                samplesheet_path = f"results/{config_id}/SampleSheet_{config_id}.csv"
                done_marker = f"logs/{config_id}/generate_samplesheets_{config_id}.done"
                
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
                        # Content changed, update done marker and invalidate stale validated sheet
                        os.makedirs(os.path.dirname(done_marker), exist_ok=True)
                        open(done_marker, 'w').close()
                        print(f"Updated done marker for {config_id} (content changed)")
                        for stale in [
                            f"results/{config_id}/SampleSheet_{config_id}_validated.csv",
                            f"logs/{config_id}/barcode_hamming_validation_{config_id}.done",
                            f"logs/{config_id}/barcode_hamming_validation_{config_id}.txt",
                        ]:
                            if os.path.exists(stale):
                                os.remove(stale)
                                print(f"Removed stale validation artifact: {stale}")
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
                samplesheet_path = f"results/{config_id}/SampleSheet_{config_id}.csv"
                done_marker = f"logs/{config_id}/generate_samplesheets_{config_id}.done"
                
                os.makedirs(os.path.dirname(samplesheet_path), exist_ok=True)
                open(samplesheet_path, 'w').close()
                
                os.makedirs(os.path.dirname(done_marker), exist_ok=True)
                open(done_marker, 'w').close()



# Generate renaming map by copying from generate_samplesheets output
rule generate_renaming_map:
    input:
        sample_sheet = "results/{config_id}/SampleSheet_{config_id}.csv"
    output:
        map = "results/{config_id}/renaming_map_{config_id}.csv"
    log:
        "logs/{config_id}/generate_renaming_map_{config_id}.log"
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

        def _finish():
            """If this lane is flagged in report_undetermined_configs, append an
            'Undetermined' pseudo-sample row so the lane's Undetermined reads flow
            through the standard pipeline (fastp, read counts, md5sums, report) as
            a normal sample. Attached to the lane's first (alphabetical) project.
            Idempotent and gated by REPORT_UNDETERMINED_CONFIGS, so default runs
            are unaffected.
            """
            if wildcards.config_id not in REPORT_UNDETERMINED_CONFIGS:
                return
            if not os.path.exists(output.map):
                return
            try:
                cur = pd.read_csv(output.map)
            except Exception as e:
                print(f"Undetermined injection: could not read {output.map}: {e}")
                return

            _names = cur.get("Sample_Name")
            if _names is not None and (_names.astype(str).str.strip() == "Undetermined").any():
                print("Undetermined row already present; skipping injection.")
                return

            _proj_col = cur["Sample_Project"].astype(str).str.strip()
            _real = cur[_proj_col.ne("") & _proj_col.str.lower().ne("nan")]
            if _real.empty:
                print("No real project rows; skipping Undetermined injection.")
                return

            first_project = sorted(_real["Sample_Project"].astype(str).str.strip().unique())[0]
            owner = _real[_real["Sample_Project"].astype(str).str.strip() == first_project].iloc[0]

            new_row = {col: "" for col in cur.columns}
            new_row.update({
                "Sample_Name": "Undetermined",
                "Sample_Project": first_project,
                "Lane": owner.get("Lane", ""),
                "index": "Undetermined",
                "index2": "",
                "Run": params.library,
                "Group": owner.get("Group", ""),
                "Position": f"P{len(cur) + 1:03d}",
            })
            if "Sample_ID" in cur.columns:
                new_row["Sample_ID"] = "Undetermined"

            cur = pd.concat([cur, pd.DataFrame([new_row])], ignore_index=True)
            cur.to_csv(output.map, index=False)
            print(
                f"Injected Undetermined row into {output.map} "
                f"(project={first_project}, lane={owner.get('Lane')}, group={owner.get('Group')})"
            )

        # If map already exists and looks valid, keep it
        if has_required_columns(output.map):
            print(f"Renaming map already valid: {output.map}")
            _finish()
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
                    _finish()
                    return
            except Exception as e:
                print(f"Error regenerating renaming map from metadata: {e}")

        # Fallback: derive from SampleSheet data section
        build_map_from_samplesheet(input.sample_sheet, output.map, params.library)
        _finish()

rule validate_barcode_hamming_distances:
    """Pre-flight validation: check barcode Hamming distances for a single config_id.
    Runs per-lane so re-running one lane's validation does not invalidate others.
    With --fix: sets BarcodeMismatchesIndex1/2 to 0 for conflicting samples and retries.
    """
    input:
        samplesheet = maybe_ancient("results/{config_id}/SampleSheet_{config_id}.csv")
    output:
        report = "logs/{config_id}/barcode_hamming_validation_{config_id}.txt",
        marker = touch("logs/{config_id}/barcode_hamming_validation_{config_id}.done"),
        fixed_sheet = "results/{config_id}/SampleSheet_{config_id}_validated.csv"
    log:
        "logs/{config_id}/barcode_hamming_validation_{config_id}.log"
    benchmark:
        "benchmarks/barcode_hamming_validation_{config_id}.bench"
    wildcard_constraints:
        config_id = VALIDATE_CONFIG_ID_PATTERN
    params:
        script = "scripts/validate_barcode_hamming_distance.py",
        tolerance = 1
    shell:
        """
        (
        echo "Validating barcode Hamming distances for {wildcards.config_id}..."
        python3 {params.script} \
            --samplesheets {input.samplesheet} \
            --mismatch-tolerance {params.tolerance} \
            --output {output.report} \
            --output-sheet {output.fixed_sheet} \
            --fix

        exit_code=$?
        if [ $exit_code -ne 0 ]; then
            echo ""
            echo "=========================================================="
            echo "ERROR: Barcode Hamming distance validation FAILED for {wildcards.config_id} (after auto-fix attempt)"
            echo "=========================================================="
            echo ""
            cat {output.report}
            exit 1
        fi
        ) > {log} 2>&1
        """

rule bcl_convert:
    input:
        sample_sheet=lambda wildcards: f"results/{wildcards.config_id}/SampleSheet_{wildcards.config_id}_validated.csv",
        renaming_map = maybe_ancient("results/{config_id}/renaming_map_{config_id}.csv"),
        data_dir=DATA_DIR,
        _sheet_done=lambda wildcards: maybe_ancient(f"logs/{wildcards.config_id}/generate_samplesheets_{wildcards.config_id}.done"),
        run_info = "src/RunInfo_nn.xml",
        prev_done = get_prev_bcl_done
    output:
        done_file = touch(".output/{config_id}/.done")
    log:
        "logs/{config_id}/bcl_convert_{config_id}.log"
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
        scratch_dir = SCRATCH_DIR,
        keep_undetermined_configs = KEEP_UNDETERMINED_CONFIGS
    shell:
        """
        (
        cleanup() {{
            pkill -P $$ 2>/dev/null || true
        }}
        trap cleanup INT TERM

        run_dragen() {{
            local sample_sheet_path="$1"
            timeout 7200 dragen --bcl-conversion-only true \
            --bcl-input-directory {input.data_dir} \
            --output-directory "$dragen_out" \
            --force \
            --bcl-sampleproject-subdirectories true \
            --sample-sheet "$sample_sheet_path" \
            --strict-mode false \
            --bcl-only-lane {params.lane} \
            --run-info {params.run_info_path} \
            --bcl-num-parallel-tiles 1 \
            --bcl-num-conversion-threads 8 \
            --bcl-num-compression-threads 8 \
            --bcl-num-decompression-threads 8 \
            $tiles_arg
        }}

        # Masking is now handled by OverrideCycles in the sample sheet

        tiles_arg=""
        if [ ! -z "{params.tiles}" ]; then
            tiles_arg="--tiles {params.tiles}"
        fi

        final_out=".output/{wildcards.config_id}"
        if [ ! -z "{params.scratch_dir}" ]; then
            dragen_out="{params.scratch_dir}/{wildcards.config_id}"
        else
            dragen_out="$final_out"
        fi

        find "$dragen_out" -name "*.fastq.gz" -delete 2>/dev/null || true
        mkdir -p "$dragen_out"

        run_dragen {input.sample_sheet}

        dragen_status=$?
        if [ $dragen_status -ne 0 ]; then
            cleanup
            exit $dragen_status
        fi

        if [ ! -z "{params.scratch_dir}" ]; then
            echo "Syncing from scratch to output with checksum verification..."
            mkdir -p "$final_out"
            sync_ok=false
            for attempt in 1 2 3; do
                if rsync -aW --delete "$dragen_out/" "$final_out/"; then
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

        # Keep Undetermined reads if config is in keep_undetermined_configs or flexbar file exists.
        keep_undetermined=false
        echo "DEBUG keep_undetermined_configs='{params.keep_undetermined_configs}' config_id='{wildcards.config_id}'"
        _keep_configs="{params.keep_undetermined_configs}"
        for cfg in $_keep_configs; do
            if [ "$cfg" = "{wildcards.config_id}" ]; then
                keep_undetermined=true
                break
            fi
        done
        
        if [ -f "metadata/flexbar_barcodes_{wildcards.config_id}.txt" ]; then
            echo "Inline demux lane detected; preserving Undetermined reads."
            keep_undetermined=true
        fi

        if [ -f "metadata/fqtk_barcodes_{wildcards.config_id}.tsv" ]; then
            echo "fqtk demux lane detected; preserving Undetermined reads."
            keep_undetermined=true
        fi
        
        if [ "$keep_undetermined" = "true" ]; then
            echo "Keeping Undetermined reads for {wildcards.config_id}."
        else
            find "$final_out" -name "Undetermined*" -delete
            echo "Undetermined reads deleted"
        fi
        # Rename FASTQ files
        src/run_rename.sh {wildcards.config_id} "$final_out" {input.renaming_map}

        trap - INT TERM
        touch {output.done_file}
        ) > {log} 2>&1
        """

rule bcl_project_done:
    """Per-project sentinel created after bcl_convert completes.

    Uses ancient() on the lane .done so that re-running bcl_convert for one
    project does NOT re-trigger downstream rules for projects whose
    .project_done already exists.

    If a rename map entry exists for this project, renames the bcl_convert
    output directory from the old Sample_Project name to the new
    {LabID}_{OrderID}_{library}_L{lane}_G{group} name, then creates a
    symlink from old name -> new directory for downstream compatibility.

    If an orientation_decision file exists for this config_id (written by
    pick_orientation after comparing first-pass vs RC-pass demux stats), reads
    it to determine whether to source FASTQs from .output (original) or
    .output_rc (reverse-complement) for this project.
    """
    input:
        done = maybe_ancient(".output/{config_id}/.done"),
        decision = maybe_ancient("logs/{config_id}/orientation_decision_{config_id}.json"),
        # CONFIG_PROJECT_PAIRS is derived from this map at Snakefile parse time, and each
        # job is parsed fresh in its own spawned subprocess. Without this dependency the
        # rule can run before the map exists, leaving the lane's project list empty.
        renaming_map = maybe_ancient("results/{config_id}/renaming_map_{config_id}.csv")
    output:
        sentinel = touch("output/{config_id}/{project}/.project_done")
    wildcard_constraints:
        config_id = "[^/]+",
        project = "[^/]+"
    log:
        "logs/{config_id}/bcl_project_done_{config_id}_{project}.log"
    run:
        import os, glob, shutil, json as json_mod

        _logf = open(log[0], "w")
        def _plog(msg):
            print(msg, file=_logf, flush=True)
        config_id = wildcards.config_id
        new_project = wildcards.project
        old_project = PROJECT_RENAME_MAP_INV.get((config_id, new_project), new_project)

        # Determine which orientation won for this project
        orientation = "original"
        try:
            with open(input.decision) as _df:
                _dec = json_mod.load(_df)
            orientation = _dec.get(old_project, _dec.get(new_project, "original"))
        except Exception:
            pass

        src_base = ".output_rc" if orientation.startswith("rc") else ".output"
        src_dir = os.path.abspath(f"{src_base}/{config_id}/{old_project}")
        new_dir = os.path.abspath(f"output/{config_id}/{new_project}")

        # Move project FASTQs from staging dir to final output dir.
        if os.path.isdir(src_dir):
            # Snakemake pre-creates the output dir; remove if empty so shutil.move works.
            if os.path.isdir(new_dir) and not os.listdir(new_dir):
                os.rmdir(new_dir)
            if not os.path.exists(new_dir):
                shutil.move(src_dir, new_dir)
            else:
                # new_dir already exists and is non-empty (e.g. stale placeholder stubs).
                # Move individual files from src_dir into new_dir, overwriting placeholders.
                for _fname in os.listdir(src_dir):
                    _src_f = os.path.join(src_dir, _fname)
                    _dst_f = os.path.join(new_dir, _fname)
                    if os.path.isfile(_src_f):
                        if os.path.exists(_dst_f):
                            os.remove(_dst_f)
                        shutil.move(_src_f, _dst_f)

        os.makedirs(new_dir, exist_ok=True)

        # Copy lane-level accessory files (Reports, Logs, dragen JSONs, etc.) to output.
        # Only the first project (alphabetically) performs the bulk copy to avoid concurrent
        # bcl_project_done jobs racing on large lane-level dirs. The demultiplex Reports,
        # however, are critical for read-count summaries, so EVERY project self-heals them
        # if missing — this guards against the bulk copy having run before the RC pass
        # populated its Reports/, or having failed silently (previously the .project_done
        # sentinel was touched regardless, leaving empty read_counts for the whole lane).
        dest_base = f"output/{config_id}"
        dest_reports = os.path.join(dest_base, "Reports")
        dest_stats = os.path.join(dest_reports, "Demultiplex_Stats.csv")
        os.makedirs(dest_base, exist_ok=True)

        # Choose the staging dir for the lane-level Reports. When any project on this lane
        # selected RC orientation, the RC pass (which flips only the suspect projects'
        # indexes) is authoritative for the WHOLE lane, so use .output_rc exclusively —
        # falling back to .output here would republish the wrong-orientation zero counts
        # that this hardening exists to prevent. The verification below turns a missing
        # RC Reports into a retryable failure rather than silent bad data.
        try:
            _rc_won = any(v.startswith("rc") for v in _dec.values())
        except Exception:
            _rc_won = False
        accessory_base = ".output_rc" if _rc_won else ".output"
        staging = f"{accessory_base}/{config_id}"
        _plog(f"RC won for lane: {_rc_won}; accessory source: {staging}")

        old_project_dirs = {p for cid, p in _CONFIG_PROJECT_PAIRS_RAW if cid == config_id}
        all_lane_projects = sorted([p for cid, p in CONFIG_PROJECT_PAIRS if cid == config_id])

        # Fail closed. Electing every project primary when the lane list is unavailable
        # makes all of the lane's concurrent bcl_project_done jobs bulk-copy the same
        # staging dir while each moves its own project dir out of it, and the copiers
        # crash on the vanishing directories.
        if new_project not in all_lane_projects:
            _plog(
                f"ERROR: {new_project} not in project list for {config_id} "
                f"(found {all_lane_projects})"
            )
            _logf.close()
            raise RuntimeError(
                f"Cannot determine the primary accessory copier for {config_id}: "
                f"{new_project} is absent from the lane's project list "
                f"({all_lane_projects or 'empty'}). Verify that "
                f"results/{config_id}/renaming_map_{config_id}.csv exists and lists it."
            )
        is_primary_copier = new_project == all_lane_projects[0]

        # Bulk accessory copy (primary project only). Skip old Sample_Project subdirs —
        # those are moved by their own bcl_project_done.
        if is_primary_copier and os.path.isdir(staging):
            _plog(f"Primary copier for lane; copying accessory files from {staging}")
            for item in os.listdir(staging):
                if item.startswith('.'):
                    continue
                src_item = os.path.join(staging, item)
                dst_item = os.path.join(dest_base, item)
                if os.path.isdir(src_item) and item in old_project_dirs:
                    continue  # handled by that project's bcl_project_done
                if os.path.isdir(src_item):
                    # Force-overwrite so RC-corrected Demultiplex_Stats and summaries
                    # replace any stale copy previously written from .output.
                    shutil.copytree(src_item, dst_item, dirs_exist_ok=True)
                else:
                    shutil.copy2(src_item, dst_item)

        # Self-heal: guarantee the demultiplex Reports landed regardless of which project
        # ran the bulk copy or in what order. Idempotent; the critical stats file is written
        # atomically (temp + os.replace) so concurrent self-healers never expose a torn file.
        src_reports = os.path.join(staging, "Reports")
        if not os.path.isfile(dest_stats) and os.path.isdir(src_reports):
            _plog(f"Self-healing missing Reports for {config_id} from {src_reports}")
            shutil.copytree(src_reports, dest_reports, dirs_exist_ok=True)
            src_stats = os.path.join(src_reports, "Demultiplex_Stats.csv")
            if os.path.isfile(src_stats):
                _tmp = f"{dest_stats}.tmp.{os.getpid()}"
                shutil.copy2(src_stats, _tmp)
                os.replace(_tmp, dest_stats)

        # Fail loudly instead of silently touching the .project_done sentinel: an empty
        # demux stats file would otherwise yield zero read counts for every sample on the
        # lane. Raising leaves the sentinel uncreated so the next run retries this rule.
        if not os.path.isfile(dest_stats):
            _plog(f"ERROR: {dest_stats} still missing after accessory copy")
            _logf.close()
            raise RuntimeError(
                f"Demultiplex_Stats.csv missing for {config_id} after accessory copy "
                f"(staging={staging}); refusing to mark {new_project} done. Verify that "
                f"{staging}/Reports/Demultiplex_Stats.csv exists."
            )
        _plog(f"Verified {dest_stats} present.")
        _logf.close()

        # Remove extraneous I1/I2 FASTQs for projects that don't need index reads.
        # CreateFastqForIndexReads is set globally per lane, so these files are produced
        # for all projects whenever any project on the lane (e.g. SMK) requires them.
        # When no_demux is set the index reads are the point of the run (DRAGEN emits
        # them as FASTQs instead of index-based demultiplexing), so keep them for every
        # project rather than stripping them here.
        _INDEX_READ_KEYWORDS = ["10x", "BD", "parse", "Parse", "SMK", "smk", "CITE", "cite", "Hashtag", "hashtag"]
        check_name = old_project if old_project else new_project
        if not NO_DEMUX and not any(kw in check_name for kw in _INDEX_READ_KEYWORDS):
            proj_dir = f"output/{config_id}/{new_project}"
            removed = 0
            for pattern in ["**/*-I1.fastq.gz", "**/*-I2.fastq.gz"]:
                for f in glob.glob(os.path.join(proj_dir, pattern), recursive=True):
                    os.remove(f)
                    removed += 1
            if removed:
                print(f"Removed {removed} index FASTQ file(s) from {proj_dir}")

rule check_low_reads:
    """Send an alert email if any sample in a project has zero or low reads after bcl_project_done.

    Reads Demultiplex_Stats.csv for the config_id and flags any sample belonging
    to this project whose read count is below LOW_READS_THRESHOLD.  The sentinel
    is always created so the pipeline is never blocked; the email is optional.
    """
    input:
        project_done = "output/{config_id}/{project}/.project_done"
    output:
        sentinel = touch("output/{config_id}/{project}/.low_reads_checked")
    wildcard_constraints:
        config_id = "[^/]+",
        project   = "[^/]+"
    priority: 99
    params:
        sender    = EMAIL_SENDER,
        receiver  = EMAIL_RECIPIENT,
        cc        = EMAIL_CC,
        threshold = LOW_READS_THRESHOLD,
        library   = LIBRARY,
    log:
        "logs/{config_id}/check_low_reads_{config_id}_{project}.log"
    run:
        import os, subprocess, sys
        import pandas as pd

        config_id = wildcards.config_id
        project   = wildcards.project
        threshold = int(params.threshold)

        log_fh = open(log[0], "w")
        def _log(msg):
            print(msg, file=log_fh, flush=True)

        demux_path = os.path.join("output", config_id, "Reports", "Demultiplex_Stats.csv")
        if not os.path.exists(demux_path):
            _log(f"Demultiplex_Stats.csv not found at {demux_path}; skipping low-reads check.")
            log_fh.close()
        else:
            try:
                df = pd.read_csv(demux_path)
            except Exception as e:
                _log(f"Could not read {demux_path}: {e}")
                log_fh.close()
            else:
                # Accept both old Sample_Project and new-name project
                target_projects = {project}
                for (cid, old_p), new_p in PROJECT_RENAME_MAP.items():
                    if cid == config_id:
                        if old_p == project:
                            target_projects.add(new_p)
                        elif new_p == project:
                            target_projects.add(old_p)

                if "Sample_Project" not in df.columns or "# Reads" not in df.columns:
                    _log(f"Expected columns missing in {demux_path}; skipping.")
                    log_fh.close()
                else:
                    proj_rows = df[df["Sample_Project"].astype(str).isin(target_projects)].copy()
                    proj_rows["_reads"] = pd.to_numeric(proj_rows["# Reads"], errors="coerce").fillna(0).astype(int)
                    low = proj_rows[proj_rows["_reads"] < threshold]

                    if low.empty:
                        _log(f"All samples in {project} ({config_id}) have >= {threshold} reads. No alert needed.")
                        log_fh.close()
                    else:
                        lines = []
                        for _, row in low.iterrows():
                            sid   = str(row.get("SampleID", row.get("Sample_ID", "unknown"))).strip()
                            reads = int(row["_reads"])
                            lines.append(f"  {sid}: {reads:,} reads")
                        sample_list = "\n".join(lines)
                        all_zero = (low["_reads"] == 0).all()
                        severity  = "ZERO" if all_zero else "LOW"
                        n_affected = len(low)
                        n_total    = len(proj_rows)

                        subject = (
                            f"[{severity} READS] {params.library} — {project} ({config_id}): "
                            f"{n_affected}/{n_total} sample(s) below {threshold:,} reads"
                        )
                        body = (
                            f"Low-reads alert for library {params.library}\n\n"
                            f"Config:  {config_id}\n"
                            f"Project: {project}\n"
                            f"Threshold: {threshold:,} reads\n\n"
                            f"{n_affected} of {n_total} sample(s) are below threshold:\n"
                            f"{sample_list}\n\n"
                            f"Please review the demultiplex report at:\n"
                            f"  output/{config_id}/Reports/Demultiplex_Stats.csv\n"
                        )
                        _log(f"Sending {severity} READS alert for {n_affected} sample(s):\n{sample_list}")
                        try:
                            result = subprocess.run(
                                [
                                    "python3", "src/send_email.py",
                                    params.sender, params.receiver, subject, body,
                                    "none", params.cc,
                                ],
                                capture_output=True, text=True
                            )
                            _log(result.stdout)
                            if result.returncode != 0:
                                _log(f"Warning: email send returned exit code {result.returncode}:\n{result.stderr}")
                            else:
                                _log("Alert email sent successfully.")
                        except Exception as e:
                            _log(f"Warning: failed to send alert email: {e}")
                        log_fh.close()

rule calculate_md5sums:
    input:
        done = "output/{config_id}/{project}/.fastq_names_done"
    output:
        md5 = "output/{config_id}/{project}/md5sums.txt"
    log:
        "logs/{config_id}/calculate_md5sums_{config_id}_{project}.log"
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
        find . -name '*.fastq.gz' \\( -type f -o -type l \\) -print0 | xargs -0 -P 8 md5sum | sort -k2 > md5sums.txt
        count=$(wc -l < md5sums.txt)
        echo "Generated md5sums.txt with $count entries for {wildcards.project}"
        if [ "$count" -eq 0 ]; then
            echo "ERROR: md5sums.txt is empty, no .fastq.gz files found" >&2
            exit 1
        fi
        ) > {log} 2>&1
        """

rule copy_plots_to_output:
    """Copy the fastp plots embedded in the order reports (results/{config_id}/{project}/*.png)
    into a 'plots' subdirectory of the corresponding output project directory."""
    input:
        plots_done   = "results/{config_id}/fastp_plots_{config_id}.done",
        project_done = "output/{config_id}/{project}/.project_done"
    output:
        sentinel = touch("output/{config_id}/{project}/.plots_copied")
    log:
        "logs/{config_id}/copy_plots_to_output_{config_id}_{project}.log"
    benchmark:
        "benchmarks/copy_plots_to_output_{config_id}_{project}.bench"
    wildcard_constraints:
        config_id = "[^/]+",
        project = ".+"
    run:
        import glob, os, shutil

        src_dir  = f"results/{wildcards.config_id}/{wildcards.project}"
        dest_dir = f"output/{wildcards.config_id}/{wildcards.project}/plots"
        os.makedirs(dest_dir, exist_ok=True)

        pngs = sorted(glob.glob(os.path.join(src_dir, "*.png")))
        copied = []
        with open(log[0], 'w') as lf:
            lf.write(f"Source: {src_dir}\nDest: {dest_dir}\n")
            if not pngs:
                lf.write("No PNG plots found to copy.\n")
            for png in pngs:
                shutil.copy2(png, os.path.join(dest_dir, os.path.basename(png)))
                copied.append(os.path.basename(png))
            lf.write(f"Copied {len(copied)} plot(s): {copied}\n")

# Rule: generate exclude-indexes file for each config_id
rule generate_exclude_indexes:
    input:
        samplesheets = lambda wildcards: [f"results/{other_id}/SampleSheet_{other_id}.csv" for other_id in get_config_ids_for_lane(get_lane_for_config(wildcards.config_id)) if other_id != wildcards.config_id]
    output:
        txt = "results/{config_id}/exclude_indexes_{config_id}.txt"
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
        done = ".output/{config_id}/.done"
    output:
        csv = "results/undetermined_indices/{config_id}.csv"
    log:
        "logs/{config_id}/analyze_undetermined_{config_id}.log"
    benchmark:
        "benchmarks/analyze_undetermined_{config_id}.bench"
    params:
        barcodes = lambda wildcards: f".output/{wildcards.config_id}/Reports/Top_Unknown_Barcodes.csv"
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

rule detect_rc_candidates:
    """Detect projects with likely i7 reverse-complement orientation issues
    for a single config_id by comparing undetermined barcodes to expected indexes.
    Produces a JSON list of suspect project records (may be empty).
    """
    input:
        undetermined = maybe_ancient("results/undetermined_indices/{config_id}.csv"),
        samplesheet = maybe_ancient("results/{config_id}/SampleSheet_{config_id}.csv")
    output:
        candidates = "logs/{config_id}/rc_candidates_{config_id}.json"
    log:
        "logs/{config_id}/detect_rc_candidates_{config_id}.log"
    wildcard_constraints:
        config_id = "[^/]+"
    params:
        rc_threshold = config.get("rc_rerun_threshold", 0.5),
        min_total_count = config.get("rc_rerun_min_total_count", 1000),
        min_rc_count = config.get("rc_rerun_min_rc_count", 1000),
    run:
        import json as json_mod
        import subprocess
        import sys as sys_mod
        result = subprocess.run(
            [
                sys_mod.executable, "scripts/check_index_rc_swap.py",
                "--samples", input.samplesheet,
                "--undetermined", input.undetermined,
                "--format", "json",
                "--rc-threshold", str(params.rc_threshold),
                "--min-total-count", str(params.min_total_count),
                "--min-rc-count", str(params.min_rc_count),
            ],
            capture_output=True, text=True
        )
        with open(log[0], 'w') as lf:
            lf.write(result.stderr)
        if result.returncode != 0:
            raise RuntimeError(f"check_index_rc_swap.py failed:\n{result.stderr}")
        payload = json_mod.loads(result.stdout)
        # config_id in the JSON comes from infer_config_id_from_samplesheet,
        # which strips the SampleSheet_ prefix, so it matches wildcards.config_id.
        suspects = [
            r for r in payload.get('project_suspects', [])
            if r.get('config_id') == wildcards.config_id
        ]
        with open(output.candidates, 'w') as f:
            json_mod.dump(suspects, f, indent=2)
        print(f"RC candidates for {wildcards.config_id}: {[r['project'] for r in suspects]}")

rule generate_rc_samplesheet:
    """Generate a SampleSheet with i7 reverse-complemented for RC suspect projects.
    If no suspects, copies the original SampleSheet unchanged.
    """
    input:
        samplesheet = maybe_ancient("results/{config_id}/SampleSheet_{config_id}.csv"),
        candidates = maybe_ancient("logs/{config_id}/rc_candidates_{config_id}.json")
    output:
        rc_samplesheet = "results/{config_id}/SampleSheet_{config_id}_rc.csv"
    log:
        "logs/{config_id}/generate_rc_samplesheet_{config_id}.log"
    wildcard_constraints:
        config_id = "[^/]+"
    run:
        import subprocess, sys as sys_mod
        result = subprocess.run(
            [
                sys_mod.executable, "src/apply_rc_to_samplesheet.py",
                "--samplesheet", input.samplesheet,
                "--candidates", input.candidates,
                "--output", output.rc_samplesheet,
            ],
            capture_output=True, text=True
        )
        with open(log[0], 'w') as lf:
            lf.write(result.stdout)
            lf.write(result.stderr)
        if result.returncode != 0:
            raise RuntimeError(f"apply_rc_to_samplesheet.py failed:\n{result.stderr}")

rule validate_barcode_hamming_distances_rc:
    """Validate RC sample sheet barcode Hamming distances before bcl_convert_rc.

    Runs the same Hamming distance check as validate_barcode_hamming_distances but
    on the RC-corrected sample sheet.  Respects dual vs single index: the validation
    script only flags an error when BOTH i7 and i5 distances are insufficient for
    dual-indexed samples, and checks i7 alone for single-indexed samples.
    """
    input:
        samplesheet = maybe_ancient("results/{config_id}/SampleSheet_{config_id}_rc.csv")
    output:
        report = "logs/{config_id}/barcode_hamming_validation_rc_{config_id}.txt",
        marker = touch("logs/{config_id}/barcode_hamming_validation_rc_{config_id}.done"),
        fixed_sheet = "results/{config_id}/SampleSheet_{config_id}_rc_validated.csv"
    log:
        "logs/{config_id}/barcode_hamming_validation_rc_{config_id}.log"
    benchmark:
        "benchmarks/barcode_hamming_validation_rc_{config_id}.bench"
    wildcard_constraints:
        config_id = "[^/]+"
    params:
        script = "scripts/validate_barcode_hamming_distance.py",
        tolerance = 1
    shell:
        """
        (
        echo "Validating RC sample sheet barcode Hamming distances for {wildcards.config_id}..."
        python3 {params.script} \
            --samplesheets {input.samplesheet} \
            --mismatch-tolerance {params.tolerance} \
            --output {output.report} \
            --output-sheet {output.fixed_sheet} \
            --fix

        exit_code=$?
        if [ $exit_code -ne 0 ]; then
            echo ""
            echo "=========================================================="
            echo "ERROR: RC barcode Hamming distance validation FAILED for {wildcards.config_id} (after auto-fix attempt)"
            echo "=========================================================="
            echo ""
            cat {output.report}
            exit 1
        fi
        ) > {log} 2>&1
        """

rule bcl_convert_rc:
    """Run BCL Convert with an i7-RC SampleSheet for config_ids where RC suspect
    projects were detected. If no suspects exist, creates an empty marker
    directory without running BCL Convert.
    """
    input:
        rc_samplesheet = maybe_ancient("results/{config_id}/SampleSheet_{config_id}_rc_validated.csv"),
        renaming_map = maybe_ancient("results/{config_id}/renaming_map_{config_id}.csv"),
        candidates = maybe_ancient("logs/{config_id}/rc_candidates_{config_id}.json"),
        data_dir = DATA_DIR,
        run_info = "src/RunInfo_nn.xml",
        orig_done = maybe_ancient(".output/{config_id}/.done")
    output:
        output_dir = directory(".output_rc/{config_id}"),
        done_file = touch(".output_rc/{config_id}/.done")
    log:
        "logs/{config_id}/bcl_convert_rc_{config_id}.log"
    benchmark:
        "benchmarks/bcl_convert_rc_{config_id}.bench"
    wildcard_constraints:
        config_id = "[^/]+"
    priority: 90
    resources:
        serial_operation=1
    threads: 1
    params:
        lane = lambda wildcards: wildcards.config_id.split('_')[0].replace('lane', ''),
        run_info_path = "src/RunInfo_nn.xml",
        tiles = TILES,
    run:
        import json as json_mod, subprocess, sys as sys_mod, os as os_mod
        with open(input.candidates) as f:
            suspects = json_mod.load(f)
        os_mod.makedirs(output.output_dir, exist_ok=True)
        with open(log[0], 'w') as lf:
            if not suspects:
                lf.write(f"No RC suspects for {wildcards.config_id}; skipping BCL Convert RC run.\n")
                return
            lf.write(f"RC suspects: {[r['project'] for r in suspects]}\n")
            tiles_args = ["--tiles", str(params.tiles)] if params.tiles else []
            cmd = [
                "dragen", "--bcl-conversion-only", "true",
                "--bcl-input-directory", str(input.data_dir),
                "--output-directory", str(output.output_dir),
                "--force",
                "--bcl-sampleproject-subdirectories", "true",
                "--sample-sheet", str(input.rc_samplesheet),
                "--strict-mode", "false",
                "--bcl-only-lane", str(params.lane),
                "--run-info", str(params.run_info_path),
                "--bcl-num-parallel-tiles", "1",
                "--bcl-num-conversion-threads", "8",
                "--bcl-num-compression-threads", "8",
                "--bcl-num-decompression-threads", "8",
            ] + tiles_args
            lf.write(f"Running: {' '.join(cmd)}\n")
            lf.flush()
            result = subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT, timeout=7200)
            if result.returncode != 0:
                raise RuntimeError(f"DRAGEN RC run failed for {wildcards.config_id}")

            # Keep RC output naming consistent with the primary bcl_convert output.
            rename_cmd = [
                "bash", "src/run_rename.sh",
                wildcards.config_id,
                str(output.output_dir),
                str(input.renaming_map),
            ]
            lf.write(f"Running: {' '.join(rename_cmd)}\n")
            lf.flush()
            rename_result = subprocess.run(rename_cmd, stdout=lf, stderr=subprocess.STDOUT)
            if rename_result.returncode != 0:
                raise RuntimeError(f"RC FASTQ rename failed for {wildcards.config_id}")

rule pick_orientation:
    """Compare first-pass and RC-pass Demultiplex_Stats for each suspect project
    and write a JSON decision file mapping old Sample_Project name -> 'original' or 'rc'.
    Non-suspect projects are omitted (callers default to 'original').
    """
    input:
        done_orig = maybe_ancient(".output/{config_id}/.done"),
        done_rc = ".output_rc/{config_id}/.done",
        candidates = "logs/{config_id}/rc_candidates_{config_id}.json"
    output:
        decision = "logs/{config_id}/orientation_decision_{config_id}.json"
    log:
        "logs/{config_id}/pick_orientation_{config_id}.log"
    wildcard_constraints:
        config_id = "[^/]+"
    run:
        import json as json_mod, csv as csv_mod, os as os_mod

        def read_project_counts(stats_csv):
            counts = {}
            if not os_mod.path.exists(stats_csv):
                return counts
            try:
                with open(stats_csv) as f:
                    reader = csv_mod.DictReader(f)
                    for r in reader:
                        proj = (r.get('SampleProject') or r.get('Sample_Project') or '').strip()
                        reads_raw = r.get('# Reads') or r.get('Reads') or '0'
                        try:
                            reads = int(reads_raw)
                        except ValueError:
                            reads = 0
                        if proj:
                            counts[proj] = counts.get(proj, 0) + reads
            except Exception as e:
                with open(log[0], 'a') as lf:
                    lf.write(f"Warning: could not parse {stats_csv}: {e}\n")
            return counts

        with open(input.candidates) as f:
            suspects = json_mod.load(f)

        # Keep Undetermined FASTQs for lanes configured for flexbar demux, or for
        # lanes explicitly listed in keep_undetermined_configs / report_undetermined_configs.
        # Match bcl_convert behavior to avoid deleting reads it was told to keep.
        preserve_undetermined = (
            os_mod.path.isfile(f"metadata/flexbar_barcodes_{wildcards.config_id}.txt")
            or wildcards.config_id in _effective_keep
        )

        # Build fix_type lookup: project -> label (rc_i7 / rc_i5 / rc_both)
        fix_type_map = {}
        for rec in suspects:
            ft = rec.get('fix_type', 'i7_rc')
            # i7_rc -> rc_i7, i5_rc -> rc_i5, both_rc -> rc_both
            fix_type_map[rec['project']] = "rc_" + ft.replace('_rc', '')

        decision = {}
        with open(log[0], 'w') as lf:
            if not suspects:
                lf.write(f"No RC suspects for {wildcards.config_id}; all projects use original.\n")
            else:
                orig_stats = f".output/{wildcards.config_id}/Reports/Demultiplex_Stats.csv"
                rc_stats = f".output_rc/{wildcards.config_id}/Reports/Demultiplex_Stats.csv"
                orig_counts = read_project_counts(orig_stats)
                rc_counts = read_project_counts(rc_stats)
                lf.write(f"Original counts: {orig_counts}\n")
                lf.write(f"RC counts: {rc_counts}\n")
                for rec in suspects:
                    project = rec['project']
                    orig = orig_counts.get(project, 0)
                    rc_val = rc_counts.get(project, 0)
                    winner = fix_type_map.get(project, "rc_i7") if rc_val > orig else "original"
                    decision[project] = winner
                    lf.write(f"{project}: original={orig}, rc={rc_val} -> {winner}\n")

        with open(output.decision, 'w') as f:
            json_mod.dump(decision, f, indent=2)

        # Remove .output_rc project directories for projects that don't need RC,
        # since bcl_convert_rc always demuxes the whole lane as a byproduct.
        import shutil as _shutil_rc
        rc_projects = {p for p, v in decision.items() if v.startswith("rc")}
        # DRAGEN-generated lane-level directories — keep these so bcl_project_done can copy
        # RC-corrected Demultiplex_Stats.csv and other reports to output/{config_id}/Reports/.
        _DRAGEN_LANE_DIRS = {'Reports', 'Logs', 'Thumbnail_Images', 'InterOp'}
        rc_lane_dir = f".output_rc/{wildcards.config_id}"
        if os_mod.path.isdir(rc_lane_dir):
            with open(log[0], 'a') as lf:
                for item in os_mod.listdir(rc_lane_dir):
                    if item.startswith('.'):
                        continue  # keep .done and other hidden markers
                    item_path = os_mod.path.join(rc_lane_dir, item)
                    if os_mod.path.isdir(item_path) and item not in rc_projects and item not in _DRAGEN_LANE_DIRS:
                        lf.write(f"Removing unused RC project dir: {item_path}\n")
                        _shutil_rc.rmtree(item_path)
                    elif os_mod.path.isfile(item_path) and item.startswith('Undetermined') and item.endswith('.fastq.gz'):
                        if preserve_undetermined:
                            lf.write(f"Preserving RC undetermined reads for flexbar lane: {item_path}\n")
                        else:
                            lf.write(f"Removing RC undetermined reads: {item_path}\n")
                            os_mod.remove(item_path)

        # Remove Undetermined*.fastq.gz from .output unless needed for flexbar.
        # Also remove original project dirs for RC-winning projects — their reads
        # came from the original (wrong-orientation) demux and are superseded by
        # the RC pass already in .output_rc.
        orig_lane_dir = f".output/{wildcards.config_id}"
        if os_mod.path.isdir(orig_lane_dir):
            with open(log[0], 'a') as lf:
                for item in os_mod.listdir(orig_lane_dir):
                    item_path = os_mod.path.join(orig_lane_dir, item)
                    if item.startswith('Undetermined') and item.endswith('.fastq.gz'):
                        if os_mod.path.isfile(item_path):
                            if preserve_undetermined:
                                lf.write(f"Preserving original undetermined reads for flexbar lane: {item_path}\n")
                            else:
                                lf.write(f"Removing original undetermined reads: {item_path}\n")
                                os_mod.remove(item_path)
                    elif os_mod.path.isdir(item_path) and item in rc_projects:
                        lf.write(f"Removing original staging dir for RC-winning project: {item_path}\n")
                        _shutil_rc.rmtree(item_path)

rule update_validation_workbook:
    """Regenerate the metadata validation workbook after all orientation decisions
    are known, so the RC_ORIENTATION sheet reflects which projects ran through RC.
    """
    input:
        decisions = expand("logs/{config_id}/orientation_decision_{config_id}.json", config_id=CONFIG_IDS),
        metadata = maybe_ancient(metadata)
    output:
        xlsx = VALIDATION_XLSX
    run:
        validate_metadata_and_write_report(str(input.metadata), out_xlsx=output.xlsx)

rule check_index_rc_swap:
    """Run the index reverse-complement/swap analysis script across generated
    SampleSheet CSVs and undetermined indices CSVs.
    """
    input:
        samples = lambda wildcards: sorted(glob.glob("results/*/SampleSheet_*.csv")),
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
        log = "logs/{config_id}/project_link_{config_id}---{project}.log",
        yaml_file = "logs/{config_id}/project_links_{config_id}---{project}.yaml"
    benchmark:
        "benchmarks/project_link_{config_id}---{project}.bench"
    wildcard_constraints:
        # Relaxed to accept any lane-prefixed config with additional underscore-separated tokens
        config_id = "[^/]+",
        project = ".+"
    resources:
        serial_operation=1
    params:
        work_dir = os.getcwd(),
        order_id = lambda wildcards: (
            # Prefer (lane, group)-keyed lookup so duplicate project names on the same lane
            # each resolve to their own order_id rather than the last-written shared entry.
            ORDER_ID_LOOKUP.get(
                (int(lane_m.group(1)), int(grp_m.group(1))),
                PROJECT_ORDER_ID.get(
                    (PROJECT_RENAME_MAP_INV.get((wildcards.config_id, wildcards.project), wildcards.project),
                     int(lane_m.group(1))), "")
            )
            if (lane_m := re.match(r'lane(\d+)', wildcards.config_id))
            and (grp_m := re.search(r'_G(\d+)$', wildcards.project))
            else PROJECT_ORDER_ID.get(
                (PROJECT_RENAME_MAP_INV.get((wildcards.config_id, wildcards.project), wildcards.project),
                 int(re.match(r'lane(\d+)', wildcards.config_id).group(1))
                 if re.match(r'lane(\d+)', wildcards.config_id) else 0), "")
        ),
        group = lambda wildcards: (
            # Extract group directly from the renamed project folder name (_G{n} suffix)
            # to avoid the reverse-lookup bug where duplicate project names on the same
            # lane always resolve to the first group in PROJECT_LOOKUP.
            m.group(1) if (m := re.search(r'_G(\d+)$', wildcards.project))
            else get_project_group(
                PROJECT_RENAME_MAP_INV.get((wildcards.config_id, wildcards.project), wildcards.project),
                wildcards.config_id)
        )
    run:
        import traceback
        import subprocess
        import sys
        from pathlib import Path
        import time
        import urllib.parse
        import re
        import os
        import shlex
        import glob as _glob
        
        config_id = wildcards.config_id
        project = wildcards.project
        order_id = params.order_id
        group = params.group
        fastq_dir = f"output/{config_id}/{project}"
        log_file = output.log
        yaml_file = output.yaml_file

        if not str(order_id).strip():
            msg = (
                f"Missing order_id for project link generation "
                f"(config_id={config_id}, project={project}, group={group}). "
                "Check metadata order-id mapping for this project/lane."
            )
            Path(log_file).write_text(msg + "\n")
            raise RuntimeError(msg)

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

        def extract_share_id(xml_text):
            if not xml_text: return None
            m = re.search(r'<id>(\d+)</id>', xml_text)
            return m.group(1) if m else None

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
                share_id_num = None
                share_xml = None
                rate_limited = False
                last_error = None
                
                while retry_count < max_retries and not share_url:
                    retry_count += 1
                    wait_time = min(3 * (2 ** (retry_count - 1)), 60)
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
                            share_id_num = extract_share_id(share_xml)
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
                            share_id_num = extract_share_id(share_xml)
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

                # --- RESTORE PRIOR TOKEN FROM EXISTING LOGS ---
                if share_url and share_token and share_id_num:
                    old_token = None
                    for lp in sorted(_glob.glob("logs/**/project_link_*.log", recursive=True)):
                        if os.path.abspath(lp) == os.path.abspath(log_file):
                            continue
                        try:
                            content = Path(lp).read_text()
                            if f"NC_PATH: {nc_path}" in content and "Status: SUCCESS" in content:
                                m = re.search(r'^WebDAV Token: (\S+)', content, re.MULTILINE)
                                if m:
                                    old_token = m.group(1)
                                    break
                        except Exception:
                            pass
                    if old_token and old_token != share_token:
                        put_cmd = [
                            sys.executable, "scripts/test_nextcloud_token.py",
                            "--share-id", share_id_num,
                            "--token", old_token
                        ]
                        executed_cmds.append(put_cmd)
                        put_result = subprocess.run(put_cmd, capture_output=True, text=True, timeout=30)
                        m_token = re.search(r'New Token\s*:\s*(\S+)', put_result.stdout)
                        m_url = re.search(r'New URL\s*:\s*(\S+)', put_result.stdout)
                        if m_token:
                            share_token = m_token.group(1)
                        if m_url:
                            share_url = m_url.group(1)

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
                        yaml_data[project][config_id][order_id] = {"link": share_url, "group": group}
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
        "logs/{config_id}/project_link_{config_id}---{project}.log"
    output:
        touch("logs/{config_id}/nextcloud_scan_{config_id}---{project}.done")
    log:
        "logs/{config_id}/rescan_nextcloud_{config_id}_{project}.log"
    benchmark:
        "benchmarks/rescan_nextcloud_{config_id}_{project}.bench"
    wildcard_constraints:
        # Relaxed to accept any lane-prefixed config with additional underscore-separated tokens
        config_id = "[^/]+",
        project = ".+"
    params:
        nc_path = lambda wildcards: f"/{NEXTCLOUD_DIR_NAME}/{LIBRARY}/output/{wildcards.config_id}/{wildcards.project}",
        ssh_host = NEXTCLOUD_SSH_HOST
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
            # OCC expects "<user>/files/<path>", not "users/<user>/files/<path>".
            # Normalize if internal path already includes a user/files prefix.
            internal=$(echo "$internal" | sed "s@^users/${{nc_owner}}/files/@@")
            internal=$(echo "$internal" | sed 's@^files/@@')
            occ_path="$nc_owner/files/$internal"
        elif [ -n "$nc_path" ]; then
            occ_path="$nc_path"
        else
            echo "NC path information not found in $nc_log" > {log}
            exit 1
        fi

        ssh {params.ssh_host} "docker exec --user www-data nextcloud-aio-nextcloud php occ files:scan --path='$occ_path'" > {log} 2>&1

        # OCC can report malformed --path usage while still returning quickly.
        if grep -q "Unknown user" {log}; then
            echo "ERROR: files:scan used an invalid user path: $occ_path" >> {log}
            exit 1
        fi
        """



rule verify_project_links:
    input:
        project_link_log = "logs/{config_id}/project_link_{config_id}---{project}.log",
        scan_done = "logs/{config_id}/nextcloud_scan_{config_id}---{project}.done"
    output:
        report = "logs/{config_id}/verify_project_link_{config_id}---{project}.txt"
    log:
        "logs/{config_id}/verify_project_link_{config_id}---{project}.log"
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
                        '-u', f'{NEXTCLOUD_USER}:{NEXTCLOUD_PASSWORD}',
                        '-X', 'PROPFIND',
                        '-H', 'Depth: 1',
                        f'{NEXTCLOUD_URL}/remote.php/dav/files/{NEXTCLOUD_USER}/{NEXTCLOUD_DIR_NAME}/{LIBRARY}/output/{config_id}/{project}/'
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
            done_path = f".output/{config_id}/.done"
            print(f"{done_path}: {'EXISTS' if os.path.exists(done_path) else 'MISSING'}")
        print("\n=== DIAGNOSTIC: Expected .log files ===")
        for config_id, project in CONFIG_PROJECT_PAIRS:
            log_path = f"logs/{config_id}/project_link_{config_id}_{project}.log"
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