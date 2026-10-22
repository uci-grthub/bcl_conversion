"""Run-directory state for the staff GUI (gui/app.py).

Everything here reads or writes plain files and the operator's crontab, so it
is testable without Flask. The cron scripts are the source of truth for a run's
progress; this module only interprets the marker files they leave:

    snakemake_config_project.yaml   pixi run init has run
    logs/gui/check.json             metadata check result (written by app.py)
    .metadata_approved              staff approval (gates run_when_ready.sh)
    .auto_launched                  run_when_ready.sh started `pixi run all`
    .auto_launch.lock               held while all + publish run
    .published_ok                   all + publish succeeded
    .post_publish.lock              held while backups run
    .post_<step>.done               one backup / sync step finished
"""
import fcntl
import getpass
import hashlib
import json
import os
import re
import subprocess
import time

import yaml

RUN_ID_RE = re.compile(r"^[ixm]R\d+$")
# A run ID inside a sample-sheet file name, e.g. 251219_23G5F2LT3_10B_PE151_xR077.
SHEET_RUN_ID_RE = re.compile(r"(?<![A-Za-z0-9])[ixmIXM][Rr]\d+(?![0-9])")
PROJECT_CONFIG = "snakemake_config_project.yaml"
APPROVAL_FILE = ".metadata_approved"
CRON_TAG = "# bclgui:"
CRON_SCRIPT = "run_and_backup_when_ready.sh"
BACKUP_STEPS = ("raw_backup", "processed_backup")


# --- config -----------------------------------------------------------------

def read_config(run_dir):
    path = os.path.join(run_dir, PROJECT_CONFIG)
    if not os.path.exists(path):
        return {}
    with open(path) as handle:
        return yaml.safe_load(handle) or {}


def set_config_values(run_dir, values):
    """Rewrite top-level `key: value` lines in place, keeping comments.

    Same approach as scripts/init_run.sh's sed prefill; a key not yet in the
    file is appended.
    """
    path = os.path.join(run_dir, PROJECT_CONFIG)
    with open(path) as handle:
        lines = handle.read().splitlines()
    for key, value in values.items():
        new_line = f"{key}: {json.dumps(value)}"
        pattern = re.compile(rf"^{re.escape(key)}:")
        for i, line in enumerate(lines):
            if pattern.match(line):
                lines[i] = new_line
                break
        else:
            lines.append(new_line)
    with open(path, "w") as handle:
        handle.write("\n".join(lines) + "\n")


# --- approval ---------------------------------------------------------------

def approval_hash(run_dir):
    """sha256 over the metadata workbook then the project config.

    Must match run_when_ready.sh: `cat "$METADATA" snakemake_config_project.yaml | sha256sum`.
    Editing either file after approval therefore withdraws the approval.
    """
    config = read_config(run_dir)
    metadata = config.get("metadata") or ""
    digest = hashlib.sha256()
    for rel in (metadata, PROJECT_CONFIG):
        path = os.path.join(run_dir, rel)
        if not rel or not os.path.isfile(path):
            return None
        with open(path, "rb") as handle:
            digest.update(handle.read())
    return digest.hexdigest()


def read_approval(run_dir):
    path = os.path.join(run_dir, APPROVAL_FILE)
    if not os.path.exists(path):
        return None
    fields = {}
    with open(path) as handle:
        for line in handle:
            key, _, value = line.strip().partition("=")
            if key:
                fields[key] = value
    fields["valid"] = fields.get("sha256") == approval_hash(run_dir)
    return fields


def write_approval(run_dir):
    digest = approval_hash(run_dir)
    if digest is None:
        raise ValueError("metadata workbook or project config missing")
    with open(os.path.join(run_dir, APPROVAL_FILE), "w") as handle:
        handle.write(f"sha256={digest}\n")
        handle.write(f"user={getpass.getuser()}\n")
        handle.write(f"time={time.strftime('%Y-%m-%d %H:%M:%S')}\n")


def revoke_approval(run_dir):
    path = os.path.join(run_dir, APPROVAL_FILE)
    if os.path.exists(path):
        os.remove(path)


# --- metadata check ---------------------------------------------------------

def parse_dry_run(text):
    """{'total': N, 'jobs': {rule: count}} from snakemake's "Job stats:" table."""
    jobs, total, in_table = {}, None, False
    for line in text.splitlines():
        if line.startswith("Job stats:"):
            jobs, total, in_table = {}, None, True
            continue
        if not in_table:
            continue
        parts = line.split()
        if not parts:
            in_table = False
        elif len(parts) == 2 and parts[1].isdigit():
            if parts[0] == "total":
                total = int(parts[1])
                in_table = False
            else:
                jobs[parts[0]] = int(parts[1])
    if total is None and "Nothing to be done" in text:
        total = 0
    return {"total": total, "jobs": jobs}


def read_validation_issues(xlsx_path):
    """Rows of the RECOMMENDED_CHANGES sheet that run_validation.py writes.

    The validator always exits 0; it reports problems only through this sheet,
    and writes a single `sheet == "OK"` row when there are none.
    """
    import pandas as pd

    df = pd.read_excel(xlsx_path, sheet_name="RECOMMENDED_CHANGES").fillna("")
    rows = df.to_dict("records")
    return [r for r in rows if str(r.get("sheet")) != "OK"]


def validation_report_path(run_dir):
    metadata = read_config(run_dir).get("metadata") or ""
    stem = os.path.splitext(os.path.basename(metadata))[0]
    return os.path.join(run_dir, "metadata", f"metadata_validation_{stem}.xlsx")


def read_check(run_dir):
    """Last metadata check, or None. `current` is False once the inputs changed."""
    path = os.path.join(run_dir, "logs", "gui", "check.json")
    if not os.path.exists(path):
        return None
    with open(path) as handle:
        check = json.load(handle)
    check["current"] = check.get("sha256") == approval_hash(run_dir)
    return check


# --- crontab ----------------------------------------------------------------

def read_crontab():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    # Exit 1 with "no crontab for <user>" just means empty.
    return result.stdout if result.returncode == 0 else ""


def write_crontab(text):
    subprocess.run(["crontab", "-"], input=text, text=True, check=True)


def cron_line(run_dir, usb_dest=""):
    run_id = os.path.basename(run_dir)
    script = os.path.join(run_dir, CRON_SCRIPT)
    args = f" {usb_dest}" if usb_dest else ""
    log = os.path.join(run_dir, "logs", "cron_run.log")
    return f"*/30 * * * * {script}{args} >> {log} 2>&1  {CRON_TAG}{run_id}"


def scheduled_line(cron_text, run_id):
    tag = f"{CRON_TAG}{run_id}"
    for line in cron_text.splitlines():
        if line.rstrip().endswith(tag) and not line.lstrip().startswith("#"):
            return line
    return None


def add_cron(run_dir, usb_dest=""):
    text = remove_tagged(read_crontab(), os.path.basename(run_dir))
    if text and not text.endswith("\n"):
        text += "\n"
    write_crontab(text + cron_line(run_dir, usb_dest) + "\n")


def remove_cron(run_id):
    write_crontab(remove_tagged(read_crontab(), run_id))


def remove_tagged(cron_text, run_id):
    tag = f"{CRON_TAG}{run_id}"
    kept = [l for l in cron_text.splitlines() if not l.rstrip().endswith(tag)]
    return "\n".join(kept) + ("\n" if kept else "")


def usb_dest_from_line(line):
    """The optional destination argument the cron line passes, or ""."""
    if not line:
        return ""
    match = re.search(rf"{re.escape(CRON_SCRIPT)}\s+(\S+)\s+>>", line)
    return match.group(1) if match else ""


# --- status -----------------------------------------------------------------

def lock_held(path):
    """True when another process holds the flock on path (the cron scripts' locks)."""
    if not os.path.exists(path):
        return False
    with open(path) as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.flock(handle, fcntl.LOCK_UN)
    return False


def last_failure(run_dir):
    path = os.path.join(run_dir, "logs", "cron_run.log")
    if not os.path.exists(path):
        return ""
    with open(path, errors="replace") as handle:
        lines = handle.readlines()[-400:]
    for line in reversed(lines):
        if "FAILED" in line or "failed;" in line:
            return line.strip()
    return ""


def run_status(run_dir, cron_text):
    """(stage, label, detail) for one run dir.

    stage is a short key the templates colour by: new, setup, ready, approved,
    scheduled, running, attention, published, done.
    """
    has = lambda name: os.path.exists(os.path.join(run_dir, name))
    run_id = os.path.basename(run_dir)
    line = scheduled_line(cron_text, run_id)
    config = read_config(run_dir)
    usb = usb_dest_from_line(line)
    steps = BACKUP_STEPS + (("usb_sync",) if usb else ())
    failure = last_failure(run_dir)

    if has(".published_ok"):
        if all(has(f".post_{s}.done") for s in steps):
            return "done", "Finished and backed up", ""
        if lock_held(os.path.join(run_dir, ".post_publish.lock")):
            return "running", "Published; backing up", ""
        pending = [s for s in steps if not has(f".post_{s}.done")]
        if not line:
            return "attention", "Published; backups not scheduled", "Waiting on: " + ", ".join(pending)
        return "published", "Published; backup retrying", failure or "Waiting on: " + ", ".join(pending)
    if has(".auto_launched"):
        if lock_held(os.path.join(run_dir, ".auto_launch.lock")):
            return "running", "Processing (pixi run all / publish)", ""
        return "attention", "Stopped before publishing", failure or "See logs; ask the pipeline maintainer"
    if not config:
        return "new", "Not set up", "Run setup has not finished"
    approval = read_approval(run_dir)
    if approval and approval["valid"]:
        if line:
            data_dir = config.get("data_dir") or ""
            done = os.path.exists(os.path.join(data_dir, "CopyComplete.txt"))
            return "scheduled", "Scheduled", ("Sequencer finished; starts on the next half-hour"
                                              if done else "Waiting for the sequencer to finish")
        return "approved", "Approved, not scheduled", "Press Schedule"
    if approval:
        return "setup", "Approval withdrawn", "Sheet or settings changed after approval; check again"
    check = read_check(run_dir)
    if check and check["current"] and check.get("ok"):
        return "ready", "Checked, awaiting approval", ""
    return "setup", "Needs checking", ""


def list_runs(platform_dir):
    cron_text = read_crontab()
    runs = []
    for name in sorted(os.listdir(platform_dir), reverse=True):
        path = os.path.join(platform_dir, name)
        if RUN_ID_RE.match(name) and os.path.isdir(path):
            stage, label, detail = run_status(path, cron_text)
            runs.append({"id": name, "path": path, "stage": stage,
                         "label": label, "detail": detail})
    return runs
