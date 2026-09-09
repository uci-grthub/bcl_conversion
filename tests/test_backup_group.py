"""The HPC3 backups must land in the lab group, on every rsync they run.

-a preserves the source group, and the staging group ('grthcloud') means nothing
on HPC3, so without an explicit mapping the copy arrives owned by the
transferring account's default group -- a lab backup only one person can read.
It has to be an rsync option rather than a chgrp afterwards, because access-hpc3
refuses arbitrary remote commands.

The subtle half is the verification pass. Both scripts verify by re-running the
transfer as a dry run and treating any remaining output as missing data. A
verify pass without the same group mapping sees a group it wants to change on
every single file and reports a complete backup as broken.
"""
import grp
import os
import re
import subprocess

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = {
    "raw": os.path.join(REPO, "scripts", "backup_raw_run.sh"),
    "processed": os.path.join(REPO, "scripts", "backup_processed_run.sh"),
}


def joined_source(path):
    """Script text with backslash-continuations folded, so one command is one line."""
    return re.sub(r"\\\n\s*", " ", open(path).read())


def transfer_rsyncs(path):
    """Every rsync in the script that actually talks to the remote.

    Keyed off the destination rather than the flags, so a new invocation is
    caught no matter which options it was written with.
    """
    return [line.strip() for line in joined_source(path).splitlines()
            if "rsync" in line and "${host}:${dest_base}" in line]


def test_both_scripts_default_to_the_lab_group():
    for name, path in SCRIPTS.items():
        source = open(path).read()
        assert 'backup_group="${BACKUP_GROUP-ucightf}"' in source, name


def test_every_remote_rsync_maps_the_group():
    """Including the verify pass -- see the module docstring."""
    for name, path in SCRIPTS.items():
        invocations = transfer_rsyncs(path)
        # dry-run preview, the real transfer, and the verification pass
        assert len(invocations) == 3, (name, invocations)
        for command in invocations:
            assert '"${group_opts[@]}"' in command, (name, command)


def test_the_group_can_be_turned_off():
    """BACKUP_GROUP= must transfer unmapped rather than fail or silently default."""
    for name, path in SCRIPTS.items():
        source = joined_source(path)
        assert 'if [[ -n "$backup_group" ]]; then' in source, name
        assert 'group_opts=(--chown=":$backup_group")' in source, name


def secondary_group():
    """A group we belong to that is not the one new files get by default.

    Returns None when the account has only one group, which makes the mapping
    untestable rather than broken.
    """
    default = os.stat(REPO).st_gid
    for gid in os.getgroups():
        if gid != default:
            try:
                return grp.getgrgid(gid).gr_name
            except KeyError:
                continue
    return None


def test_chown_rewrites_the_group_and_verify_stays_clean(tmp_path):
    """The behaviour itself, with a real rsync: dest is remapped, verify is empty."""
    group = secondary_group()
    if group is None:
        print("skipped: account has no second group to map to")
        return

    src = os.path.join(str(tmp_path), "src")
    dst = os.path.join(str(tmp_path), "dst")
    os.makedirs(os.path.join(src, "sub"))
    os.makedirs(dst)
    for rel in ("a.txt", "sub/b.txt"):
        with open(os.path.join(src, rel), "w") as fh:
            fh.write("payload")

    chown = "--chown=:" + group
    subprocess.run(["rsync", "-a", chown, src + "/", dst + "/"], check=True)

    for dirpath, _dirnames, filenames in os.walk(dst):
        for name in [dirpath] + [os.path.join(dirpath, f) for f in filenames]:
            got = grp.getgrgid(os.stat(name).st_gid).gr_name
            assert got == group, (name, got)

    verify = subprocess.run(
        ["rsync", "-an", "--itemize-changes", chown, src + "/", dst + "/"],
        check=True, capture_output=True, text=True)
    assert verify.stdout.strip() == "", verify.stdout


def test_verify_without_the_mapping_would_report_a_good_backup_as_broken(tmp_path):
    """Pins why the flag belongs on the verify pass and not only the transfer."""
    group = secondary_group()
    if group is None:
        print("skipped: account has no second group to map to")
        return

    src = os.path.join(str(tmp_path), "src")
    dst = os.path.join(str(tmp_path), "dst")
    os.makedirs(src)
    os.makedirs(dst)
    with open(os.path.join(src, "a.txt"), "w") as fh:
        fh.write("payload")

    subprocess.run(["rsync", "-a", "--chown=:" + group, src + "/", dst + "/"], check=True)
    unmapped = subprocess.run(
        ["rsync", "-an", "--itemize-changes", src + "/", dst + "/"],
        check=True, capture_output=True, text=True)
    # 'g' in the itemize string is a group change rsync still wants to make.
    assert re.search(r"^\.f\S*g\S*\s+a\.txt$", unmapped.stdout, re.M), unmapped.stdout
