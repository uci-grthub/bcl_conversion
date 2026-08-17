"""restem_by_position: re-point delivered files onto the delivered barcode.

The property that matters is that a re-stem can only ever rename a sample onto
itself. Matching used to key on a substring of the lane/group, which would have
moved one sample's reads onto another sample's name as soon as a barcode changed.
"""
import os
import shutil

import pandas as pd

from _helpers import (FIXTURE_DUAL_PROJECT, FIXTURE_MAP, FIXTURE_RUN, revcomp)
from rename_pipeline_outputs import _row_parts, restem_by_position

READS = ("R1", "R2")
SUFFIXES = ("-R1.fastq.gz", "-R2.fastq.gz", ".fastp.json", ".fastp.html",
            "-base_comp.png", "-mean_phred.png")


def rows_for_project(project=FIXTURE_DUAL_PROJECT):
    frame = pd.read_csv(FIXTURE_MAP, dtype=str, keep_default_na=False)
    return frame[frame["Sample_Project"] == project].to_dict("records")


def seed_directory(tmp_dir, rows):
    """Every delivered artifact for these rows, as empty files."""
    os.makedirs(tmp_dir, exist_ok=True)
    names = []
    for row in rows:
        prefix, barcode, _lane, _project, _sample = _row_parts(row)
        for suffix in SUFFIXES:
            name = f"{prefix}-{barcode}{suffix}"
            open(os.path.join(tmp_dir, name), "w").close()
            names.append(name)
    return sorted(names)


def flip_i5(rows):
    return [dict(row, index2=revcomp(row["index2"])) for row in rows]


def position_of(name):
    return name.split("-")[3]


def test_rename_never_crosses_samples(tmp_path):
    rows = rows_for_project()
    work = os.path.join(str(tmp_path), "project")
    before = seed_directory(work, rows)

    renames = restem_by_position(work, flip_i5(rows))
    after = sorted(os.listdir(work))

    assert len(after) == len(before), "file count changed"
    assert len(set(after)) == len(after), "two files collapsed onto one name"
    assert len(renames) == len(before), "not every artifact was re-stemmed"

    for src, dst in renames:
        assert position_of(os.path.basename(src)) == position_of(os.path.basename(dst))

    # Same set of (position, suffix) slots before and after: nothing lost or moved.
    def slots(names):
        return {(position_of(n), next(s for s in SUFFIXES if n.endswith(s))) for n in names}

    assert slots(before) == slots(after)


def test_delivered_names_match_the_map(tmp_path):
    rows = rows_for_project()
    work = os.path.join(str(tmp_path), "project")
    seed_directory(work, rows)
    flipped = flip_i5(rows)

    restem_by_position(work, flipped)

    expected = set()
    for row in flipped:
        prefix, barcode, _lane, _project, _sample = _row_parts(row)
        expected.update(f"{prefix}-{barcode}{suffix}" for suffix in SUFFIXES)
    assert set(os.listdir(work)) == expected


def test_is_idempotent_and_reversible(tmp_path):
    rows = rows_for_project()
    work = os.path.join(str(tmp_path), "project")
    before = seed_directory(work, rows)
    flipped = flip_i5(rows)

    restem_by_position(work, flipped)
    assert restem_by_position(work, flipped) == [], "second pass renamed something"

    restem_by_position(work, rows)
    assert sorted(os.listdir(work)) == before, "round trip did not restore the names"


def test_single_index_rows_survive(tmp_path):
    """A blank i5 means the stem ends at the i7; the suffix must still be found."""
    rows = rows_for_project("SoloS_Amplicon_2plex")
    work = os.path.join(str(tmp_path), "project")
    seed_directory(work, rows)

    flipped = [dict(row, index=revcomp(row["index"])) for row in rows]
    renames = restem_by_position(work, flipped)

    assert len(renames) == len(rows) * len(SUFFIXES)
    for name in os.listdir(work):
        assert "--" not in name, f"blank i5 left an empty barcode field: {name}"
        assert position_of(name).startswith("P")


def test_leaves_foreign_files_alone(tmp_path):
    """Files belonging to another lane, group or sample must not be touched."""
    rows = rows_for_project()
    work = os.path.join(str(tmp_path), "project")
    seed_directory(work, rows)

    foreign = [
        f"{FIXTURE_RUN}-L6-G1-P001-CGCTCATT-AGGCGAAG-R1.fastq.gz",   # other lane
        f"{FIXTURE_RUN}-L5-G11-P001-CGCTCATT-AGGCGAAG-R1.fastq.gz",  # G11, not G1
        f"{FIXTURE_RUN}-L5-G1-P0011-CGCTCATT-AGGCGAAG-R1.fastq.gz",  # P0011, not P001
        "md5sums.txt",
        "Undetermined_S0_L005_R1_001.fastq.gz",
    ]
    for name in foreign:
        open(os.path.join(work, name), "w").close()

    restem_by_position(work, flip_i5(rows))

    for name in foreign:
        assert os.path.exists(os.path.join(work, name)), f"{name} was renamed"


def test_missing_directory_is_not_an_error(tmp_path):
    assert restem_by_position(os.path.join(str(tmp_path), "nope"), rows_for_project()) == []


def test_dry_run_writes_nothing(tmp_path):
    rows = rows_for_project()
    work = os.path.join(str(tmp_path), "project")
    before = seed_directory(work, rows)

    planned = restem_by_position(work, flip_i5(rows), dry_run=True)

    assert planned, "dry run reported no work"
    assert sorted(os.listdir(work)) == before, "dry run modified the directory"
