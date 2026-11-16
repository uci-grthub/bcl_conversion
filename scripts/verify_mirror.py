#!/usr/bin/env python3
"""Verify that a mirrored run directory actually received every FASTQ.

`sync_run` fans the big `output/` transfer out across `xargs -P`, and each worker
prints DONE whether or not its rsync succeeded. Nothing downstream notices a
dropped or truncated subdirectory: `publish_run.sh` then runs `snakemake --touch`,
which stamps outputs current *without reading them*, and the per-project
md5sums.txt is never recomputed. The result is a share link to a short FASTQ.

This script closes that gap using the checksums the conversion run already wrote:
every `output/*/*/md5sums.txt` in the mirror lists the files that project is
supposed to contain. That listing is itself checked for truncation first -- it
is written by a shell redirect and so is legitimately empty while the checksum
job runs, and a short one would otherwise shrink this whole check in silence.

    python3 scripts/verify_mirror.py <mirror_dir>                 # existence + size
    python3 scripts/verify_mirror.py <mirror_dir> --src <run_dir> # also compare sizes to the source
    python3 scripts/verify_mirror.py <mirror_dir> --md5           # re-verify every checksum (slow)
    python3 scripts/verify_mirror.py <usb_dir> --flat --src <run_dir>  # USB copy (see below)

A USB copy (scripts/sync_usb.sh) holds only the contents of output/, flattened:
<usb_dir>/<lane>/<project>/md5sums.txt. --flat looks for the listings there and
still compares against <run_dir>/output/<lane>/<project> in the source. --lanes
limits the source-side "project missing from the mirror" check to the lanes a
partial copy was asked for.

Exit status is 0 when the mirror is complete, 1 otherwise.
"""

import argparse
import hashlib
import os
import sys
from glob import glob


def read_md5sums(path):
    """Parse an md5sum-format file into {basename: digest}.

    calculate_md5sums runs `md5sum` from inside the project directory, so the
    recorded paths are relative ("./NAME.fastq.gz").
    """
    entries = {}
    with open(path) as fh:
        for line in fh:
            parts = line.split(None, 1)
            if len(parts) != 2:
                continue
            digest, name = parts[0], parts[1].strip()
            entries[os.path.basename(name)] = digest
    return entries


def md5_of(path, chunk=8 * 1024 * 1024):
    digest = hashlib.md5()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(chunk), b""):
            digest.update(block)
    return digest.hexdigest()


def fastqs_on_disk(project_dir):
    """The FASTQs actually sitting in a project directory.

    calculate_md5sums records `find . -name '*.fastq.gz'` run from inside the
    project, so a finished md5sums.txt has exactly one line per file here.
    """
    return {name for name in os.listdir(project_dir) if name.endswith(".fastq.gz")}


def check_md5sums_file(md5_path, rel_dir, project_dir, entries, src, problems, src_rel=None):
    """Decide whether md5sums.txt itself is trustworthy before believing its contents.

    calculate_md5sums writes with `find ... | xargs md5sum | sort > md5sums.txt`,
    so the shell truncates the file the instant the rule starts and it stays
    short until the last md5sum returns -- minutes, on a 100 GB project. A run
    killed in that window (or a publish interrupted mid-flight) leaves a 0-byte
    or partial file on disk, and `snakemake --touch` then stamps it current
    without reading it. Every other check in this script is driven BY this file,
    so a short one silently shrinks the whole verification instead of failing
    it: the missing FASTQs are simply never looked for.

    Size and line count are the only things that separate that from a healthy
    file, since a partial md5sums.txt is perfectly well-formed.

    Returns True when the listing is worth iterating.
    """
    md5_size = os.path.getsize(md5_path)
    if md5_size == 0:
        problems.append(
            f"{rel_dir}: md5sums.txt is 0 bytes -- truncated, or the checksum "
            "job was still running when the mirror was taken")
        return False
    if not entries:
        problems.append(
            f"{rel_dir}: md5sums.txt has {md5_size:,} bytes but no parseable entries")
        return False

    # A FASTQ sitting in the directory with no line in md5sums.txt means the
    # checksum job never got to it; the file would ship unverified.
    unlisted = fastqs_on_disk(project_dir) - set(entries)
    if unlisted:
        shown = ", ".join(sorted(unlisted)[:5])
        more = f" (+{len(unlisted) - 5} more)" if len(unlisted) > 5 else ""
        problems.append(
            f"{rel_dir}: md5sums.txt lists {len(entries)} entr(ies) but the "
            f"directory holds {len(unlisted) + len(entries)} FASTQ(s); "
            f"unlisted: {shown}{more}")

    # The source copy is the reference for how long the listing should be, and
    # catches the case where the mirror copied a partial file faithfully.
    if src:
        src_md5 = os.path.join(src, src_rel or rel_dir, "md5sums.txt")
        if os.path.exists(src_md5):
            src_entries = read_md5sums(src_md5)
            if len(src_entries) != len(entries):
                problems.append(
                    f"{rel_dir}: md5sums.txt has {len(entries)} entr(ies), "
                    f"source has {len(src_entries)}")

    return True


def check_project(md5_path, mirror, src, check_md5, problems, flat=False):
    project_dir = os.path.dirname(md5_path)
    rel_dir = os.path.relpath(project_dir, mirror)
    # The source run dir always nests lanes under output/; a flat copy does not.
    src_rel = os.path.join("output", rel_dir) if flat else rel_dir
    entries = read_md5sums(md5_path)

    if not check_md5sums_file(md5_path, rel_dir, project_dir, entries, src, problems, src_rel):
        return 0

    for name, digest in sorted(entries.items()):
        path = os.path.join(project_dir, name)
        if not os.path.exists(path):
            problems.append(f"{rel_dir}: missing {name}")
            continue

        size = os.path.getsize(path)
        if size == 0:
            problems.append(f"{rel_dir}: {name} is empty")
            continue

        # A truncated transfer is the failure mode that survives every
        # existence-only check, so compare against the source when we have it.
        if src:
            src_path = os.path.join(src, src_rel, name)
            if not os.path.exists(src_path):
                problems.append(f"{rel_dir}: {name} exists in mirror but not in source {src_path}")
            else:
                src_size = os.path.getsize(src_path)
                if src_size != size:
                    problems.append(
                        f"{rel_dir}: size mismatch {name} "
                        f"(source {src_size:,}, mirror {size:,})"
                    )
                    continue

        if check_md5 and md5_of(path) != digest:
            problems.append(f"{rel_dir}: md5 mismatch {name}")

    return len(entries)


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mirror", help="the mirrored run directory to check")
    parser.add_argument("--src", help="the source run directory, to compare file sizes against")
    parser.add_argument("--md5", action="store_true",
                        help="re-verify every checksum (slow; reads all the data)")
    parser.add_argument("--flat", action="store_true",
                        help="mirror holds output/'s contents directly (USB copy from sync_usb.sh)")
    parser.add_argument("--lanes", nargs="+", metavar="LANE",
                        help="only expect these lane dirs from the source (partial copy)")
    args = parser.parse_args()

    mirror = os.path.abspath(args.mirror)
    src = os.path.abspath(args.src) if args.src else None

    if not os.path.isdir(mirror):
        print(f"error: {mirror} is not a directory", file=sys.stderr)
        return 1
    if src and not os.path.isdir(src):
        print(f"error: source {src} is not a directory", file=sys.stderr)
        return 1

    lane_glob = os.path.join(mirror, "*") if args.flat else os.path.join(mirror, "output", "*")
    md5_files = sorted(glob(os.path.join(lane_glob, "*", "md5sums.txt")))
    if not md5_files:
        layout = "*/*" if args.flat else "output/*/*"
        print(f"error: no {layout}/md5sums.txt under {mirror}; either the mirror is "
              "empty or the conversion run never completed", file=sys.stderr)
        return 1

    problems = []
    n_files = 0
    for md5_path in md5_files:
        n_files += check_project(md5_path, mirror, src, args.md5, problems, args.flat)

    # A project directory present in the source but absent from the mirror has no
    # md5sums.txt to drive the loop above, so it would otherwise pass silently.
    if src:
        src_output = os.path.join(src, "output")
        src_projects = {
            # Keyed the way the mirror lays them out, so the two sets compare.
            os.path.relpath(os.path.dirname(p), src_output if args.flat else src)
            for p in glob(os.path.join(src_output, "*", "*", "md5sums.txt"))
        }
        if args.lanes:
            src_projects = {
                p for p in src_projects
                if (p.split(os.sep)[0] if args.flat else p.split(os.sep)[1]) in args.lanes
            }
        mirror_projects = {os.path.relpath(os.path.dirname(p), mirror) for p in md5_files}
        for missing in sorted(src_projects - mirror_projects):
            problems.append(f"project {missing} is in the source but not in the mirror")

    if problems:
        print(f"Mirror INCOMPLETE: {len(problems)} problem(s) across "
              f"{len(md5_files)} project(s):")
        for problem in problems:
            print(f"  {problem}")
        return 1

    how = "checksums verified" if args.md5 else (
        "sizes matched against source" if src else "sizes non-empty")
    print(f"Mirror OK: {len(md5_files)} project(s), {n_files} FASTQ(s), {how}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
