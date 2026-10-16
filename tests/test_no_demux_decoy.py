"""The decoy index that makes a no_demux run fall through to Undetermined.

DRAGEN requires index columns whenever RunInfo declares indexed reads, and only writes
I1/I2 FASTQs for the Undetermined pseudo-sample when no real sample claims the reads. So
no_demux ships a decoy index that must match nothing. A homopolymer cannot be used: on
2-channel chemistry absent signal reads out as G, so a polyG decoy captures dark clusters
and silently drops them from the delivery.
"""
import os
import textwrap

from _helpers import REPO, _exec_source


def _load_decoy_helpers():
    """Exec the shipped decoy helpers out of the Snakemake include file."""
    with open(os.path.join(REPO, "src", "workflow_defs.smk")) as handle:
        source = handle.read()
    start = source.index("NO_DEMUX_DECOY_SAMPLE =")
    end = source.index("def generate_lane_samplesheets(")
    import xml.etree.ElementTree as ET
    return _exec_source(textwrap.dedent(source[start:end]), {"ET": ET})


HELPERS = _load_decoy_helpers()


def _run_info(tmp_path, reads):
    path = os.path.join(tmp_path, "RunInfo.xml")
    body = "".join(
        f'<Read Number="{n}" NumCycles="{c}" IsIndexedRead="{i}"/>'
        for n, c, i in reads
    )
    with open(path, "w") as handle:
        handle.write(f"<RunInfo><Run><Reads>{body}</Reads></Run></RunInfo>")
    return path


def test_decoy_matches_the_runs_index_lengths(tmp_path):
    """A length mismatch is a hard DRAGEN error, so the pattern is cut to the run."""
    path = _run_info(tmp_path, [(1, 8, "Y"), (2, 8, "Y"), (3, 150, "N")])
    i7, i5 = HELPERS["no_demux_decoy_indexes"](path)
    assert len(i7) == 8 and len(i5) == 8


def test_decoy_is_cycled_for_longer_index_reads(tmp_path):
    """10-cycle indexes are real; the 8-base pattern must extend, not truncate short."""
    path = _run_info(tmp_path, [(1, 10, "Y"), (2, 10, "Y"), (3, 150, "N")])
    i7, i5 = HELPERS["no_demux_decoy_indexes"](path)
    assert len(i7) == 10 and len(i5) == 10


def test_single_index_run_gets_no_i5_decoy(tmp_path):
    """An index2 value on a run with one index read is a sheet DRAGEN rejects."""
    path = _run_info(tmp_path, [(1, 8, "Y"), (2, 150, "N")])
    i7, i5 = HELPERS["no_demux_decoy_indexes"](path)
    assert len(i7) == 8
    assert i5 == ""


def test_decoy_is_not_a_homopolymer(tmp_path):
    """The whole point: polyG is what absent signal looks like on 2-channel chemistry."""
    path = _run_info(tmp_path, [(1, 8, "Y"), (2, 8, "Y"), (3, 150, "N")])
    for seq in HELPERS["no_demux_decoy_indexes"](path):
        assert len(set(seq)) >= 3, f"decoy {seq} is too low-complexity"
        assert "GGGG" not in seq, f"decoy {seq} contains a G-run"


def test_decoy_uses_both_channels(tmp_path):
    """A decoy of only G/T (dark-channel bases) is closer to no-signal than it looks."""
    path = _run_info(tmp_path, [(1, 8, "Y"), (2, 8, "Y"), (3, 150, "N")])
    for seq in HELPERS["no_demux_decoy_indexes"](path):
        assert set("ACGT") >= set(seq)
        assert set(seq) & set("AC"), f"decoy {seq} has no green-channel base"


def _miseq_workbook(tmp_path, i7, i5):
    """Minimal MiSeq-format metadata workbook with the given barcode cells."""
    import pandas as pd
    path = os.path.join(tmp_path, "book.xlsx")
    with pd.ExcelWriter(path) as writer:
        pd.DataFrame([
            [None, None, None, None, None, None],
            [None, "Flowcell:TEST", None, None, None, "mRi100_test"],
            [None, "Run ID: TEST", None, None, None, None],
            [None, "Lab ID", "Sample Name", "Contact (E-mail)", "Multiplex Library", "Index Type"],
            [None, "PoolG", "PCG_L1_test", "a@b.com", "no", "dual"],
        ]).to_excel(writer, sheet_name="Sample Information + User Info", index=False, header=False)
        pd.DataFrame([
            ["Library Name", "Barcode Entries i7", None, "Barcode Entries i5"],
            ["PCG_L1_test", i7, None, i5],
        ]).to_excel(writer, sheet_name="Barcode Entries", index=False, header=False)
    return path


def _generate(tmp_path, i7, i5, no_demux):
    """Run the shipped MiSeq generator with NO_DEMUX set, return the sheet text."""
    import sys
    if os.path.join(REPO, "src") not in sys.path:
        sys.path.insert(0, os.path.join(REPO, "src"))
    with open(os.path.join(REPO, "src", "workflow_defs.smk")) as handle:
        source = handle.read()
    namespace = {"__name__": "wd", "NO_DEMUX": no_demux, "LIBRARY": "iRTEST",
                 "REPORT_UNDETERMINED_CONFIGS": ["lane1"]}
    exec(compile(source, "workflow_defs.smk", "exec"), namespace)
    out_dir = os.path.join(tmp_path, "out")
    os.makedirs(out_dir, exist_ok=True)
    namespace["generate_miseq_samplesheets"](
        _miseq_workbook(tmp_path, i7, i5), out_dir,
        os.path.join(REPO, "src", "RunInfo_nn.xml"), "iRTEST")
    with open(os.path.join(out_dir, "lane1", "SampleSheet_lane1.csv")) as handle:
        return handle.read()


def test_placeholder_workbook_yields_a_decoy_sheet(tmp_path):
    """NNNNNNNN is the documented no_demux placeholder; it must never reach DRAGEN."""
    sheet = _generate(tmp_path, "NNNNNNNN", "NNNNNNNN", no_demux=True)
    assert "NNNNNNNN" not in sheet
    assert HELPERS["NO_DEMUX_DECOY_SAMPLE"] in sheet


def test_placeholder_without_no_demux_is_rejected_at_generation(tmp_path):
    """Without the flag the placeholder would become a DRAGEN error several rules later."""
    try:
        _generate(tmp_path, "NNNNNNNN", "NNNNNNNN", no_demux=False)
    except ValueError as exc:
        assert "no_demux" in str(exc) and "NNNNNNNN" in str(exc)
    else:
        raise AssertionError("non-ACGT barcodes were accepted without no_demux")


def test_real_barcodes_without_no_demux_still_pass(tmp_path):
    """The guard must not disturb an ordinary demultiplexed run."""
    sheet = _generate(tmp_path, "ACGTACGT", "TTTTAAAA", no_demux=False)
    assert "ACGTACGT" in sheet
    assert HELPERS["NO_DEMUX_DECOY_SAMPLE"] not in sheet


def _demux_stats_frame():
    """Demultiplex_Stats.csv as DRAGEN writes it for a no_demux lane."""
    import pandas as pd
    return pd.DataFrame([
        {"Lane": 1, "SampleID": HELPERS["NO_DEMUX_DECOY_SAMPLE"],
         "Sample_Project": "PoolG", "# Reads": 0},
        {"Lane": 1, "SampleID": "Undetermined",
         "Sample_Project": "Undetermined", "# Reads": 191497},
    ])


def _load_filter(no_demux):
    import sys
    if os.path.join(REPO, "src") not in sys.path:
        sys.path.insert(0, os.path.join(REPO, "src"))
    with open(os.path.join(REPO, "src", "workflow_defs.smk")) as handle:
        source = handle.read()
    namespace = {"__name__": "wd", "NO_DEMUX": no_demux, "LIBRARY": "iRTEST",
                 "REPORT_UNDETERMINED_CONFIGS": ["lane1"]}
    exec(compile(source, "workflow_defs.smk", "exec"), namespace)
    return namespace["drop_no_demux_decoy_rows"]


def test_decoy_is_dropped_from_demux_stats():
    """It carries the real Sample_Project, so read counts and the zero-read alert see it."""
    kept = _load_filter(True)(_demux_stats_frame())
    assert list(kept["SampleID"]) == ["Undetermined"]


def test_undetermined_row_survives_the_filter():
    """That row is the entire delivery for a no_demux lane."""
    kept = _load_filter(True)(_demux_stats_frame())
    assert int(kept.iloc[0]["# Reads"]) == 191497


def test_filter_is_inert_without_no_demux():
    """A real sample that happens to share the decoy's name must not vanish."""
    frame = _demux_stats_frame()
    kept = _load_filter(False)(frame)
    assert len(kept) == len(frame)


def test_filter_tolerates_an_empty_frame():
    """Demultiplex_Stats.csv is read defensively; a failed read yields an empty frame."""
    import pandas as pd
    assert len(_load_filter(True)(pd.DataFrame())) == 0
