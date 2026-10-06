"""Standalone scripts key projects with the same rule as the sample sheets.

single_cell.py and split_shared_project_groups.py read the raw Summary
"Project Name". DRAGEN writes Sample_Project through normalize_project_name, so
both scripts must compare on that form or a name with punctuation never matches.
"""
import os

import pandas as pd

import single_cell
from naming import normalize_project_name

RAW = "EomD WT,  V4/Sublibrary1to8 "
KEY = "EomD_WT_V4_Sublibrary1to8"


def _write_summary(path, rows):
    """A Summary sheet with its header on row 3, as the lab's workbooks have it."""
    df = pd.DataFrame(rows, columns=["Lane", "Gr", "Project Name", "Sample sheet tab"])
    with pd.ExcelWriter(path) as writer:
        df.to_excel(writer, sheet_name="Summary", index=False, startrow=2)


def test_naming_rule_matches_sample_sheet_form():
    assert normalize_project_name(RAW) == KEY


def test_single_cell_registry_matches_normalized_project(tmp_path):
    path = os.path.join(tmp_path, "run.xlsx")
    _write_summary(path, [(6, 1, RAW, "Parse Biosciences")])
    # No single-cell token in the name and a lane/group not on the Summary,
    # so only the Summary name lookup can make this match.
    assert not single_cell.name_indicates_single_cell(KEY)
    assert single_cell.is_single_cell_project(KEY, lane=9, group=9, metadata_file=path)
    assert not single_cell.is_single_cell_project("Other_Project", lane=9, group=9,
                                                  metadata_file=path)


def test_split_script_normalizes_summary_project_names():
    src = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "src", "split_shared_project_groups.py")
    with open(src) as handle:
        source = handle.read()
    assert 'df_summary["Project Name"].map(normalize_project_name)' in source
    # Normalizing must happen before the shared-name grouping uses the column.
    assert source.index("map(normalize_project_name)") < source.index('groupby(["Lane", "Project Name"])')
