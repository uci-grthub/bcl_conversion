"""scripts/backfill_rc_barcode_names.py, against a synthetic run root.

Repairs runs that already shipped with the workbook barcode in the filename.
The dangerous parts are that it must not touch checksums, must not leave a stale
stem in a client-facing artifact, and must never move reads between samples.
"""
import json
import os
import subprocess
import sys

import pandas as pd

from _helpers import (FIXTURE_DELIVERED_DIR, FIXTURE_DUAL_PROJECT, FIXTURE_MAP,
                      FIXTURE_ORDER_ID, REPO, revcomp)
from rename_pipeline_outputs import _row_parts

SCRIPT = os.path.join(REPO, "scripts", "backfill_rc_barcode_names.py")
CONFIG_ID = "lane5"


def fixture_rows(project=FIXTURE_DUAL_PROJECT):
    frame = pd.read_csv(FIXTURE_MAP, dtype=str, keep_default_na=False)
    return frame[frame["Sample_Project"] == project].to_dict("records")


def build_run(root, decision):
    """A finished run: delivered FASTQs, plots, fastp output, md5s and a report."""
    rows = fixture_rows()
    os.makedirs(os.path.join(root, "results", CONFIG_ID), exist_ok=True)
    os.makedirs(os.path.join(root, "logs", CONFIG_ID), exist_ok=True)
    pd.read_csv(FIXTURE_MAP, dtype=str, keep_default_na=False).to_csv(
        os.path.join(root, "results", CONFIG_ID, f"renaming_map_{CONFIG_ID}.csv"),
        index=False)
    with open(os.path.join(root, "logs", CONFIG_ID,
                           f"orientation_decision_{CONFIG_ID}.json"), "w") as handle:
        json.dump(decision, handle)

    out_dir = os.path.join(root, "output", CONFIG_ID, FIXTURE_DELIVERED_DIR)
    res_dir = os.path.join(root, "results", CONFIG_ID, FIXTURE_DELIVERED_DIR)
    plots_dir = os.path.join(out_dir, "plots")
    for path in (out_dir, res_dir, plots_dir):
        os.makedirs(path, exist_ok=True)

    md5_lines, stems = [], []
    for index, row in enumerate(rows):
        prefix, barcode, _lane, _project, _sample = _row_parts(row)
        stem = f"{prefix}-{barcode}"
        stems.append(stem)
        for read in ("R1", "R2"):
            open(os.path.join(out_dir, f"{stem}-{read}.fastq.gz"), "w").close()
            md5_lines.append(f"{index:032x}  ./{stem}-{read}.fastq.gz")
        for suffix in (".fastp.json", ".fastp.html", "-base_comp.png", "-mean_phred.png"):
            open(os.path.join(res_dir, f"{stem}{suffix}"), "w").close()
        for suffix in ("-base_comp.png", "-mean_phred.png"):
            open(os.path.join(plots_dir, f"{stem}{suffix}"), "w").close()

    md5_text = "\n".join(md5_lines) + "\n"
    with open(os.path.join(out_dir, "md5sums.txt"), "w") as handle:
        handle.write(md5_text)

    order_dir = os.path.join(root, "Reports", f"order_{FIXTURE_ORDER_ID}")
    os.makedirs(order_dir, exist_ok=True)
    with open(os.path.join(order_dir, "md5sums.txt"), "w") as handle:
        handle.write(md5_text)
    with open(os.path.join(order_dir, "index.html"), "w") as handle:
        handle.write("<html><body>"
                     + "".join(f"<h2>{stem}</h2>" for stem in stems)
                     + "</body></html>")
    return rows, stems


def backfill(root, *args):
    result = subprocess.run(
        [sys.executable, SCRIPT, "--run-root", root, "--config-id", CONFIG_ID, *args],
        capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout


def read(path):
    with open(path) as handle:
        return handle.read()


def test_no_rc_decision_is_a_no_op(tmp_path):
    root = str(tmp_path)
    build_run(root, {})
    before = sorted(os.listdir(os.path.join(root, "output", CONFIG_ID, FIXTURE_DELIVERED_DIR)))

    output = backfill(root, "--apply")

    assert "Nothing to do" in output
    assert sorted(os.listdir(os.path.join(root, "output", CONFIG_ID,
                                          FIXTURE_DELIVERED_DIR))) == before


def test_dry_run_changes_nothing(tmp_path):
    root = str(tmp_path)
    build_run(root, {FIXTURE_DUAL_PROJECT: "rc_i5"})
    out_dir = os.path.join(root, "output", CONFIG_ID, FIXTURE_DELIVERED_DIR)
    before = sorted(os.listdir(out_dir))
    before_html = read(os.path.join(root, "Reports", f"order_{FIXTURE_ORDER_ID}", "index.html"))

    output = backfill(root)

    assert "Dry run" in output
    assert sorted(os.listdir(out_dir)) == before
    assert read(os.path.join(root, "Reports", f"order_{FIXTURE_ORDER_ID}",
                             "index.html")) == before_html


def test_apply_flips_i5_and_keeps_positions(tmp_path):
    root = str(tmp_path)
    rows, _stems = build_run(root, {FIXTURE_DUAL_PROJECT: "rc_i5"})
    out_dir = os.path.join(root, "output", CONFIG_ID, FIXTURE_DELIVERED_DIR)
    before = sorted(f for f in os.listdir(out_dir) if f.endswith(".fastq.gz"))

    backfill(root, "--apply")

    after = sorted(f for f in os.listdir(out_dir) if f.endswith(".fastq.gz"))
    assert len(after) == len(before)
    assert len(set(after)) == len(after)

    expected = set()
    for row in rows:
        prefix, _barcode, _lane, _project, _sample = _row_parts(row)
        delivered = f"{row['index']}-{revcomp(row['index2'])}"
        expected.update(f"{prefix}-{delivered}-{read_}.fastq.gz" for read_ in ("R1", "R2"))
    assert set(after) == expected


def test_checksums_are_preserved(tmp_path):
    """File contents never change, so recomputing or dropping md5s would be wrong."""
    root = str(tmp_path)
    build_run(root, {FIXTURE_DUAL_PROJECT: "rc_i5"})
    md5_path = os.path.join(root, "output", CONFIG_ID, FIXTURE_DELIVERED_DIR, "md5sums.txt")
    before_text = read(md5_path)
    before = [line.split()[0] for line in before_text.splitlines() if line.strip()]

    backfill(root, "--apply")

    after_text = read(md5_path)
    # Guard against passing vacuously: the manifest must actually be rewritten.
    assert after_text != before_text, "md5sums.txt was never updated"
    lines = [line for line in after_text.splitlines() if line.strip()]
    assert [line.split()[0] for line in lines] == before, "checksums must not change"

    on_disk = set(os.listdir(os.path.join(root, "output", CONFIG_ID, FIXTURE_DELIVERED_DIR)))
    listed = {line.split()[1].lstrip("./") for line in lines}
    assert listed <= on_disk, f"md5sums names missing from disk: {listed - on_disk}"


def test_no_stale_stem_survives_in_client_artifacts(tmp_path):
    root = str(tmp_path)
    _rows, stems = build_run(root, {FIXTURE_DUAL_PROJECT: "rc_i5"})

    backfill(root, "--apply")

    order_dir = os.path.join(root, "Reports", f"order_{FIXTURE_ORDER_ID}")
    for artifact in ("index.html", "md5sums.txt"):
        content = read(os.path.join(order_dir, artifact))
        for stem in stems:
            assert stem not in content, f"stale stem {stem} left in {artifact}"


def test_derived_artifacts_follow(tmp_path):
    root = str(tmp_path)
    rows, _stems = build_run(root, {FIXTURE_DUAL_PROJECT: "rc_i5"})

    backfill(root, "--apply")

    res_dir = os.path.join(root, "results", CONFIG_ID, FIXTURE_DELIVERED_DIR)
    plots_dir = os.path.join(root, "output", CONFIG_ID, FIXTURE_DELIVERED_DIR, "plots")
    for row in rows:
        prefix, _barcode, _lane, _project, _sample = _row_parts(row)
        delivered = f"{prefix}-{row['index']}-{revcomp(row['index2'])}"
        for suffix in (".fastp.json", ".fastp.html", "-base_comp.png", "-mean_phred.png"):
            assert os.path.exists(os.path.join(res_dir, f"{delivered}{suffix}")), suffix
        for suffix in ("-base_comp.png", "-mean_phred.png"):
            assert os.path.exists(os.path.join(plots_dir, f"{delivered}{suffix}")), suffix


def test_apply_is_idempotent(tmp_path):
    root = str(tmp_path)
    build_run(root, {FIXTURE_DUAL_PROJECT: "rc_i5"})
    out_dir = os.path.join(root, "output", CONFIG_ID, FIXTURE_DELIVERED_DIR)

    backfill(root, "--apply")
    settled = sorted(os.listdir(out_dir))
    md5_after_first = read(os.path.join(out_dir, "md5sums.txt"))

    output = backfill(root, "--apply")

    assert "Applied 0 rename(s)." in output
    assert sorted(os.listdir(out_dir)) == settled
    assert read(os.path.join(out_dir, "md5sums.txt")) == md5_after_first


def test_forced_orientation_covers_runs_without_a_decision_file(tmp_path):
    root = str(tmp_path)
    rows, _stems = build_run(root, {})
    os.remove(os.path.join(root, "logs", CONFIG_ID,
                           f"orientation_decision_{CONFIG_ID}.json"))

    backfill(root, "--project", FIXTURE_DUAL_PROJECT,
             "--force-orientation", "rc_i5", "--apply")

    out_dir = os.path.join(root, "output", CONFIG_ID, FIXTURE_DELIVERED_DIR)
    names = set(os.listdir(out_dir))
    for row in rows:
        prefix, _barcode, _lane, _project, _sample = _row_parts(row)
        assert f"{prefix}-{row['index']}-{revcomp(row['index2'])}-R1.fastq.gz" in names


def test_writes_an_audit_log(tmp_path):
    root = str(tmp_path)
    build_run(root, {FIXTURE_DUAL_PROJECT: "rc_i5"})

    backfill(root, "--apply")

    logs = [f for f in os.listdir(os.path.join(root, "logs"))
            if f.startswith("backfill_rc_names_") and f.endswith(".json")]
    assert logs, "no audit log written"
    with open(os.path.join(root, "logs", logs[0])) as handle:
        audit = json.load(handle)
    assert audit["applied"] is True
    assert audit["config_id"] == CONFIG_ID
    assert audit["decision"] == {FIXTURE_DUAL_PROJECT: "rc_i5"}
    renames = audit["projects"][0]["renames"]
    assert renames and all(r["old"] != r["new"] for r in renames)
