"""scripts/resolve_fqtk_barcodes.py --override.

xR128 lane 5: the dominant Undetermined form starting GTAGAG was MartJ_BGS10's
GTAGAGGA, so measuring LuptA Pool_9 hit the identical-to-sheet-index check. An
override sets the barcode by hand and skips measuring it.
"""
import gzip
import os
import subprocess
import sys
from pathlib import Path

from _helpers import REPO

SCRIPT = os.path.join(REPO, "scripts", "resolve_fqtk_barcodes.py")


def _setup(tmp_path):
    tmp_path = Path(tmp_path)
    (tmp_path / "bc.tsv").write_text("sample_id\tbarcode\nPool_9\tGTAGAG\nPool_1\tCGATGT\n")
    reads = ["GTAGAGGA"] * 20 + ["GTAGAGAT"] * 3 + ["CGATGTAT"] * 5
    with gzip.open(tmp_path / "i1.fq.gz", "wt") as f:
        for n, seq in enumerate(reads):
            f.write(f"@r{n}\n{seq}\n+\n{'F' * 8}\n")
    (tmp_path / "ss.csv").write_text("[Data]\nLane,Sample_ID,index,index2\n5,S1,GTAGAGGA,GCGATCTA\n")


def _run(tmp_path, *extra):
    tmp_path = Path(tmp_path)
    return subprocess.run(
        [sys.executable, SCRIPT, "--barcodes", str(tmp_path / "bc.tsv"),
         "--undetermined-i1", str(tmp_path / "i1.fq.gz"), "--samplesheet", str(tmp_path / "ss.csv"),
         "--output", str(tmp_path / "out.tsv"), *extra],
        capture_output=True, text=True)


def test_dominant_form_matching_a_sheet_index_fails(tmp_path):
    _setup(tmp_path)
    res = _run(tmp_path)
    assert res.returncode == 1
    assert "Pool_9: resolved barcode GTAGAGGA is identical to sheet index GTAGAGGA" in res.stderr


def test_override_sets_barcode_and_others_are_still_measured(tmp_path):
    _setup(tmp_path)
    res = _run(tmp_path, "--override", "Pool_9=GTAGAGAT")
    assert res.returncode == 0, res.stderr
    rows = dict(line.split("\t") for line in (Path(tmp_path) / "out.tsv").read_text().splitlines()[1:])
    assert rows["Pool_9"] == "GTAGAGAT"
    assert rows["Pool_1"] == "CGATGTAT"
    assert rows["decoy__GTAGAGGA"] == "GTAGAGGA"


def test_override_must_extend_the_sheet_barcode(tmp_path):
    _setup(tmp_path)
    res = _run(tmp_path, "--override", "Pool_9=GTAGTTAT")
    assert res.returncode == 1
    assert "must be 8bp and extend the sheet barcode GTAGAG" in res.stderr


def test_override_for_unknown_sample_fails(tmp_path):
    _setup(tmp_path)
    res = _run(tmp_path, "--override", "Pool_99=GTAGAGAT")
    assert res.returncode == 1
    assert "no sample 'Pool_99'" in res.stderr
