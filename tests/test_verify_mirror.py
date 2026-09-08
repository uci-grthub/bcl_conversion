"""Tests for scripts/verify_mirror.py.

The script is loaded from its shipped path rather than reimplemented here, so
these tests fail if the real publish-time check changes behaviour.

The case that motivated them: calculate_md5sums writes md5sums.txt through a
shell redirect, so the file is truncated for as long as the checksum job runs.
Every other check in verify_mirror is driven by that listing, which means a
short one does not fail verification -- it quietly shrinks it.
"""
import hashlib
import importlib.util
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_verify_mirror():
    path = os.path.join(REPO, "scripts", "verify_mirror.py")
    spec = importlib.util.spec_from_file_location("verify_mirror_under_test", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def make_run(root, fastqs, md5_lines="all"):
    """Build a minimal run tree: <root>/output/lane1/Proj_A/{*.fastq.gz,md5sums.txt}.

    fastqs maps filename -> bytes. md5_lines is "all", "none", or a list of the
    filenames to record, so a caller can model a half-written listing.
    """
    project = os.path.join(root, "output", "lane1", "Proj_A")
    os.makedirs(project, exist_ok=True)
    for name, payload in fastqs.items():
        with open(os.path.join(project, name), "wb") as fh:
            fh.write(payload)

    if md5_lines == "all":
        recorded = list(fastqs)
    elif md5_lines == "none":
        recorded = []
    else:
        recorded = md5_lines

    with open(os.path.join(project, "md5sums.txt"), "w") as fh:
        for name in sorted(recorded):
            digest = hashlib.md5(fastqs[name]).hexdigest()
            fh.write(f"{digest}  ./{name}\n")
    return project


FASTQS = {
    "S1_L001_R1_001.fastq.gz": b"read one payload",
    "S1_L001_R2_001.fastq.gz": b"read two payload",
    "S2_L001_R1_001.fastq.gz": b"read three payload",
}


def check(tmp_path, mirror_kwargs, src_kwargs=None):
    """Run check_project over a fixture and return (problems, n_files)."""
    vm = load_verify_mirror()
    mirror = os.path.join(str(tmp_path), "mirror")
    make_run(mirror, **mirror_kwargs)
    src = None
    if src_kwargs is not None:
        src = os.path.join(str(tmp_path), "src")
        make_run(src, **src_kwargs)

    problems = []
    md5_path = os.path.join(mirror, "output", "lane1", "Proj_A", "md5sums.txt")
    n_files = vm.check_project(md5_path, mirror, src, False, problems)
    return problems, n_files


def test_healthy_project_passes(tmp_path):
    problems, n_files = check(tmp_path, {"fastqs": FASTQS}, {"fastqs": FASTQS})
    assert problems == []
    assert n_files == len(FASTQS)


def test_zero_byte_md5sums_is_flagged(tmp_path):
    """The exact state a killed or in-flight checksum job leaves on disk."""
    vm = load_verify_mirror()
    mirror = os.path.join(str(tmp_path), "mirror")
    project = make_run(mirror, fastqs=FASTQS)
    open(os.path.join(project, "md5sums.txt"), "w").close()

    problems = []
    vm.check_project(os.path.join(project, "md5sums.txt"), mirror, None, False, problems)
    assert len(problems) == 1
    assert "0 bytes" in problems[0]


def test_truncated_listing_is_flagged(tmp_path):
    """A partial md5sums.txt is well-formed, so only the count gives it away."""
    recorded = sorted(FASTQS)[:1]
    problems, _ = check(tmp_path, {"fastqs": FASTQS, "md5_lines": recorded})
    assert any("unlisted" in p for p in problems), problems
    unlisted = [p for p in problems if "unlisted" in p][0]
    for name in sorted(FASTQS)[1:]:
        assert name in unlisted


def test_short_listing_is_flagged_against_the_source(tmp_path):
    """Covers a truncated listing that rsync then copied faithfully."""
    recorded = sorted(FASTQS)[:2]
    problems, _ = check(
        tmp_path,
        {"fastqs": FASTQS, "md5_lines": recorded},
        {"fastqs": FASTQS},
    )
    assert any("source has 3" in p for p in problems), problems


def test_truncation_check_does_not_mask_a_missing_fastq(tmp_path):
    """The original check has to keep working: a listed file that never arrived."""
    vm = load_verify_mirror()
    mirror = os.path.join(str(tmp_path), "mirror")
    project = make_run(mirror, fastqs=FASTQS)
    os.remove(os.path.join(project, sorted(FASTQS)[0]))

    problems = []
    vm.check_project(os.path.join(project, "md5sums.txt"), mirror, None, False, problems)
    assert any(p.endswith(f"missing {sorted(FASTQS)[0]}") for p in problems), problems
