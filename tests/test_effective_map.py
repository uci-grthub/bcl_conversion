"""apply_orientation_to_map: workbook barcodes -> delivered barcodes.

Guards the core of the RC naming fix. A project whose reads came out of the RC
demux pass must be named with the sequence actually present in the index reads,
and every other project must be passed through untouched.
"""
import json
import os

import pandas as pd

from _helpers import (FIXTURE_DUAL_PROJECT, FIXTURE_MAP, FIXTURE_SINGLE_PROJECT,
                      live_run_lanes, load_workflow_defs_helpers, revcomp)

_helpers = load_workflow_defs_helpers()
apply_orientation_to_map = _helpers["apply_orientation_to_map"]
RC_ORIENTATION_COLUMNS = _helpers["RC_ORIENTATION_COLUMNS"]

SHARED_COLUMNS = ["Sample_ID", "Sample_Name", "Sample_Project", "Lane", "index",
                  "index2", "Run", "Group", "Position"]


def load_fixture():
    return pd.read_csv(FIXTURE_MAP, dtype=str, keep_default_na=False)


def test_reported_case_is_reproduced():
    """The i5 pair from the xR106 L5G1 report the fix was written for."""
    assert revcomp("AGGCGAAG") == "CTTCGCCT"

    effective = apply_orientation_to_map(load_fixture(), {FIXTURE_DUAL_PROJECT: "rc_i5"})
    p001 = effective[effective["Position"] == "P001"].iloc[0]

    assert p001["index"] == "CGCTCATT", "i7 must not move under rc_i5"
    assert p001["index2_workbook"] == "AGGCGAAG"
    assert p001["index2"] == "CTTCGCCT"

    delivered = f"{p001['Run']}-L{p001['Lane']}-G{p001['Group']}-{p001['Position']}-{p001['index']}-{p001['index2']}-R1.fastq.gz"
    assert delivered == "xR106-L5-G1-P001-CGCTCATT-CTTCGCCT-R1.fastq.gz"


def test_no_decision_is_a_faithful_passthrough():
    """A run with no RC suspects must not perturb a single barcode."""
    original = load_fixture()
    effective = apply_orientation_to_map(original, {})

    pd.testing.assert_frame_equal(original[SHARED_COLUMNS], effective[SHARED_COLUMNS])
    assert (effective["orientation"] == "original").all()
    assert (effective["index"] == effective["index_workbook"]).all()
    assert (effective["index2"] == effective["index2_workbook"]).all()


def test_each_orientation_touches_only_its_own_columns():
    original = load_fixture()
    hit = original["Sample_Project"] == FIXTURE_DUAL_PROJECT

    for orientation, columns in RC_ORIENTATION_COLUMNS.items():
        effective = apply_orientation_to_map(original, {FIXTURE_DUAL_PROJECT: orientation})
        for column in ("index", "index2"):
            if column in columns:
                expected = original.loc[hit, column].map(revcomp)
                assert (effective.loc[hit, column] == expected).all(), \
                    f"{orientation} did not flip {column}"
            else:
                assert (effective[column] == original[column]).all(), \
                    f"{orientation} wrongly changed {column}"


def test_undecided_projects_keep_workbook_barcodes():
    """pick_orientation only records suspects; everything else defaults to original."""
    original = load_fixture()
    effective = apply_orientation_to_map(original, {FIXTURE_DUAL_PROJECT: "rc_i5"})

    other = effective["Sample_Project"] == FIXTURE_SINGLE_PROJECT
    assert other.any()
    assert (effective.loc[other, "orientation"] == "original").all()
    assert (effective.loc[other, "index"] == original.loc[other, "index"]).all()
    assert (effective.loc[other, "index2"] == original.loc[other, "index2"]).all()


def test_blank_i5_stays_blank():
    """Single-index and 10x rows carry no i5; revcomp('') must not invent one."""
    original = load_fixture()
    blank = original["index2"].str.strip() == ""
    assert blank.any(), "fixture must cover single-index rows"

    decision = {p: "rc_both" for p in original["Sample_Project"].unique()}
    effective = apply_orientation_to_map(original, decision)

    assert (effective.loc[blank, "index2"].str.strip() == "").all()
    assert (effective.loc[blank, "index"] == original.loc[blank, "index"].map(revcomp)).all()


def test_flipping_twice_restores_the_workbook_barcode():
    original = load_fixture()
    once = apply_orientation_to_map(original, {FIXTURE_DUAL_PROJECT: "rc_both"})
    twice = apply_orientation_to_map(once[SHARED_COLUMNS], {FIXTURE_DUAL_PROJECT: "rc_both"})

    pd.testing.assert_frame_equal(original[SHARED_COLUMNS], twice[SHARED_COLUMNS])


def test_live_run_lanes_without_rc_are_unchanged():
    """Same invariant against whatever real run is checked out, if any."""
    lanes = live_run_lanes()
    if not lanes:
        return  # No run directory here; the fixture cases already cover the logic

    checked = 0
    for config_id, map_path, decision_path in lanes:
        if not os.path.exists(decision_path):
            continue
        with open(decision_path) as handle:
            decision = json.load(handle)
        if any(str(v).startswith("rc") for v in decision.values()):
            continue  # This lane legitimately changes barcodes
        original = pd.read_csv(map_path, dtype=str, keep_default_na=False)
        effective = apply_orientation_to_map(original, decision)
        pd.testing.assert_frame_equal(original[SHARED_COLUMNS], effective[SHARED_COLUMNS])
        checked += 1
    print(f"    checked {checked} live lane(s) with no RC decision")
