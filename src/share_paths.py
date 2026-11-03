"""Where a run's data lives, and how that maps onto a Nextcloud path.

A run dir normally holds its data in place. With `share_output_root` set, the bulk
data dirs (DATA_DIRS) are instead symlinks into
<share_output_root>/<instrument>/<run_id>/, so FASTQs land on the share from the
start and the pipeline's own share links are already final -- no publish rsync.

The Nextcloud path of a local dir is derived from where the bytes really are, so
it must use os.path.realpath, never abspath: abspath of output/<lane>/<project>
in a linked run dir is a /staging path that Nextcloud cannot see.
"""
import os

# Data dirs that move to the share. .output and .output_rc must sit on the same
# filesystem as output (bcl_project_done moves projects out of them, which is a
# rename only within one filesystem), and sweeps must too (masking_sweep.sh
# hardlinks FASTQs from output into each variant).
DATA_DIRS = ("output", ".output", ".output_rc", "sweeps")

DEFAULT_SHARE_ROOT = "/mnt/jbod2_main/nextshare/bcl_convert"


def nc_path_for(local_path, dir_name, dir_path):
    """Nextcloud path of local_path: the part after /<dir_path>/, under /<dir_name>/.

    Paths outside any /<dir_path>/ come back as their real absolute path, as before.
    """
    real = os.path.realpath(local_path)
    marker = f"/{dir_path}/"
    if marker in real:
        return f"/{dir_name}/" + real.split(marker, 1)[1]
    return real


def share_link_problems(run_dir, share_root):
    """Why run_dir's data dirs are not correctly linked into share_root (empty = ok)."""
    problems = []
    root = os.path.realpath(share_root)
    if not os.path.isdir(root):
        return [f"share root {share_root} does not exist or is not mounted"]
    if not os.access(root, os.W_OK):
        problems.append(f"share root {share_root} is not writable")
    for name in DATA_DIRS:
        path = os.path.join(run_dir, name)
        if not os.path.islink(path):
            state = "a real directory" if os.path.isdir(path) else "missing"
            problems.append(f"{name} is {state}, not a symlink into {share_root}")
            continue
        target = os.path.realpath(path)
        if os.path.commonpath([root, target]) != root:
            problems.append(f"{name} -> {target} is outside {share_root}")
        elif not os.path.isdir(target):
            problems.append(f"{name} -> {target} does not exist")
    return problems
