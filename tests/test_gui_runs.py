"""Tests for the staff GUI's run-state helpers (gui/runs.py) and the cron
scripts' side of the contract they share with it.

The approval hash is computed twice, in Python by the GUI and in bash by
run_when_ready.sh; the gate tests run the shipped script so the two recipes
cannot drift apart unnoticed. Crontab is faked with a script on PATH that keeps
the table in a file.
"""
import os
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "gui"))

import runs  # noqa: E402

FAKE_CRONTAB = """#!/bin/bash
# crontab -l / crontab - against $FAKE_CRONTAB_FILE
if [ "$1" = "-l" ]; then
  [ -f "$FAKE_CRONTAB_FILE" ] || { echo "no crontab for $USER" >&2; exit 1; }
  cat "$FAKE_CRONTAB_FILE"
else
  cat > "$FAKE_CRONTAB_FILE"
fi
"""


def make_run(tmp_path, run_id="xR999"):
    run_dir = os.path.join(tmp_path, run_id)
    os.makedirs(os.path.join(run_dir, "metadata"))
    os.makedirs(os.path.join(tmp_path, "data"))
    with open(os.path.join(run_dir, "metadata", "sheet_xR999.xlsx"), "wb") as handle:
        handle.write(b"fake workbook bytes")
    with open(os.path.join(run_dir, runs.PROJECT_CONFIG), "w") as handle:
        handle.write("# project config\n"
                     'metadata: "metadata/sheet_xR999.xlsx"\n'
                     f'data_dir: "{os.path.join(tmp_path, "data")}"\n'
                     'email_recipient: ""\n')
    return run_dir


def fake_crontab(tmp_path):
    bin_dir = os.path.join(tmp_path, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    path = os.path.join(bin_dir, "crontab")
    with open(path, "w") as handle:
        handle.write(FAKE_CRONTAB)
    os.chmod(path, 0o755)
    os.environ["PATH"] = bin_dir + os.pathsep + os.environ["PATH"]
    os.environ["FAKE_CRONTAB_FILE"] = os.path.join(tmp_path, "crontab.txt")
    return os.environ["FAKE_CRONTAB_FILE"]


def run_script(run_dir, name, *args):
    shutil.copy(os.path.join(REPO, name), run_dir)
    return subprocess.run(["bash", os.path.join(run_dir, name), *args], cwd=run_dir,
                          capture_output=True, text=True)


def test_set_config_values_keeps_comments_and_appends_missing(tmp_path):
    run_dir = make_run(tmp_path)
    runs.set_config_values(run_dir, {"email_recipient": "me@uci.edu", "email_cc": "x@uci.edu"})
    text = open(os.path.join(run_dir, runs.PROJECT_CONFIG)).read()
    assert text.startswith("# project config\n")
    assert 'email_recipient: "me@uci.edu"' in text
    assert runs.read_config(run_dir)["email_cc"] == "x@uci.edu"


def test_approval_withdrawn_when_config_edited(tmp_path):
    run_dir = make_run(tmp_path)
    assert runs.read_approval(run_dir) is None
    runs.write_approval(run_dir)
    assert runs.read_approval(run_dir)["valid"]
    runs.set_config_values(run_dir, {"email_recipient": "someone@else"})
    assert not runs.read_approval(run_dir)["valid"]


def test_approval_withdrawn_when_sheet_replaced(tmp_path):
    run_dir = make_run(tmp_path)
    runs.write_approval(run_dir)
    with open(os.path.join(run_dir, "metadata", "sheet_xR999.xlsx"), "wb") as handle:
        handle.write(b"edited workbook")
    assert not runs.read_approval(run_dir)["valid"]


def test_run_when_ready_gate_matches_python_hash(tmp_path):
    run_dir = make_run(tmp_path)
    out = run_script(run_dir, "run_when_ready.sh")
    assert out.returncode == 0, out.stderr
    assert "waiting for approval" in out.stdout

    runs.write_approval(run_dir)
    out = run_script(run_dir, "run_when_ready.sh")
    assert "CopyComplete.txt" in out.stdout and "approval" not in out.stdout, out.stdout

    runs.set_config_values(run_dir, {"email_recipient": "changed@uci.edu"})
    out = run_script(run_dir, "run_when_ready.sh")
    assert "approval withdrawn" in out.stdout
    assert not os.path.exists(os.path.join(run_dir, ".auto_launched"))


def test_gate_can_be_skipped_for_hand_scheduled_runs(tmp_path):
    run_dir = make_run(tmp_path)
    shutil.copy(os.path.join(REPO, "run_when_ready.sh"), run_dir)
    out = subprocess.run(["bash", "run_when_ready.sh"], cwd=run_dir, capture_output=True, text=True,
                         env={**os.environ, "REQUIRE_APPROVAL": "0"})
    assert "approval" not in out.stdout and "CopyComplete.txt" in out.stdout


def test_cron_add_replace_remove(tmp_path):
    table = fake_crontab(tmp_path)
    with open(table, "w") as handle:
        handle.write("0 8 * * 1 /some/other/job.sh\n")
    run_dir = make_run(tmp_path, "xR12")
    other = make_run(os.path.join(tmp_path, "b"), "xR123")

    runs.add_cron(run_dir)
    runs.add_cron(other, "/mnt/extusb3")
    runs.add_cron(run_dir, "/mnt/usb2")   # re-schedule replaces, never duplicates
    text = runs.read_crontab()
    assert text.count("# bclgui:xR12\n") == 1
    assert runs.usb_dest_from_line(runs.scheduled_line(text, "xR12")) == "/mnt/usb2"
    assert runs.usb_dest_from_line(runs.scheduled_line(text, "xR123")) == "/mnt/extusb3"

    runs.remove_cron("xR12")
    text = runs.read_crontab()
    assert runs.scheduled_line(text, "xR12") is None
    assert runs.scheduled_line(text, "xR123") is not None
    assert "/some/other/job.sh" in text


def test_backup_wrapper_removes_its_cron_entry_when_done(tmp_path):
    fake_crontab(tmp_path)
    run_dir = make_run(tmp_path)
    runs.add_cron(run_dir)
    runs.add_cron(make_run(os.path.join(tmp_path, "b"), "xR998"))
    for marker in (".auto_launched", ".published_ok", ".post_raw_backup.done"):
        open(os.path.join(run_dir, marker), "w").close()

    # processed_backup not done yet (its script is absent, so the step fails): entry stays.
    run_script(run_dir, "run_and_backup_when_ready.sh")
    assert runs.scheduled_line(runs.read_crontab(), "xR999")

    open(os.path.join(run_dir, ".post_processed_backup.done"), "w").close()
    out = run_script(run_dir, "run_and_backup_when_ready.sh")
    text = runs.read_crontab()
    assert runs.scheduled_line(text, "xR999") is None, out.stdout + out.stderr
    assert runs.scheduled_line(text, "xR998")


def test_parse_dry_run_job_stats():
    text = ("Building DAG of jobs...\nJob stats:\njob                count\n"
            "-----------------  -------\nall                    1\nfastp_sample          12\n"
            "total                 13\n\nThis was a dry-run.\n")
    assert runs.parse_dry_run(text) == {"total": 13, "jobs": {"all": 1, "fastp_sample": 12}}
    assert runs.parse_dry_run("Nothing to be done (all requested files are present).")["total"] == 0


def test_run_status_stages(tmp_path):
    run_dir = make_run(tmp_path)
    touch = lambda name: open(os.path.join(run_dir, name), "w").close()
    assert runs.run_status(run_dir, "")[0] == "setup"

    runs.write_approval(run_dir)
    assert runs.run_status(run_dir, "")[0] == "approved"
    assert runs.run_status(run_dir, runs.cron_line(run_dir))[0] == "scheduled"

    touch(".auto_launched")   # no lock held: all/publish died
    assert runs.run_status(run_dir, "")[0] == "attention"

    touch(".published_ok")
    assert runs.run_status(run_dir, runs.cron_line(run_dir))[0] == "published"
    touch(".post_raw_backup.done")
    touch(".post_processed_backup.done")
    assert runs.run_status(run_dir, "")[0] == "done"
    # A USB sync on the schedule is one more step to wait for.
    assert runs.run_status(run_dir, runs.cron_line(run_dir, "/mnt/x"))[0] == "published"


def test_sheet_run_id_found_in_real_sheet_names():
    find = lambda name: runs.SHEET_RUN_ID_RE.findall(name)
    assert find("260724_257J2MLT4_25B_PE51_87_60_71_xR102") == ["xR102"]
    assert find("251219_23G5F2LT3_10B_PE151_xR077") == ["xR077"]
    assert find("06262026_BXA66618-2426_iR011") == ["iR011"]
    assert find("0915_mr496_samples") == ["mr496"]
    assert find("lab_sheet_final") == []


def test_login_token_file_is_private_and_stable(tmp_path):
    import app
    path = os.path.join(tmp_path, "state", "token")
    first = app.load_or_create(path, lambda: "abc123")
    assert first == "abc123"
    assert os.stat(path).st_mode & 0o777 == 0o600
    assert app.load_or_create(path, lambda: "different") == "abc123"


def test_login_requires_localhost_host_and_token():
    import app
    app.PORT, app.LOGIN_TOKEN = 8123, "tok"
    client = app.app.test_client()
    assert client.get("/", headers={"Host": "evil.example:8123"}).status_code == 400
    assert client.get("/", headers={"Host": "localhost:8123"}).status_code == 403
    response = client.get("/?token=tok", headers={"Host": "localhost:8123"})
    assert response.status_code == 302
    assert "Max-Age=2592000" in response.headers["Set-Cookie"]
    assert client.get("/?token=wrong", headers={"Host": "127.0.0.1:8123"}).status_code == 403


def test_access_log_hides_token():
    import logging
    import app
    record = logging.LogRecord("werkzeug", logging.INFO, "", 0,
                               '%s - - "%s" %s', ("127.0.0.1", "GET /?token=s3cret HTTP/1.1", "302"), None)
    app.RedactToken().filter(record)
    assert "s3cret" not in record.getMessage() and "token=<hidden>" in record.getMessage()
