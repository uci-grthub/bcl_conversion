"""Single-cell project detection (10x / Parse / BD).

Single-cell projects keep Illumina default FASTQ naming
(``<Sample_Name>_S<num>_L00<lane>_R<read>_001.fastq.gz``) because CellRanger,
the Parse pipeline and the BD tools all parse that convention.

Detection used to look only at the project name, which misses true single-cell
orders whose submitted name has no "10x"/"Parse"/"BD" token (e.g. a Parse order
named ``EomD_WT_V4_Sublibrary1to8``).  The Summary sheet's "Sample sheet tab"
column always names the specialty tab those samples live on, so it is consulted
as a second source of truth: a project counts as single cell when *either* its
name or its Summary sheet tab matches.

The Summary lookup is cached module-wide.  The metadata workbook is taken from
``PIPELINE_METADATA_FILE`` (exported by the Snakefile so child scripts inherit
it) or discovered under ``metadata/`` when that variable is unset.
"""

import os
import re
import glob

# Tokens shared by project names and Summary sheet tabs.
SINGLE_CELL_TOKENS = ("10x", "parse", "bd")

# Renamed project folders look like {LabID}_{OrderID}_{library}_L{lane}_G{group};
# the suffix lets a renamed folder be resolved back to its Summary row.
_RENAMED_SUFFIX_RE = re.compile(r"_L(\d+)_G(\d+)$")

_REGISTRY = {
    "loaded_from": None,   # abspath of the workbook the sets came from
    "names": set(),        # normalized project names sitting on a single-cell tab
    "lane_groups": set(),  # (lane, group) pairs sitting on a single-cell tab
}


def _norm(value):
    try:
        return str(value if value is not None else "").strip().lower()
    except Exception:
        return ""


def name_indicates_single_cell(project_name):
    """True when the project name itself carries a single-cell token."""
    p = _norm(project_name)
    return any(tok in p for tok in SINGLE_CELL_TOKENS)


def sheet_tab_indicates_single_cell(tab):
    """True when a Summary "Sample sheet tab" value names a single-cell tab."""
    t = _norm(tab).replace("_", " ")
    if not t or t == "nan":
        return False
    # "Barcode List" is the generic tab every non-specialty order uses.
    if t == "barcode list":
        return False
    return any(tok in t for tok in SINGLE_CELL_TOKENS)


def find_metadata_file():
    """Locate the run's metadata workbook (env override, else metadata/*.xlsx)."""
    env_path = os.environ.get("PIPELINE_METADATA_FILE")
    if env_path and os.path.exists(env_path):
        return env_path
    candidates = [
        p for p in glob.glob(os.path.join("metadata", "*.xlsx"))
        if not os.path.basename(p).startswith(("metadata_validation_", "~$", "."))
    ]
    if not candidates:
        return None
    # Newest workbook wins when a run directory holds more than one.
    candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return candidates[0]


def load_single_cell_registry(metadata_file=None, force=False):
    """Populate the Summary-derived registry; safe to call repeatedly."""
    path = metadata_file or find_metadata_file()
    if not path or not os.path.exists(path):
        return _REGISTRY

    abspath = os.path.abspath(path)
    if not force and _REGISTRY["loaded_from"] == abspath:
        return _REGISTRY

    names = set()
    lane_groups = set()
    try:
        import pandas as pd
        df = pd.read_excel(path, sheet_name="Summary", header=2)
        if "Sample sheet tab" in df.columns:
            for _, row in df.iterrows():
                if not sheet_tab_indicates_single_cell(row.get("Sample sheet tab")):
                    continue
                project = _norm(row.get("Project Name"))
                if project and project != "nan":
                    names.add(project)
                try:
                    lane_groups.add((int(float(row.get("Lane"))), int(float(row.get("Gr")))))
                except Exception:
                    pass
    except Exception as e:
        print(f"Note: could not read single-cell tabs from {path}: {e}")
        return _REGISTRY

    _REGISTRY["loaded_from"] = abspath
    _REGISTRY["names"] = names
    _REGISTRY["lane_groups"] = lane_groups
    return _REGISTRY


def is_single_cell_project(project_name, lane=None, group=None, metadata_file=None):
    """True when the project uses Illumina default naming (10x / Parse / BD).

    Matches on the project name, on the Summary "Sample sheet tab" entry for
    that project, or on the (lane, group) the project belongs to — including the
    lane/group encoded in a renamed output folder.
    """
    if name_indicates_single_cell(project_name):
        return True
    try:
        load_single_cell_registry(metadata_file)
        if _norm(project_name) in _REGISTRY["names"]:
            return True
        if lane is None or group is None:
            m = _RENAMED_SUFFIX_RE.search(str(project_name or ""))
            if m:
                lane, group = m.group(1), m.group(2)
        if lane is not None and group is not None:
            if (int(float(lane)), int(float(group))) in _REGISTRY["lane_groups"]:
                return True
    except Exception as e:
        print(f"Note: single-cell tab lookup failed for '{project_name}': {e}")
    return False


# Historical name kept so existing call sites read unchanged.
is_parse_or_10x = is_single_cell_project
