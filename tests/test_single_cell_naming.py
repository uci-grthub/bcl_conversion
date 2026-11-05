"""Projects on a bcl2fastq sheet tab get Illumina default naming, like single cell.

xR123's SequA order sits on a "SequA_bcl2fastq" tab: a bulk mRNA-seq library whose
customer expects bcl2fastq file names. Naming follows the single-cell rule, but
index-read retention (naming=False) stays single-cell only.
"""
import os

import pandas as pd

import single_cell


def _write_summary(path, rows):
    """A Summary sheet with its header on row 3, as the lab's workbooks have it."""
    df = pd.DataFrame(rows, columns=["Lane", "Gr", "Project Name", "Sample sheet tab"])
    with pd.ExcelWriter(path) as writer:
        df.to_excel(writer, sheet_name="Summary", index=False, startrow=2)


def _workbook(tmp_path):
    path = os.path.join(tmp_path, "run.xlsx")
    _write_summary(path, [
        (2, 1, "SequA_mRNAseq_Lane1", "SequA_bcl2fastq"),
        (7, 2, "PalcK_DNAseq_2plex", "Barcode List"),
        (8, 1, "LawsD_5V2_GEX", "10x5V2"),
    ])
    return path


def test_bcl2fastq_tab_variants_match():
    for tab in ("SequA_bcl2fastq", "BCL2FASTQ", "Bcl2Fastq", "bcl2 fastq", "Bcl-2-Fastq"):
        assert single_cell.sheet_tab_indicates_illumina_naming(tab), tab
    for tab in ("Barcode List", "10x Dual Index", "", None, float("nan")):
        assert not single_cell.sheet_tab_indicates_illumina_naming(tab), tab


def test_bcl2fastq_tab_is_not_single_cell():
    assert not single_cell.sheet_tab_indicates_single_cell("SequA_bcl2fastq")
    assert single_cell.sheet_tab_indicates_single_cell("10x Dual Index")
    assert not single_cell.sheet_tab_indicates_single_cell("Barcode List")


def test_bcl2fastq_project_gets_illumina_naming_only(tmp_path):
    path = _workbook(tmp_path)
    assert single_cell.is_single_cell_project("SequA_mRNAseq_Lane1", metadata_file=path)
    assert not single_cell.is_single_cell_project("SequA_mRNAseq_Lane1", metadata_file=path,
                                                  naming=False)


def test_bcl2fastq_lane_group_resolves_renamed_folder(tmp_path):
    path = _workbook(tmp_path)
    renamed = "SequA_0426I-40_xR123_L2_G1"
    assert single_cell.is_single_cell_project(renamed, metadata_file=path)
    assert not single_cell.is_single_cell_project(renamed, metadata_file=path, naming=False)


def test_other_tabs_unchanged(tmp_path):
    path = _workbook(tmp_path)
    assert not single_cell.is_single_cell_project("PalcK_DNAseq_2plex", lane=7, group=2,
                                                  metadata_file=path)
    for naming in (True, False):
        assert single_cell.is_single_cell_project("LawsD_5V2_GEX", lane=8, group=1,
                                                  metadata_file=path, naming=naming)
