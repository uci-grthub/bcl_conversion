#!/usr/bin/env python3
"""Collapse byte-identical FASTQs in a mirrored run into hardlinks.

`sync_run` transfers `output/*` with one rsync per subdirectory and everything
else in a second pass, and neither pass is given `-H`. Hardlinks that were
shared in the source therefore arrive at the destination as independent copies.
A masking sweep is the pathological case: `seed_conversion_dir` hardlinks R1/I1/I2
into each variant because only R2 differs between maskings, so three variants of
one lane cost ~40 GB of real R2 in the source and ~209 GB in the mirror.

Rather than re-read a few hundred GB over NFS to find duplicates the way rdfind
or jdupes would, this uses the checksums the conversion run already wrote: every
delivered project directory carries an md5sums.txt covering all four reads of
every sample. Files that share a digest are the same bytes, so one inode will do.

    python3 scripts/dedupe_mirror.py                     # dry run, mirror of cwd's run
    python3 scripts/dedupe_mirror.py <dir>               # dry run, explicit directory
    python3 scripts/dedupe_mirror.py <dir> --apply       # actually relink
    python3 scripts/dedupe_mirror.py <dir> --apply --verify   # byte-compare each pair first

Dry run is the default because this rewrites directory entries in a
customer-facing share. Nothing is deleted: each duplicate is replaced by a link
to an identical file, via a temporary name and rename(2), so a reader either sees
the old entry or the new one and never a missing file.

Exit status is 0 when the pass completed (or found nothing to do), 1 on error.
"""

import argparse
import filecmp
import os
import subprocess
import sys
from collections import defaultdict
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


# Where deliveries live. The run's own are at output/<lane>/<project>/; a masking
# sweep's are one level down, and those are exactly the copies worth collapsing.
MD5_GLOBS = (
    "output/*/*/md5sums.txt",
    "sweeps/*/output/*/*/md5sums.txt",
)


def find_md5sums(root):
    """Every md5sums.txt under root.

    Globbing the two known layouts rather than walking: the destination is an NFS
    mount holding a couple of terabytes, and a full os.walk of it spends minutes in
    metadata round-trips before the first digest is read. The walk stays as a
    fallback for a tree shaped some other way.
    """
    found = []
    for pattern in MD5_GLOBS:
        found.extend(glob(os.path.join(root, pattern)))
    if found:
        return sorted(found)

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".snakemake"]
        if "md5sums.txt" in filenames:
            found.append(os.path.join(dirpath, "md5sums.txt"))
    return sorted(found)


def human(num_bytes):
    value = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(value) < 1024 or unit == "TB":
            return f"{value:.1f} {unit}"
        value /= 1024


LOCK_GLOBS = (
    ".snakemake/locks/*",
    "sweeps/*/.snakemake/locks/*",
)


def snakemake_running(root):
    """Describe a workflow that looks live in this tree, or None.

    Relinking underneath a running job is the one way this script can corrupt
    something: a rule that has opened a FASTQ for writing would keep writing into
    an inode that other paths now share.

    Both checks are needed. Snakemake only holds a lock while a job is actually in
    flight, so a sweep sitting between variants shows none. And the process check
    has to go through /proc/<pid>/cwd rather than the command line, because these
    are started from inside the run directory -- `masking_sweep.sh 39 22 17` names
    no path at all, which is exactly how a live sweep slipped past an earlier
    version of this check.
    """
    for pattern in LOCK_GLOBS:
        for lock in glob(os.path.join(root, pattern)):
            return f"snakemake lock present: {lock}"

    try:
        out = subprocess.run(["pgrep", "-af", "masking_sweep|snakemake"],
                             capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return None

    root_prefix = root.rstrip(os.sep) + os.sep
    for line in out.splitlines():
        pid, _, cmdline = line.partition(" ")
        if "dedupe_mirror" in cmdline:
            continue
        if root in cmdline:
            return f"process running against this tree: {line.strip()}"
        try:
            cwd = os.path.realpath(os.path.join("/proc", pid, "cwd"))
        except OSError:
            continue
        if cwd == root or cwd.startswith(root_prefix):
            return f"process {pid} running in {cwd}: {cmdline.strip()}"
    return None


def collect_groups(root, problems):
    """digest -> list of paths, for every FASTQ named in an md5sums.txt."""
    groups = defaultdict(list)
    md5_files = find_md5sums(root)
    if not md5_files:
        problems.append(f"no md5sums.txt found under {root}")
        return groups, 0

    total = 0
    for md5_path in md5_files:
        project_dir = os.path.dirname(md5_path)
        for name, digest in read_md5sums(md5_path).items():
            path = os.path.join(project_dir, name)
            if not os.path.isfile(path) or os.path.islink(path):
                # verify_mirror.py is the tool that cares about missing files;
                # here a gap just means there is nothing to link.
                continue
            groups[digest].append(path)
            total += 1
    return groups, total


def pick_keeper(paths):
    """Which copy keeps its inode.

    Prefer a path outside sweeps/ so the surviving inode lives in the run's own
    delivery rather than in a masking variant: the variants are the disposable
    ones, and a later `rm -rf sweeps/` should not be able to strand the delivery.
    Ties break on link count, then on path, so the choice is deterministic.
    """
    def rank(path):
        in_sweeps = os.sep + "sweeps" + os.sep in path
        try:
            nlink = os.stat(path).st_nlink
        except OSError:
            nlink = 0
        return (in_sweeps, -nlink, path)

    return sorted(paths, key=rank)[0]


def relink(keeper, duplicate):
    """Replace duplicate with a hardlink to keeper, atomically."""
    tmp = duplicate + ".dedupe.tmp"
    if os.path.exists(tmp):
        os.unlink(tmp)
    os.link(keeper, tmp)
    try:
        os.replace(tmp, duplicate)
    except OSError:
        os.unlink(tmp)
        raise


def process_group(digest, paths, apply_changes, verify, problems, verbose):
    """Link every copy in one digest group to a single inode. Returns bytes freed."""
    stats = {}
    for path in paths:
        try:
            stats[path] = os.stat(path)
        except OSError as exc:
            problems.append(f"{path}: {exc}")
    paths = [p for p in paths if p in stats]
    if len(paths) < 2:
        return 0

    sizes = {stats[p].st_size for p in paths}
    if len(sizes) > 1:
        # Same digest, different sizes: an md5sums.txt is stale with respect to
        # the file beside it. Linking here would propagate whichever copy won.
        problems.append(
            f"{digest}: sizes disagree, refusing to link "
            + ", ".join(f"{p} ({stats[p].st_size})" for p in sorted(paths)))
        return 0

    devices = {stats[p].st_dev for p in paths}
    if len(devices) > 1:
        problems.append(f"{digest}: spans {len(devices)} filesystems, cannot hardlink")
        return 0

    keeper = pick_keeper(paths)
    keeper_ino = stats[keeper].st_ino
    size = stats[keeper].st_size
    freed = 0
    linked_inodes = {keeper_ino}

    for path in sorted(paths):
        if path == keeper or stats[path].st_ino == keeper_ino:
            continue
        if verify and not filecmp.cmp(keeper, path, shallow=False):
            problems.append(
                f"{digest}: --verify says {path} differs from {keeper} "
                f"despite a matching digest")
            continue
        if stats[path].st_ino not in linked_inodes:
            freed += size
            linked_inodes.add(stats[path].st_ino)
        if verbose:
            action = "link" if apply_changes else "would link"
            print(f"  {action} {path}\n       -> {keeper}")
        if apply_changes:
            try:
                relink(keeper, path)
            except OSError as exc:
                problems.append(f"{path}: could not relink: {exc}")
                freed -= size
    return freed


def main():
    parser = argparse.ArgumentParser(
        description="Hardlink byte-identical FASTQs within a mirrored run.")
    parser.add_argument(
        "target", nargs="?",
        help="directory to deduplicate; defaults to the mirror of the run in cwd")
    parser.add_argument(
        "--mirror-base", default="/mnt/jbod_localdisk/nextshare/bcl_convert",
        help="share root used to derive the target from cwd (default: %(default)s)")
    parser.add_argument("--apply", action="store_true",
                        help="actually relink; without this nothing is modified")
    parser.add_argument("--verify", action="store_true",
                        help="byte-compare each pair before linking (reads everything)")
    parser.add_argument("--force", action="store_true",
                        help="proceed even though a workflow looks live in the tree")
    parser.add_argument("--quiet", action="store_true",
                        help="summary only, no per-file lines")
    args = parser.parse_args()

    target = args.target
    if not target:
        run_dir = os.getcwd()
        run_id = os.path.basename(run_dir)
        instrument = os.path.basename(os.path.dirname(run_dir))
        if not run_id or not instrument:
            sys.exit(f"cannot derive a run from {run_dir}; pass the directory explicitly")
        target = os.path.join(args.mirror_base, instrument, run_id)
        print(f"no target given; using the mirror of {instrument}/{run_id}")
    target = os.path.abspath(target)

    if not os.path.isdir(target):
        sys.exit(f"not a directory: {target}")

    print(f"target: {target}")
    print(f"mode:   {'APPLY' if args.apply else 'dry run'}"
          f"{' + verify' if args.verify else ''}")

    live = snakemake_running(target)
    if live:
        message = (f"a workflow appears to be running here ({live}). Relinking a "
                   f"file a rule is writing would corrupt every path sharing it.")
        if not args.force:
            sys.exit(f"refusing: {message}\nRe-run once it finishes, or pass --force.")
        print(f"WARNING: {message} Continuing because --force was given.")

    problems = []
    groups, total_files = collect_groups(target, problems)
    freed = 0
    for digest, paths in sorted(groups.items()):
        if len(paths) > 1:
            freed += process_group(digest, paths, args.apply, args.verify,
                                   problems, not args.quiet)

    duplicated = sum(1 for paths in groups.values() if len(paths) > 1)
    print()
    print(f"checked {total_files} file(s) across {len(groups)} distinct digest(s)")
    print(f"{duplicated} digest(s) have more than one copy")
    print(f"{'reclaimed' if args.apply else 'reclaimable'}: {human(freed)}")

    if problems:
        print(f"\n{len(problems)} problem(s):")
        for problem in problems:
            print(f"  {problem}")
        return 1
    if not args.apply and freed:
        print("\nDry run: nothing was modified. Re-run with --apply to relink.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
