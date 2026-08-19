"""Detect index collisions DRAGEN cannot resolve and route them to post-hoc demux.

When two samples on a lane carry indexes of different lengths and the shorter one
matches the longer one over its whole length (GTAGAG vs GTAGAGGA), a read carrying
the longer index matches both samples exactly. DRAGEN compares mixed-length indexes
at their "common value" and aborts the whole lane:

    Sample Sheet Error: hamming distance errors occurred in the Sample Sheet

No BarcodeMismatchesIndex value fixes this -- 0 mismatches still matches both.

Splitting the lane into two BCL Convert passes does NOT fix it either: with the
long-index sample absent from a pass, its reads match the short index exactly and
are silently written into the short-index sample's FASTQ. That trades a loud abort
for a contaminated deliverable.

What does work is dropping the *shorter* index sample from the sheet and letting
DRAGEN assign the longer, more specific index first. The short-index sample's reads
fall through to Undetermined, which DRAGEN writes at the run's native read structure
(full-length reads and full-length index reads, regardless of any per-sample
OverrideCycles masking), and are recovered afterwards by fqtk. Reads only leak into
the recovered sample if the long-index sample failed its own assignment first.

Routing is decided from the sample sheet alone, so a run needs no annotation in the
metadata workbook to reach the fqtk path.
"""

from collections import defaultdict


def is_prefix_collision(seq1, seq2):
    """True when two indexes differ in length but agree over the common prefix.

    This is the unresolvable case: the shorter index is indistinguishable from the
    longer one at any mismatch tolerance.
    """
    if not seq1 or not seq2 or len(seq1) == len(seq2):
        return False
    n = min(len(seq1), len(seq2))
    return seq1[:n] == seq2[:n]


def _get(row, key):
    """Read a column from a dict row or a pandas Series, tolerating NaN."""
    try:
        value = row[key]
    except (KeyError, IndexError):
        return ""
    if value is None:
        return ""
    text = str(value).strip()
    return "" if text.lower() == "nan" else text


def sample_label(row):
    name = _get(row, "Sample_Name") or _get(row, "Sample_ID")
    project = _get(row, "Sample_Project")
    return f"{project}/{name}" if project else name


def find_unresolvable_pairs(rows):
    """Return [(index_a, index_b, description)] for every pair DRAGEN cannot separate.

    Indexes are positions in `rows`. Mirrors the pairing rule used by
    scripts/validate_barcode_hamming_distance.py: two samples are distinguishable
    when either index channel separates them, so a dual-indexed pair is only
    unresolvable when both channels collide.
    """
    by_lane = defaultdict(list)
    for pos, row in enumerate(rows):
        if _get(row, "index"):
            by_lane[_get(row, "Lane")].append(pos)

    conflicts = []
    for lane, positions in by_lane.items():
        for a in range(len(positions)):
            for b in range(a + 1, len(positions)):
                pos_a, pos_b = positions[a], positions[b]
                row_a, row_b = rows[pos_a], rows[pos_b]
                i7a, i7b = _get(row_a, "index"), _get(row_b, "index")
                i5a, i5b = _get(row_a, "index2"), _get(row_b, "index2")

                if not is_prefix_collision(i7a, i7b):
                    continue
                # A differing i5 still separates the samples; only flag when i5
                # cannot help either (absent on one side, identical, or colliding).
                if i5a and i5b and not (i5a == i5b or is_prefix_collision(i5a, i5b)):
                    continue

                conflicts.append(
                    (
                        pos_a,
                        pos_b,
                        f"lane {lane}: {i7a} ({len(i7a)}bp, {sample_label(row_a)}) collides with "
                        f"{i7b} ({len(i7b)}bp, {sample_label(row_b)}) over the common prefix",
                    )
                )
    return conflicts


def select_projects_for_fqtk(rows):
    """Pick the projects to demultiplex from Undetermined instead of by DRAGEN.

    For each unresolvable pair the shorter index is routed away: the longer index is
    the specific one, so leaving it in the sheet lets DRAGEN claim its own reads
    before anything falls through to Undetermined.

    Routing is by project, not by sample, because the downstream fqtk path keys off a
    project being absent from the sample sheet (FQTK_ORDER_ID_MAP in the Snakefile) to
    find its order ID and build its renaming map. A half-removed project would produce
    FASTQs with nowhere to be delivered.

    Returns (projects, notes, errors).
    """
    projects = set()
    notes = []
    errors = []
    for pos_a, pos_b, description in find_unresolvable_pairs(rows):
        short_pos, long_pos = (
            (pos_a, pos_b)
            if len(_get(rows[pos_a], "index")) < len(_get(rows[pos_b], "index"))
            else (pos_b, pos_a)
        )
        short_project = _get(rows[short_pos], "Sample_Project")
        long_project = _get(rows[long_pos], "Sample_Project")

        if short_project == long_project:
            errors.append(
                f"{description}; both samples belong to project '{short_project}', so removing "
                f"the project from the sheet would leave nothing to assign the longer index "
                f"first -- these libraries need different indexes"
            )
            continue

        notes.append(
            f"{description}; routing project '{short_project}' to post-hoc fqtk demux so "
            f"DRAGEN assigns {sample_label(rows[long_pos])} first"
        )
        projects.add(short_project)
    return projects, notes, errors
