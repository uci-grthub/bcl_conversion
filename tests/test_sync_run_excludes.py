"""Tests for the rsync exclude list in scripts/sync_run.sh.

The excludes are read out of the shipped script and handed to a real rsync, so
these tests exercise what publish actually runs rather than a copy of it.

Motivation: `--exclude 'Reports'` (unanchored) matches any path component named
Reports at any depth. It was meant for the run-root Reports/ -- the order
reports, rebuilt in the mirror -- but it also stripped output/*/Reports and
.output/*/Reports, where DRAGEN writes Demultiplex_Stats.csv. That file is the
only source of the read counts in the order reports.

It bit twice, in two different ways, before it was anchored. Under sweeps/ the
demux reports never arrived at all, because the variants are carried solely by
this pass, and every sample in a published variant's report read "N/A". For the
run's own output/ the parallel pass copied the directories once with no
excludes, so the damage was narrower and slower: a lane re-demuxed after its
subdir had transferred kept the pre-demux stats, and only lane 3 of xR111 --
whose barcodes changed with the re-demux, so the stale rows stopped matching --
showed N/A rather than confidently printing the old numbers.
"""
import os
import re
import shutil
import subprocess

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SYNC_RUN = os.path.join(REPO, "scripts", "sync_run.sh")


def metadata_pass_excludes():
    """The --exclude patterns on the single-pass rsync that copies everything else.

    The parallel output/ pass deliberately runs without excludes; this is the
    pass whose patterns decide what the mirror is allowed to refresh.
    """
    lines = open(SYNC_RUN).read().splitlines()
    # Matched on the flag rather than the whole invocation: the rsync options
    # themselves change (-aW gained -H when the mirror started being deduped),
    # and that must not silently stop this test from finding the pass.
    starts = [i for i, line in enumerate(lines)
              if line.lstrip().startswith(("rsync", "if ! rsync")) and "--info=progress2" in line]
    assert len(starts) == 1, f"expected one metadata-pass rsync, found {len(starts)}"
    start = starts[0]
    patterns = []
    for line in lines[start:]:
        if '"$src/" "$dest/"' in line:
            break
        found = re.search(r"--exclude\s+'([^']*)'", line)
        if found:
            patterns.append(found.group(1))
    assert patterns, "no --exclude patterns found in the metadata pass"
    return patterns


def build_fixture(root):
    """A run tree holding one of each thing the excludes have an opinion about."""
    files = {
        "Reports/order_1/index.html": "run-root order report",
        "output/lane1/Reports/Demultiplex_Stats.csv": "per-lane demux stats",
        "output/lane1/Proj_A/S1_L001_R1_001.fastq.gz": "payload",
        ".output/lane1/Reports/Demultiplex_Stats.csv": "per-lane demux stats (work dir)",
        "sweeps/variant_A/Reports/order_1/index.html": "variant order report",
        "sweeps/variant_A/output/lane1/Reports/Demultiplex_Stats.csv": "variant demux stats",
        ".snakemake/metadata/whatever": "snakemake provenance",
        "logs/lane1/project_links_lane1.yaml": "link log",
        "results/lane1/SampleSheet_lane1.csv": "samplesheet",
    }
    for rel, text in files.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write(text)
    return files


def run_sync(tmp_path):
    src = os.path.join(str(tmp_path), "src")
    dest = os.path.join(str(tmp_path), "dest")
    os.makedirs(src, exist_ok=True)
    os.makedirs(dest, exist_ok=True)
    build_fixture(src)

    cmd = ["rsync", "-aW"]
    for pattern in metadata_pass_excludes():
        cmd += ["--exclude", pattern]
    cmd += [src + "/", dest + "/"]
    subprocess.run(cmd, check=True, capture_output=True)

    arrived = set()
    for dirpath, _dirnames, filenames in os.walk(dest):
        for name in filenames:
            arrived.add(os.path.relpath(os.path.join(dirpath, name), dest))
    return arrived


def test_per_lane_demux_stats_reach_the_mirror(tmp_path):
    """The regression: these carry the read counts the order reports print."""
    arrived = run_sync(tmp_path)
    assert "output/lane1/Reports/Demultiplex_Stats.csv" in arrived, arrived
    assert ".output/lane1/Reports/Demultiplex_Stats.csv" in arrived, arrived
    assert "sweeps/variant_A/output/lane1/Reports/Demultiplex_Stats.csv" in arrived, arrived


def test_run_root_reports_is_still_excluded(tmp_path):
    """Anchoring the pattern must not stop excluding what it was added for."""
    arrived = run_sync(tmp_path)
    assert "Reports/order_1/index.html" not in arrived, arrived
    assert "sweeps/variant_A/Reports/order_1/index.html" not in arrived, arrived


def test_reports_exclude_is_anchored(tmp_path):
    """Guards the leading slash itself, so the fix cannot be undone by a tidy-up."""
    patterns = metadata_pass_excludes()
    assert "/Reports" in patterns
    assert "/sweeps/*/Reports" in patterns
    # The bare pattern is the bug: it matches at any depth.
    assert "Reports" not in patterns


def test_other_excludes_are_unchanged(tmp_path):
    arrived = run_sync(tmp_path)
    assert not any(p.startswith(".snakemake") for p in arrived), arrived
    assert "results/lane1/SampleSheet_lane1.csv" in arrived, arrived
    assert "output/lane1/Proj_A/S1_L001_R1_001.fastq.gz" in arrived, arrived
    assert "logs/lane1/project_links_lane1.yaml" not in arrived, arrived
