"""Readiness checks for one run, printed as JSON for the staff GUI.

Run under `pixi run` from the run dir so .env activation applies:
    pixi run python gui/preflight.py

Each check is read-only: nothing is created on Nextcloud or HPC3.
"""
import base64
import json
import os
import subprocess
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from runs import read_config  # noqa: E402


def check(name, ok, detail=""):
    return {"name": name, "ok": bool(ok), "detail": detail}


def nextcloud():
    url = os.environ.get("NEXTCLOUD_URL", "").rstrip("/")
    password = os.environ.get("NEXTCLOUD_PASSWORD", "")
    user = os.environ.get("NEXTCLOUD_USER") or os.environ.get("USER", "")
    if not url or not password:
        return check("Nextcloud login", False, "NEXTCLOUD_URL / NEXTCLOUD_PASSWORD not set (see SOP: Credentials)")
    request = urllib.request.Request(
        f"{url}/ocs/v1.php/cloud/user?format=json",
        headers={"OCS-APIRequest": "true",
                 "Authorization": "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return check("Nextcloud login", response.status == 200, f"{user} @ {url}")
    except Exception as exc:
        return check("Nextcloud login", False, f"{user} @ {url}: {exc}")


def hpc3():
    # access-hpc3 refuses remote commands, so probe with sftp like the backup scripts do.
    try:
        result = subprocess.run(
            ["sftp", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-b", "-", "hpc3"],
            input="pwd\n", capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return check("HPC3 key login (backups)", False, "timed out")
    detail = "" if result.returncode == 0 else (result.stderr.strip().splitlines() or ["failed"])[-1]
    return check("HPC3 key login (backups)", result.returncode == 0, detail)


def main():
    config = read_config(".")
    base = read_config_base()
    dragen = config.get("dragen_bin") or base.get("dragen_bin", "")
    data_dir = config.get("data_dir") or ""
    results = [
        check("DRAGEN installed", os.access(dragen, os.X_OK), dragen),
        check("Sequencer data folder found", data_dir and os.path.isdir(data_dir), data_dir or "data_dir not set"),
        check("Results email set", config.get("email_recipient"), config.get("email_recipient") or "email_recipient is blank"),
        check("Gmail app password set", os.environ.get("GMAIL_APP_PASSWORD"), ""),
        nextcloud(),
        hpc3(),
    ]
    print(json.dumps(results))


def read_config_base():
    import yaml
    with open("snakemake_config.yaml") as handle:
        return yaml.safe_load(handle) or {}


if __name__ == "__main__":
    main()
