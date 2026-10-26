"""Renaming maps and sample sheets are published atomically and read with retries.

generate_lane_samplesheets runs at parse time in every Snakemake process, so these
files are rewritten while sibling processes read them. xR123's publish lost lane 8
when a spawned job parsed an empty renaming_map_lane8.csv mid-rewrite and then had
no rule for send_order_email_1026I_31.
"""
import csv
import os
import threading
import time
from io import StringIO
from pathlib import Path

import pandas as pd

from _helpers import FIXTURE_MAP, REPO, _exec_source


def _load():
    with open(os.path.join(REPO, "src", "workflow_defs.smk")) as handle:
        source = handle.read()
    start = source.index("# generate_lane_samplesheets runs at parse time")
    end = source.index("# Shared with the standalone scripts", start)
    return _exec_source(source[start:end], {"pd": pd, "csv": csv, "StringIO": StringIO})


_ns = _load()
write_text_atomic = _ns["write_text_atomic"]
atomic_text_writer = _ns["atomic_text_writer"]
read_renaming_map = _ns["read_renaming_map"]
write_renaming_map = _ns["write_renaming_map"]


def _leftovers(directory, name):
    return [f for f in os.listdir(directory) if f.startswith(f".{name}.")]


def test_unchanged_content_is_not_rewritten(tmp_path):
    tmp_path = Path(tmp_path)  # tests/run_tests.py passes a str
    path = tmp_path / "renaming_map_lane1.csv"
    path.write_text("a,b\n1,2\n")
    os.utime(path, (1_000_000, 1_000_000))
    before = os.stat(path)

    write_text_atomic(str(path), "a,b\n1,2\n")

    after = os.stat(path)
    assert (after.st_ino, after.st_mtime) == (before.st_ino, before.st_mtime)


def test_changed_content_is_replaced_whole(tmp_path):
    tmp_path = Path(tmp_path)  # tests/run_tests.py passes a str
    path = tmp_path / "renaming_map_lane1.csv"
    path.write_text("old\n")
    os.chmod(path, 0o664)
    before = os.stat(path)

    write_text_atomic(str(path), "a,b\n1,2\n")

    after = os.stat(path)
    assert path.read_text() == "a,b\n1,2\n"
    assert after.st_ino != before.st_ino  # renamed into place, not truncated
    assert after.st_mode & 0o777 == 0o664
    assert _leftovers(tmp_path, path.name) == []


def test_failed_block_leaves_original_intact(tmp_path):
    tmp_path = Path(tmp_path)  # tests/run_tests.py passes a str
    path = tmp_path / "SampleSheet_lane1.csv"
    path.write_text("[Header]\noriginal\n")
    try:
        with atomic_text_writer(str(path)) as f:
            f.write("[Header]\n")
            raise RuntimeError("boom")
    except RuntimeError:
        pass
    assert path.read_text() == "[Header]\noriginal\n"
    assert _leftovers(tmp_path, path.name) == []


def test_writer_matches_plain_file_output(tmp_path):
    tmp_path = Path(tmp_path)  # tests/run_tests.py passes a str
    df = pd.DataFrame({"Lane": [1, 1], "Sample_ID": ["s1", "s2"]})
    plain = tmp_path / "plain.csv"
    with open(plain, "w") as f:
        f.write("[BCLConvert_Data]\n")
        df.to_csv(f, index=False)
    atomic = tmp_path / "atomic.csv"
    with atomic_text_writer(str(atomic)) as f:
        f.write("[BCLConvert_Data]\n")
        df.to_csv(f, index=False)
    assert atomic.read_bytes() == plain.read_bytes()


def test_write_renaming_map_round_trips_fixture(tmp_path):
    tmp_path = Path(tmp_path)  # tests/run_tests.py passes a str
    src = pd.read_csv(FIXTURE_MAP, dtype=str, keep_default_na=False)
    out = tmp_path / "lane5" / "renaming_map_lane5.csv"
    out.parent.mkdir()
    write_renaming_map(src.copy(), str(out))
    back = pd.read_csv(out, dtype=str, keep_default_na=False)
    assert list(back["Sample_Name"]) == list(src["Sample_Name"])
    assert list(back["Position"]) == list(src["Position"])


def test_reader_gives_up_on_empty_file(tmp_path):
    tmp_path = Path(tmp_path)  # tests/run_tests.py passes a str
    path = tmp_path / "renaming_map_lane8.csv"
    path.write_text("")
    started = time.monotonic()
    assert read_renaming_map(str(path), attempts=3, delay=0.05) is None
    assert time.monotonic() - started >= 0.1  # it did retry


def test_reader_waits_out_a_rewrite_window(tmp_path):
    tmp_path = Path(tmp_path)  # tests/run_tests.py passes a str
    """The xR123 failure: the file is empty when first read, complete shortly after."""
    path = tmp_path / "renaming_map_lane8.csv"
    path.write_text("")

    def finish_rewrite():
        time.sleep(0.15)
        write_text_atomic(str(path), "Sample_Project,Lane\nPlikM_10xVisiumHD_2plex,8\n")

    writer = threading.Thread(target=finish_rewrite)
    writer.start()
    df = read_renaming_map(str(path), attempts=10, delay=0.05)
    writer.join()
    assert df is not None
    assert list(df["Sample_Project"]) == ["PlikM_10xVisiumHD_2plex"]


def test_reader_waits_for_a_deleted_output(tmp_path):
    tmp_path = Path(tmp_path)  # tests/run_tests.py passes a str
    """Snakemake deletes a job's outputs before it runs, so the map can be absent."""
    path = tmp_path / "renaming_map_lane8.csv"

    def recreate():
        time.sleep(0.15)
        write_text_atomic(str(path), "Sample_Project,Lane\nGaneA_10xVisiumHD_2plex,8\n")

    writer = threading.Thread(target=recreate)
    writer.start()
    df = read_renaming_map(str(path), attempts=10, delay=0.05)
    writer.join()
    assert df is not None and len(df) == 1
