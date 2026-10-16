"""NUM_READS follows RunInfo.xml rather than a config value that can drift from it."""
import os
import xml.etree.ElementTree as ET

from _helpers import load_snakefile_function, load_workflow_defs_function

RUNINFO = """<?xml version="1.0"?>
<RunInfo><Run><Reads>
{reads}
</Reads></Run></RunInfo>
"""


def _count():
    fn = load_snakefile_function(
        "_runinfo_data_read_count", "# End of _runinfo_data_read_count."
    )
    # The Snakefile sees get_run_read_lengths through `include:`; supply the real one.
    reader = load_workflow_defs_function(
        "get_run_read_lengths", "def generate_lane_samplesheets("
    )
    reader.__globals__["ET"] = ET
    fn.__globals__["get_run_read_lengths"] = reader
    return fn


def _write(tmp_path, reads):
    lines = "\n".join(
        f'<Read Number="{i + 1}" NumCycles="{n}" IsIndexedRead="{ix}"/>'
        for i, (n, ix) in enumerate(reads)
    )
    path = os.path.join(str(tmp_path), "RunInfo.xml")
    with open(path, "w") as handle:
        handle.write(RUNINFO.format(reads=lines))
    return path


def test_single_read_with_leading_index_reads(tmp_path):
    """The iR027 layout: I8;I8;Y151 is one data read, not two."""
    path = _write(tmp_path, [(8, "Y"), (8, "Y"), (151, "N")])
    assert _count()(path) == 1


def test_paired_end(tmp_path):
    path = _write(tmp_path, [(151, "N"), (10, "Y"), (10, "Y"), (151, "N")])
    assert _count()(path) == 2


def test_missing_runinfo_defers_to_config(tmp_path):
    assert _count()(os.path.join(str(tmp_path), "absent.xml")) is None
