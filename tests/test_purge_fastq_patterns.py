"""purge_project_outputs.sh --old-metadata/--new-metadata finds the changed samples' FASTQs.

Diff mode used to glob only on the barcode, which the GRT stem name embeds but the
Illumina default name (single-cell and bcl2fastq-tab projects) does not. xR123's
SequA barcode fixes matched no FASTQs at all. The patterns now cover both names.
"""
import fnmatch
import os

import pandas as pd

from _helpers import REPO, _exec_source


def _load():
    with open(os.path.join(REPO, "src", "purge_project_outputs.sh")) as handle:
        source = handle.read()
    start = source.index("def _get_barcode_pat(row):")
    end = source.index("all_tabs = set(", start)
    return _exec_source(source[start:end])


_ns = _load()
_old_fastq_pats = _ns["_old_fastq_pats"]

ROW = pd.Series({"Sample_Name": "33_2000", "index": "CTACTCGA", "index2": "GTTCATCT"})


def _matches(pats, name):
    # find -path matches the whole path; the project dir prefix is literal.
    return any(fnmatch.fnmatchcase(f"./output/lane6/P/{name}", f"./output/lane6/P/{p}")
               for p in pats)


def test_illumina_named_fastqs_match():
    pats = _old_fastq_pats(ROW, "33_2000", 6)
    assert _matches(pats, "33_2000_S3_L006_R1_001.fastq.gz")
    assert _matches(pats, "33_2000_S12_L006_I1_001.fastq.gz")


def test_grt_named_fastqs_still_match():
    pats = _old_fastq_pats(ROW, "33_2000", 6)
    assert _matches(pats, "xR123-L6-G1-P003-CTACTCGA-GTTCATCT-R1.fastq.gz")


def test_other_samples_and_lanes_do_not_match():
    pats = _old_fastq_pats(ROW, "33_2000", 6)
    for name in ("133_2000_S3_L006_R1_001.fastq.gz",   # name with a shared suffix
                 "33_20001_S3_L006_R1_001.fastq.gz",   # name with a shared prefix
                 "33_2000_S3_L007_R1_001.fastq.gz",    # same sample, other lane
                 "xR123-L6-G1-P004-AAGAAGCG-TTATCTAC-R1.fastq.gz"):
        assert not _matches(pats, name), name


def test_blank_sample_name_falls_back_to_sample_id():
    row = pd.Series({"Sample_Name": float("nan"), "index": "AAGTACAG", "index2": ""})
    pats = _old_fastq_pats(row, "239_1052_2", 2)
    assert _matches(pats, "239_1052_2_S42_L002_R2_001.fastq.gz")
    assert _matches(pats, "xR123-L2-G1-P042-AAGTACAG-R2.fastq.gz")
