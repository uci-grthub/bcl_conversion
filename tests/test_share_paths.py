"""Direct-to-share mode: run-dir data dirs symlinked into the Nextcloud share.

The share path of a project must come from where its FASTQs really are. With
output/ a symlink, abspath gives the /staging path, which Nextcloud cannot see,
so a share link minted from it points nowhere. These tests pin that down and
exercise the shipped link_share_dirs.sh against a fake share tree.
"""
import os
import subprocess

from share_paths import DATA_DIRS, nc_path_for, share_link_problems

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINK_SCRIPT = os.path.join(REPO, "scripts", "link_share_dirs.sh")


def _fake_layout(tmp_path):
    """<tmp>/staging/nextcloud/NovaSeqX/xR1 run dir and <tmp>/jbod/nextshare/bcl_convert share."""
    run_dir = os.path.join(tmp_path, "staging", "nextcloud", "NovaSeqX", "xR1")
    share_root = os.path.join(tmp_path, "jbod", "nextshare", "bcl_convert")
    os.makedirs(run_dir)
    os.makedirs(share_root)
    return run_dir, share_root


def test_plain_dir_maps_like_before(tmp_path):
    run_dir, _ = _fake_layout(tmp_path)
    proj = os.path.join(run_dir, "output", "lane1", "P_G1")
    os.makedirs(proj)
    assert nc_path_for(proj, "dragenshare", "nextcloud") == "/dragenshare/NovaSeqX/xR1/output/lane1/P_G1"


def test_symlinked_output_maps_to_share(tmp_path):
    run_dir, share_root = _fake_layout(tmp_path)
    target = os.path.join(share_root, "NovaSeqX", "xR1", "output")
    os.makedirs(os.path.join(target, "lane1", "P_G1"))
    os.symlink(target, os.path.join(run_dir, "output"))
    proj = os.path.join(run_dir, "output", "lane1", "P_G1")
    assert nc_path_for(proj, "Jbod2", "nextshare") == "/Jbod2/bcl_convert/NovaSeqX/xR1/output/lane1/P_G1"


def test_unmapped_path_returns_real_path(tmp_path):
    d = os.path.join(tmp_path, "elsewhere")
    os.makedirs(d)
    assert nc_path_for(d, "Jbod2", "nextshare") == os.path.realpath(d)


def test_problems_reported_for_unlinked_run_dir(tmp_path):
    run_dir, share_root = _fake_layout(tmp_path)
    os.makedirs(os.path.join(run_dir, "output"))
    problems = share_link_problems(run_dir, share_root)
    assert len(problems) == len(DATA_DIRS)
    assert any("output is a real directory" in p for p in problems)


def test_problems_for_missing_share_root(tmp_path):
    run_dir, _ = _fake_layout(tmp_path)
    problems = share_link_problems(run_dir, os.path.join(tmp_path, "not_mounted"))
    assert problems and "does not exist" in problems[0]


def _run_link_script(run_dir, share_root):
    return subprocess.run(["bash", LINK_SCRIPT, share_root], cwd=run_dir,
                          capture_output=True, text=True)


def _prepare_run_dir(run_dir):
    open(os.path.join(run_dir, "Snakefile"), "w").close()
    with open(os.path.join(run_dir, "snakemake_config_project.yaml"), "w") as f:
        f.write('nextcloud_dir_name: "dragenshare"\nnextcloud_dir_path: "nextcloud"\n')
    for d in ("output", "sweeps"):
        os.makedirs(os.path.join(run_dir, d))
        with open(os.path.join(run_dir, d, ".gitignore"), "w") as f:
            f.write("*\n!.gitignore")


def test_link_script_links_and_configures(tmp_path):
    run_dir, share_root = _fake_layout(tmp_path)
    _prepare_run_dir(run_dir)

    result = _run_link_script(run_dir, share_root)
    assert result.returncode == 0, result.stderr

    assert share_link_problems(run_dir, share_root) == []
    dest = os.path.join(share_root, "NovaSeqX", "xR1")
    for d in DATA_DIRS:
        assert os.path.realpath(os.path.join(run_dir, d)) == os.path.realpath(os.path.join(dest, d))
    assert os.path.isfile(os.path.join(dest, "output", ".gitignore"))

    with open(os.path.join(run_dir, "snakemake_config_project.yaml")) as f:
        cfg = f.read()
    assert 'nextcloud_dir_name: "Jbod2"' in cfg
    assert 'nextcloud_dir_path: "nextshare"' in cfg
    assert f'share_output_root: "{share_root}"' in cfg

    # Idempotent.
    again = _run_link_script(run_dir, share_root)
    assert again.returncode == 0, again.stderr


def test_link_script_refuses_dir_with_data(tmp_path):
    run_dir, share_root = _fake_layout(tmp_path)
    _prepare_run_dir(run_dir)
    os.makedirs(os.path.join(run_dir, "output", "lane1"))

    result = _run_link_script(run_dir, share_root)
    assert result.returncode != 0
    assert "already holds data" in result.stderr
    # Nothing changed: refusal happens before any dir is linked.
    for d in DATA_DIRS:
        assert not os.path.islink(os.path.join(run_dir, d))


def test_link_script_creates_root_under_existing_mount(tmp_path):
    run_dir, share_root = _fake_layout(tmp_path)
    _prepare_run_dir(run_dir)
    os.rmdir(share_root)  # nextshare/ (the mount) exists; bcl_convert/ does not yet

    result = _run_link_script(run_dir, share_root)
    assert result.returncode == 0, result.stderr
    assert share_link_problems(run_dir, share_root) == []


def test_link_script_refuses_when_mount_missing(tmp_path):
    run_dir, _ = _fake_layout(tmp_path)
    _prepare_run_dir(run_dir)
    missing = os.path.join(tmp_path, "unmounted", "nextshare", "bcl_convert")

    result = _run_link_script(run_dir, missing)
    assert result.returncode != 0
    assert "not mounted" in result.stderr
    assert not os.path.exists(os.path.dirname(missing))
