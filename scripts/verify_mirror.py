#!/usr/bin/env python3
"""Verify that a mirrored run directory actually received every FASTQ.

`sync_run` fans the big `output/` transfer out across `xargs -P`, and each worker
prints DONE whether or not its rsync succeeded. Nothing downstream notices a
dropped or truncated subdirectory: `publish_run.sh` then runs `snakemake --touch`,
which stamps outputs current *without reading them*, and the per-project
md5sums.txt is never recomputed. The result is a share link to a short FASTQ.

This script closes that gap using the checksums the conversion run already wrote:
every `output/*/*/md5sums.txt` in the mirror lists the files that project is
supposed to contain.

    python3 scripts/verify_mirror.py <mirror_dir>                 # existence + size
    python3 scripts/verify_mirror.py <mirror_dir> --src <run_dir> # also compare sizes to the source
    python3 scripts/verify_mirror.py <mirror_dir> --md5           # re-verify every checksum (slow)

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


def check_project(md5_path, mirror, src, check_md5, problems):
    project_dir = os.path.dirname(md5_path)
    rel_dir = os.path.relpath(project_dir, mirror)
    entries = read_md5sums(md5_path)

    if not entries:
        problems.append(f"{rel_dir}: md5sums.txt is empty")
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
            src_path = os.path.join(src, rel_dir, name)
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
    args = parser.parse_args()

    mirror = os.path.abspath(args.mirror)
    src = os.path.abspath(args.src) if args.src else None

    if not os.path.isdir(mirror):
        print(f"error: {mirror} is not a directory", file=sys.stderr)
        return 1
    if src and not os.path.isdir(src):
        print(f"error: source {src} is not a directory", file=sys.stderr)
        return 1

    md5_files = sorted(glob(os.path.join(mirror, "output", "*", "*", "md5sums.txt")))
    if not md5_files:
        print(f"error: no output/*/*/md5sums.txt under {mirror}; either the mirror is "
              "empty or the conversion run never completed", file=sys.stderr)
        return 1

    problems = []
    n_files = 0
    for md5_path in md5_files:
        n_files += check_project(md5_path, mirror, src, args.md5, problems)

    # A project directory present in the source but absent from the mirror has no
    # md5sums.txt to drive the loop above, so it would otherwise pass silently.
    if src:
        src_projects = {
            os.path.relpath(os.path.dirname(p), src)
            for p in glob(os.path.join(src, "output", "*", "*", "md5sums.txt"))
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
