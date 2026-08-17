"""The operator-facing RC notice: the summary CSV and the email subject tag.

The manager needs to know an i5 reverse-complement workflow ran for a project at
the time reports go out, so he can add his own wording for the client. Nothing
here may change what the client reads.
"""
import json
import os

import pandas as pd

from _helpers import (FIXTURE_DUAL_PROJECT, FIXTURE_MAP, FIXTURE_ORDER_ID, Stub,
                      load_rule_body, load_snakefile_function,
                      load_workflow_defs_helpers)

apply_orientation_to_map = load_workflow_defs_helpers()["apply_orientation_to_map"]
rc_orientation_tag = load_snakefile_function("rc_orientation_tag",
                                             end_marker="rule rc_orientation_summary:")
SUMMARY_BODY = load_rule_body("rc_orientation_summary",
                              end_marker="rule generate_effective_renaming_map:")

SUMMARY_COLUMNS = ["order_id", "config_id", "project", "group", "orientation",
                   "workbook_i7", "delivered_i7", "workbook_i5", "delivered_i5",
                   "rc_fraction", "n_samples"]


def summary_row(order_id, orientation):
    row = {column: "" for column in SUMMARY_COLUMNS}
    row.update(order_id=order_id, orientation=orientation, config_id="lane5",
               project="P", n_samples=11)
    return row


def write_summary(root, rows):
    os.makedirs(os.path.join(root, "Reports"), exist_ok=True)
    pd.DataFrame(rows, columns=SUMMARY_COLUMNS).to_csv(
        os.path.join(root, "Reports", "rc_orientation_summary.csv"), index=False)


def in_dir(path, func):
    previous = os.getcwd()
    os.chdir(path)
    try:
        return func()
    finally:
        os.chdir(previous)


# --- subject tag ------------------------------------------------------------

def test_tag_is_empty_without_a_summary(tmp_path):
    assert in_dir(str(tmp_path), lambda: rc_orientation_tag(FIXTURE_ORDER_ID)) == ""


def test_tag_is_empty_when_no_project_was_flipped(tmp_path):
    write_summary(str(tmp_path), [])
    assert in_dir(str(tmp_path), lambda: rc_orientation_tag(FIXTURE_ORDER_ID)) == ""


def test_tag_names_the_flipped_index(tmp_path):
    write_summary(str(tmp_path), [
        summary_row("0626I-49", "rc_i5"),
        summary_row("0726I-08", "rc_i7"),
        summary_row("0726I-30", "rc_both"),
        summary_row("0726I-44", "rc_i5"),
        summary_row("0726I-44", "rc_i7"),   # one order, two projects, two flavours
    ])
    expected = {
        "0626I-49": " [i5 reverse-complement applied]",
        "0726I-08": " [i7 reverse-complement applied]",
        "0726I-30": " [i7+i5 reverse-complement applied]",
        "0726I-44": " [i7+i5 reverse-complement applied]",
        "0626I-25": "",   # an order with no RC project stays untagged
    }
    got = in_dir(str(tmp_path),
                 lambda: {order: rc_orientation_tag(order) for order in expected})
    assert got == expected


# --- summary CSV ------------------------------------------------------------

def build_run(root, decisions):
    """A run root with an effective map, decision and candidates per lane."""
    original = pd.read_csv(FIXTURE_MAP, dtype=str, keep_default_na=False)
    for config_id, decision in decisions.items():
        os.makedirs(os.path.join(root, "results", config_id), exist_ok=True)
        os.makedirs(os.path.join(root, "logs", config_id), exist_ok=True)
        apply_orientation_to_map(original, decision).to_csv(
            os.path.join(root, "results", config_id,
                         f"renaming_map_{config_id}_effective.csv"), index=False)
        with open(os.path.join(root, "logs", config_id,
                               f"orientation_decision_{config_id}.json"), "w") as handle:
            json.dump(decision, handle)
        candidates = [{"config_id": config_id, "project": project,
                       "expected_pair": "CGCTCATT+AGGCGAAG", "total_hits": 5000,
                       "rc_hits": 4800, "rc_fraction": 0.96,
                       "fix_type": orientation.replace("rc_", "") + "_rc"}
                      for project, orientation in decision.items()]
        with open(os.path.join(root, "logs", config_id,
                               f"rc_candidates_{config_id}.json"), "w") as handle:
            json.dump(candidates, handle)
    os.makedirs(os.path.join(root, "Reports"), exist_ok=True)


def run_summary_rule(root, config_ids, order_lookup):
    namespace = {
        "os": os, "pd": pd,
        "CONFIG_IDS": config_ids,
        "ORDER_ID_LOOKUP": order_lookup,
        "input": Stub(
            decisions=[f"logs/{c}/orientation_decision_{c}.json" for c in config_ids],
            candidates=[f"logs/{c}/rc_candidates_{c}.json" for c in config_ids],
            maps=[f"results/{c}/renaming_map_{c}_effective.csv" for c in config_ids]),
        "output": Stub(csv="Reports/rc_orientation_summary.csv"),
        "log": ["logs/rc_orientation_summary.log"],
    }
    in_dir(root, lambda: exec(SUMMARY_BODY, namespace))
    return pd.read_csv(os.path.join(root, "Reports", "rc_orientation_summary.csv"),
                       dtype=str, keep_default_na=False)


def test_summary_lists_only_flipped_projects(tmp_path):
    root = str(tmp_path)
    build_run(root, {"lane5": {FIXTURE_DUAL_PROJECT: "rc_i5"}, "lane6": {}})

    frame = run_summary_rule(root, ["lane5", "lane6"],
                             {(5, 1): FIXTURE_ORDER_ID, (5, 2): "0626I-57"})

    assert list(frame.columns) == SUMMARY_COLUMNS
    assert len(frame) == 1, "the clean lane must contribute no rows"
    row = frame.iloc[0]
    assert row["config_id"] == "lane5"
    assert row["project"] == FIXTURE_DUAL_PROJECT
    assert row["orientation"] == "rc_i5"
    assert row["order_id"] == FIXTURE_ORDER_ID
    assert row["group"] == "1"
    assert row["n_samples"] == "3"
    assert row["rc_fraction"] == "0.9600"
    assert row["workbook_i7"] == row["delivered_i7"] == "CGCTCATT"
    assert row["workbook_i5"] == "AGGCGAAG"
    assert row["delivered_i5"] == "CTTCGCCT"


def test_summary_is_empty_when_nothing_was_flipped(tmp_path):
    root = str(tmp_path)
    build_run(root, {"lane5": {}})

    frame = run_summary_rule(root, ["lane5"], {(5, 1): FIXTURE_ORDER_ID})

    assert frame.empty
    assert list(frame.columns) == SUMMARY_COLUMNS, "header must survive an empty run"


def test_summary_feeds_the_subject_tag(tmp_path):
    """End to end: the rule's output is what the email subject reads."""
    root = str(tmp_path)
    build_run(root, {"lane5": {FIXTURE_DUAL_PROJECT: "rc_both"}})
    run_summary_rule(root, ["lane5"], {(5, 1): FIXTURE_ORDER_ID})

    tag = in_dir(root, lambda: rc_orientation_tag(FIXTURE_ORDER_ID))
    assert tag == " [i7+i5 reverse-complement applied]"
    assert in_dir(root, lambda: rc_orientation_tag("0999I-99")) == ""
