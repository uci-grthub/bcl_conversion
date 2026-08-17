"""The index_rc flag in the emailed read-count table.

Recipients of the per-run read-count email are promised a flag naming the
projects whose submitted indexes had to be reverse-complemented. That flag is a
column in results/{LIBRARY}-count.csv, one value per lane/group block, so it can
be read without cross-referencing the orientation summary attachment.
"""
import csv
import os
import sys

import pandas as pd

from _helpers import (FIXTURE_MAP, Stub, load_rule_body,
                      load_workflow_defs_helpers)

_helpers = load_workflow_defs_helpers()
rc_index_label = _helpers["rc_index_label"]
rc_tags_label = _helpers["rc_tags_label"]
apply_orientation_to_map = _helpers["apply_orientation_to_map"]

COMPILE_BODY = load_rule_body("compile_read_counts",
                              end_marker="rule send_read_counts_email:")

LIBRARY = "xR106"
CONFIG_ID = "lane5"
DUAL_PROJECT = "AcmeC_WGS_8plex"      # Group 1 in the fixture
SINGLE_PROJECT = "SoloS_Amplicon_2plex"  # Group 2 in the fixture


# --- the shared label helper ------------------------------------------------

def test_label_names_the_flipped_index():
    assert rc_index_label("rc_i7") == "i7"
    assert rc_index_label("rc_i5") == "i5"
    assert rc_index_label("rc_both") == "i7+i5"


def test_label_is_blank_when_nothing_was_flipped():
    for orientation in ("original", "", None, "nan", float("nan")):
        assert rc_index_label(orientation) == ""


def test_tags_label_keeps_i7_before_i5():
    assert rc_tags_label({"i5", "i7"}) == "i7+i5"
    assert rc_tags_label({"i5"}) == "i5"
    assert rc_tags_label(set()) == ""


# --- driving the shipped compile_read_counts body ---------------------------

def build_run(root, decision):
    """A run root with one lane's effective map and its Demultiplex_Stats.

    `decision` is the {project: orientation} mapping pick_orientation writes.
    Passing None writes the workbook map instead, standing in for a run that
    predates the orientation decision — the column is then simply absent.
    """
    original = pd.read_csv(FIXTURE_MAP, dtype=str, keep_default_na=False)
    map_dir = os.path.join(root, "results", CONFIG_ID)
    reports_dir = os.path.join(root, "output", CONFIG_ID, "Reports")
    os.makedirs(map_dir, exist_ok=True)
    os.makedirs(reports_dir, exist_ok=True)

    written = original if decision is None else apply_orientation_to_map(original, decision)
    map_path = os.path.join(map_dir, f"renaming_map_{CONFIG_ID}_effective.csv")
    written.to_csv(map_path, index=False)

    pd.DataFrame([
        {"Lane": int(row["Lane"]), "Sample_Project": row["Sample_Project"],
         "SampleID": row["Sample_Name"], "# Reads": 1000 + index}
        for index, row in original.iterrows()
    ]).to_csv(os.path.join(reports_dir, "Demultiplex_Stats.csv"), index=False)

    return map_path


def compile_counts(root, decision):
    """Run the real rule body against `root` and return the parsed CSV."""
    map_path = build_run(root, decision)
    out_csv = os.path.join("results", f"{LIBRARY}-count.csv")
    os.makedirs(os.path.join(root, "logs"), exist_ok=True)

    namespace = {
        "input": Stub(maps=[os.path.relpath(map_path, root)]),
        "output": Stub(csv=out_csv),
        "log": [os.path.join("logs", "compile_read_counts.log")],
        "LIBRARY": LIBRARY,
        "FLEXBAR_CONFIGS": [],
        "FQTK_CONFIGS": [],
        "FQTK_CONFIG_RENAMING_MAP": {},
        # 10x/Parse labelling is orthogonal to the flag; keep the barcode stems.
        "is_parse_or_10x": lambda project, lane=None, group=None: False,
        "rc_index_label": rc_index_label,
        "rc_tags_label": rc_tags_label,
    }

    previous_cwd = os.getcwd()
    # The rule body reassigns sys.stdout/sys.stderr to its log and never puts
    # them back, so the test has to.
    saved_stdout, saved_stderr = sys.stdout, sys.stderr
    os.chdir(root)
    try:
        exec(compile(COMPILE_BODY, "<compile_read_counts>", "exec"), namespace)
    finally:
        if sys.stdout is not saved_stdout:
            sys.stdout.close()
        sys.stdout, sys.stderr = saved_stdout, saved_stderr
        os.chdir(previous_cwd)

    with open(os.path.join(root, out_csv)) as handle:
        rows = list(csv.reader(handle))
    return rows[0], rows[1:]


def block_values(header, rows, column):
    """{block index: set of non-empty values} for one column of every block."""
    positions = [i for i, name in enumerate(header) if name == column]
    return {
        block: {row[i].strip() for row in rows if i < len(row) and row[i].strip()}
        for block, i in enumerate(positions)
    }


def test_header_carries_index_rc_in_every_block(tmp_path):
    header, _ = compile_counts(str(tmp_path), {})
    # Leading empty column, then lane/group/sample/counts/index_rc per block.
    assert header[0] == ""
    assert header[1:] == ["lane", "group", "sample", "counts", "index_rc"] * 2


def test_flag_is_blank_when_nothing_was_reverse_complemented(tmp_path):
    header, rows = compile_counts(str(tmp_path), {})
    assert block_values(header, rows, "index_rc") == {0: set(), 1: set()}


def test_flag_is_blank_when_the_map_predates_the_decision(tmp_path):
    # No orientation column at all: every project reads as delivered-as-submitted.
    header, rows = compile_counts(str(tmp_path), None)
    assert "index_rc" in header
    assert block_values(header, rows, "index_rc") == {0: set(), 1: set()}


def test_flag_marks_only_the_reverse_complemented_project(tmp_path):
    header, rows = compile_counts(str(tmp_path), {DUAL_PROJECT: "rc_i5"})
    assert block_values(header, rows, "index_rc") == {0: {"i5"}, 1: set()}
    # Group 1 is the flagged block, and every one of its populated rows says so.
    assert block_values(header, rows, "group")[0] == {"1"}


def test_flag_repeats_on_every_row_of_its_block(tmp_path):
    header, rows = compile_counts(str(tmp_path), {DUAL_PROJECT: "rc_i7"})
    position = [i for i, name in enumerate(header) if name == "index_rc"][0]
    sample = position - 2
    populated = [row for row in rows if row[sample].strip()]
    assert len(populated) > 1
    assert all(row[position] == "i7" for row in populated)


def test_both_indexes_render_i7_first(tmp_path):
    header, rows = compile_counts(
        str(tmp_path), {DUAL_PROJECT: "rc_both", SINGLE_PROJECT: "rc_i7"})
    assert block_values(header, rows, "index_rc") == {0: {"i7+i5"}, 1: {"i7"}}


def test_counts_survive_the_added_column(tmp_path):
    header, rows = compile_counts(str(tmp_path), {DUAL_PROJECT: "rc_i5"})
    counts = block_values(header, rows, "counts")
    assert all(values for values in counts.values())
    assert all(value.replace(",", "").isdigit()
               for values in counts.values() for value in values)


# --- the one layout-sensitive downstream consumer ---------------------------

def test_find_missing_samples_reads_the_wider_table(tmp_path):
    from find_missing_samples import read_count_file

    header, _ = compile_counts(str(tmp_path), {DUAL_PROJECT: "rc_i5"})
    count_file = os.path.join(str(tmp_path), "results", f"{LIBRARY}-count.csv")
    found = read_count_file(count_file)

    original = pd.read_csv(FIXTURE_MAP, dtype=str, keep_default_na=False)
    assert len(found) == len(original)
    assert "index_rc" in header          # the column it must not mistake for a sample
    assert "i5" not in found


def test_find_missing_samples_still_reads_the_old_layout(tmp_path):
    from find_missing_samples import read_count_file

    legacy = os.path.join(str(tmp_path), "legacy-count.csv")
    with open(legacy, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["", "lane", "group", "sample", "counts",
                         "lane", "group", "sample", "counts"])
        writer.writerow(["", "5", "1", "A01", "1,000", "5", "2", "B01", "2,000"])
        writer.writerow(["", "5", "1", "A02", "1,001", "", "", "", ""])

    assert read_count_file(legacy) == {"A01", "A02", "B01"}
