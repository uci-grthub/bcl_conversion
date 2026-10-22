"""Staff web GUI: set up, check, approve and schedule sequencing runs.

    pixi run gui                      # from the control clone, e.g. NovaSeqX/.bcl_gui

It listens on 127.0.0.1 only, on a per-user port, and prints the SSH tunnel
command and a login link. The link's token is kept in ~/.config/bclgui, so it
stays the same across restarts (`pixi run gui-link` prints it again). It runs as the operator, so the cron entries
it writes are theirs and use their ~/.env and hpc3 key, the same as running the
scripts by hand. See docs/GUI.md.

The GUI drives the existing scripts and never replaces them: setup is
`git clone` + `pixi install` + `pixi run init`, the check is `pixi run validate`
+ `pixi run dry-run`, and scheduling adds run_and_backup_when_ready.sh to
crontab. That script removes its own entry once the backups finish.
"""
import argparse
import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time

from flask import (Flask, abort, flash, jsonify, redirect, render_template,
                   request, send_file, url_for)
from werkzeug.utils import secure_filename

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import runs  # noqa: E402

CONTROL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PIXI = shutil.which("pixi") or os.path.expanduser("~/.pixi/bin/pixi")
GUI_LOGS = os.path.join(CONTROL_DIR, "logs", "gui")
# Config fields staff may edit; everything else stays as init / the base config set it.
EDITABLE = ("data_dir", "email_sender", "email_recipient", "email_cc")

app = Flask(__name__)
app.config["SESSION_COOKIE_SAMESITE"] = "Strict"
app.config["MAX_CONTENT_LENGTH"] = 50 * 1024 * 1024   # sheet uploads
PLATFORM_DIR = os.path.dirname(CONTROL_DIR)
STATE_DIR = os.path.expanduser("~/.config/bclgui")
TOKEN_FILE = os.path.join(STATE_DIR, "token")
COOKIE_DAYS = 30
LOGIN_TOKEN = None   # set in main()
PORT = None

# run_id -> Job; one background action per run at a time.
jobs = {}
jobs_lock = threading.Lock()


class Job:
    """Runs a list of commands in order in a thread, stopping at the first failure."""

    def __init__(self, action, steps, log_path, on_finish=None):
        self.action, self.steps, self.log_path = action, steps, log_path
        self.on_finish = on_finish
        self.outputs = {}
        self.rc = None
        self.started = time.strftime("%H:%M:%S")
        self.t0 = time.time()
        self.step = 0   # 1-based index of the step running now
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        open(log_path, "w").close()
        threading.Thread(target=self._run, daemon=True).start()

    @property
    def running(self):
        return self.rc is None

    def progress(self):
        """What the page's spinner shows: which step of how many, and for how long."""
        label = self.steps[self.step - 1][0] if self.step else ""
        return {"action": self.action, "step": self.step, "total": len(self.steps),
                "label": label, "elapsed": int(time.time() - self.t0)}

    def _log(self, text):
        with open(self.log_path, "a") as handle:
            handle.write(text)

    def _run(self):
        rc = 0
        for self.step, (label, argv, cwd) in enumerate(self.steps, 1):
            self._log(f"\n=== {label} ===\n$ {' '.join(argv)}\n")
            try:
                proc = subprocess.Popen(argv, cwd=cwd, env=child_env(), stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, errors="replace")
                chunks = []
                for line in proc.stdout:
                    chunks.append(line)
                    self._log(line)
                rc = proc.wait()
            except Exception as exc:
                chunks, rc = [f"{exc}\n"], 1
                self._log(f"{exc}\n")
            self.outputs[label] = (rc, "".join(chunks))
            self._log(f"=== {label}: {'OK' if rc == 0 else f'FAILED (exit {rc})'} ===\n")
            if rc != 0:
                break
        if self.on_finish:
            try:
                self.on_finish(self, rc)
            except Exception as exc:
                self._log(f"\nGUI error after {self.action}: {exc}\n")
                rc = rc or 1
        self.rc = rc


def child_env():
    """This process's environment minus the pixi activation of the control clone.

    `pixi run gui` exports the control clone's manifest and env; left in place,
    a `pixi run` in a run dir warns about it and inherits the wrong activation.
    """
    drop = ("PIXI_PROJECT_", "PIXI_ENVIRONMENT_", "PIXI_IN_SHELL", "CONDA_")
    return {k: v for k, v in os.environ.items() if not k.startswith(drop)}


def start_job(run_id, *args, **kwargs):
    with jobs_lock:
        current = jobs.get(run_id)
        if current and current.running:
            flash(f"{run_id}: '{current.action}' is still running; wait for it to finish.", "error")
            return None
        jobs[run_id] = Job(*args, **kwargs)
        return jobs[run_id]


def run_dir_for(run_id):
    if not runs.RUN_ID_RE.match(run_id):
        abort(404)
    return os.path.join(PLATFORM_DIR, run_id)


def tail(path, lines=200):
    if not path or not os.path.exists(path):
        return ""
    with open(path, errors="replace") as handle:
        return "".join(handle.readlines()[-lines:])


def newest(pattern_dir, prefix):
    if not os.path.isdir(pattern_dir):
        return None
    names = sorted(n for n in os.listdir(pattern_dir) if n.startswith(prefix))
    return os.path.join(pattern_dir, names[-1]) if names else None


def sample_sheets():
    folder = os.path.join(PLATFORM_DIR, "SampleSheets")
    if not os.path.isdir(folder):
        return []
    names = [n for n in os.listdir(folder) if n.endswith(".xlsx") and not n.startswith("~$")]
    return sorted(names, key=lambda n: os.path.getmtime(os.path.join(folder, n)), reverse=True)


# --- login ------------------------------------------------------------------

def load_or_create(path, make):
    """Read a secret from a file only the operator can read, creating it if missing."""
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    try:
        with open(path) as handle:
            value = handle.read().strip()
        if value:
            return value
    except FileNotFoundError:
        pass
    value = make()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(value + "\n")
    return value


def token_matches(value):
    return bool(value) and secrets.compare_digest(value.encode(), LOGIN_TOKEN.encode())


@app.before_request
def require_login():
    # Only a browser that asked for localhost by name gets through; a page that
    # rebinds its own domain to 127.0.0.1 sends its own Host and is refused.
    if request.host not in (f"localhost:{PORT}", f"127.0.0.1:{PORT}"):
        abort(400)
    # Bound to 127.0.0.1, but every account on this host can reach that port,
    # and the app acts as the operator (crontab, credentials). The token is the
    # operator's proof of being the operator.
    if token_matches(request.args.get("token")):
        response = redirect(request.path)
        response.set_cookie("bclgui", LOGIN_TOKEN, max_age=COOKIE_DAYS * 86400,
                            httponly=True, samesite="Strict")
        return response
    if not token_matches(request.cookies.get("bclgui")):
        return ("Not logged in. On the server, run `pixi run gui-link` in the .bcl_gui folder "
                "and open the link it prints.", 403)


# --- pages ------------------------------------------------------------------

@app.route("/")
def index():
    return render_template("index.html", runs=runs.list_runs(PLATFORM_DIR),
                           platform_dir=PLATFORM_DIR, jobs=jobs)


@app.route("/new", methods=["GET", "POST"])
def new_run():
    if request.method == "GET":
        return render_template("new.html", sheets=sample_sheets())

    run_id = request.form.get("run_id", "").strip()
    if not runs.RUN_ID_RE.match(run_id):
        flash("Run ID must look like xR123 (letter, R, number).", "error")
        return redirect(url_for("new_run"))
    run_dir = os.path.join(PLATFORM_DIR, run_id)
    if os.path.exists(run_dir):
        flash(f"{run_id} already exists.", "error")
        return redirect(url_for("run_page", run_id=run_id))

    upload = request.files.get("upload")
    if upload and upload.filename:
        name = secure_filename(upload.filename)
        if not name.endswith(".xlsx"):
            flash("The uploaded sheet must be an .xlsx file.", "error")
            return redirect(url_for("new_run"))
        os.makedirs(os.path.join(GUI_LOGS, "uploads"), exist_ok=True)
        sheet = os.path.join(GUI_LOGS, "uploads", name)
        upload.save(sheet)
    else:
        name = request.form.get("sheet", "")
        if name not in sample_sheets():
            flash("Choose a sample sheet or upload one.", "error")
            return redirect(url_for("new_run"))
        sheet = os.path.join(PLATFORM_DIR, "SampleSheets", name)

    # Sheet names carry the run ID (…_xR123.xlsx); a different one means the
    # wrong sheet was picked, which would process and email the wrong orders.
    named = runs.SHEET_RUN_ID_RE.findall(os.path.splitext(name)[0])
    if named and run_id.lower() not in (n.lower() for n in named):
        flash(f"The sheet {name} is for {named[-1]}, not {run_id}. Pick the sheet for {run_id}.", "error")
        return redirect(url_for("new_run"))

    # The control clone is shared, so for most operators it is owned by someone
    # else, and git refuses to read another user's repo without safe.directory.
    git = ["git", "-c", f"safe.directory={CONTROL_DIR}", "-c", f"safe.directory={CONTROL_DIR}/.git"]
    origin = subprocess.run(git + ["-C", CONTROL_DIR, "remote", "get-url", "origin"],
                            capture_output=True, text=True).stdout.strip()
    # Clone the control clone (no GitHub credentials needed), then point origin
    # back at GitHub so `git pull` in the run dir behaves as in a normal clone.
    steps = [("Copy pipeline", git + ["clone", CONTROL_DIR, run_dir], PLATFORM_DIR)]
    if origin:
        steps.append(("Set origin", ["git", "-C", run_dir, "remote", "set-url", "origin", origin], PLATFORM_DIR))
    steps += [
        ("Copy sample sheet", ["bash", "-c", 'mkdir -p metadata logs && cp "$0" metadata/', sheet], run_dir),
        ("Install software (pixi install)", [PIXI, "install"], run_dir),
        ("Prefill settings (pixi run init)", [PIXI, "run", "init", "--sheet", f"metadata/{name}"], run_dir),
    ]
    start_job(run_id, "setup", steps, os.path.join(GUI_LOGS, f"setup_{run_id}.log"))
    return redirect(url_for("run_page", run_id=run_id))


@app.route("/run/<run_id>")
def run_page(run_id):
    run_dir = run_dir_for(run_id)
    job = jobs.get(run_id)
    if not os.path.isdir(run_dir) and not job:
        abort(404)
    cron_text = runs.read_crontab()
    stage, label, detail = runs.run_status(run_dir, cron_text) if os.path.isdir(run_dir) else ("new", "Setting up", "")
    config = runs.read_config(run_dir) if os.path.isdir(run_dir) else {}
    line = runs.scheduled_line(cron_text, run_id)
    preflight_path = os.path.join(run_dir, "logs", "gui", "preflight.json")
    preflight = None
    if os.path.exists(preflight_path):
        with open(preflight_path) as handle:
            preflight = json.load(handle)
    data_dir = config.get("data_dir") or ""
    return render_template(
        "run.html", run_id=run_id, stage=stage, label=label, detail=detail,
        config=config, editable=EDITABLE, job=job,
        launched=os.path.exists(os.path.join(run_dir, ".auto_launched")),
        copy_complete=bool(data_dir) and os.path.exists(os.path.join(data_dir, "CopyComplete.txt")),
        check=runs.read_check(run_dir) if config else None,
        approval=runs.read_approval(run_dir) if config else None,
        cron_line=line, usb_dest=runs.usb_dest_from_line(line),
        preflight=preflight, logs=log_choices(run_dir, job))


def log_choices(run_dir, job):
    choices = {}
    if job:
        choices[f"Last action: {job.action}"] = job.log_path
    choices["Cron (scheduled run)"] = os.path.join(run_dir, "logs", "cron_run.log")
    choices["Workflow (snakemake)"] = newest(os.path.join(run_dir, "logs", "driver"), "snakemake_")
    choices["Publish"] = newest(os.path.join(run_dir, "logs"), "publish_")
    return {k: v for k, v in choices.items() if v}


@app.route("/run/<run_id>/log")
def run_log(run_id):
    run_dir = run_dir_for(run_id)
    choices = log_choices(run_dir, jobs.get(run_id))
    job = jobs.get(run_id)
    running = bool(job and job.running)
    return jsonify(text=tail(choices.get(request.args.get("name"))),
                   job_running=running, progress=job.progress() if running else None)


@app.route("/run/<run_id>/config", methods=["POST"])
def save_config(run_id):
    run_dir = run_dir_for(run_id)
    if os.path.exists(os.path.join(run_dir, ".auto_launched")):
        flash("This run has already started; settings can no longer be changed here.", "error")
    else:
        runs.set_config_values(run_dir, {k: request.form.get(k, "").strip() for k in EDITABLE})
        flash("Settings saved. Check the metadata again before approving.", "ok")
    return redirect(url_for("run_page", run_id=run_id))


@app.route("/run/<run_id>/preflight", methods=["POST"])
def preflight(run_id):
    run_dir = run_dir_for(run_id)
    out = os.path.join(run_dir, "logs", "gui", "preflight.json")

    def save(job, rc):
        if rc == 0:
            with open(out, "w") as handle:
                handle.write(job.outputs["Readiness checks"][1].strip().splitlines()[-1])

    start_job(run_id, "readiness checks",
              [("Readiness checks", [PIXI, "run", "python", os.path.join(CONTROL_DIR, "gui", "preflight.py")], run_dir)],
              os.path.join(run_dir, "logs", "gui", "preflight.log"), on_finish=save)
    return redirect(url_for("run_page", run_id=run_id))


@app.route("/run/<run_id>/check", methods=["POST"])
def check_metadata(run_id):
    run_dir = run_dir_for(run_id)
    # Bind the result to the inputs as they were when the check started.
    digest = runs.approval_hash(run_dir)

    def save(job, rc):
        validate_rc = job.outputs.get("Validate sheet", (None, ""))[0]
        dry_rc, dry_text = job.outputs.get("Dry run", (None, ""))
        report = runs.validation_report_path(run_dir)
        issues = runs.read_validation_issues(report) if validate_rc == 0 and os.path.exists(report) else []
        result = {"ok": validate_rc == 0 and dry_rc == 0, "validate_rc": validate_rc,
                  "dry_run_rc": dry_rc, "issues": issues, "sha256": digest,
                  "time": time.strftime("%Y-%m-%d %H:%M:%S"), **runs.parse_dry_run(dry_text)}
        with open(os.path.join(run_dir, "logs", "gui", "check.json"), "w") as handle:
            json.dump(result, handle, default=str)

    start_job(run_id, "metadata check",
              [("Validate sheet", [PIXI, "run", "validate"], run_dir),
               ("Dry run", [PIXI, "run", "dry-run"], run_dir)],
              os.path.join(run_dir, "logs", "gui", "check.log"), on_finish=save)
    return redirect(url_for("run_page", run_id=run_id))


@app.route("/run/<run_id>/report")
def validation_report(run_id):
    path = runs.validation_report_path(run_dir_for(run_id))
    if not os.path.exists(path):
        abort(404)
    return send_file(path, as_attachment=True)


@app.route("/run/<run_id>/approve", methods=["POST"])
def approve(run_id):
    run_dir = run_dir_for(run_id)
    check = runs.read_check(run_dir)
    if not (check and check["current"] and check["ok"]):
        flash("Run the metadata check (with the current sheet and settings) first.", "error")
    elif check["issues"] and not request.form.get("reviewed"):
        flash("Tick the box confirming you reviewed the listed issues.", "error")
    else:
        runs.write_approval(run_dir)
        flash("Approved.", "ok")
    return redirect(url_for("run_page", run_id=run_id))


@app.route("/run/<run_id>/revoke", methods=["POST"])
def revoke(run_id):
    runs.revoke_approval(run_dir_for(run_id))
    flash("Approval withdrawn.", "ok")
    return redirect(url_for("run_page", run_id=run_id))


@app.route("/run/<run_id>/schedule", methods=["POST"])
def schedule(run_id):
    run_dir = run_dir_for(run_id)
    approval = runs.read_approval(run_dir)
    usb = request.form.get("usb_dest", "").strip()
    if not (approval and approval["valid"]):
        flash("Approve the run before scheduling it.", "error")
    elif usb and not os.path.isdir(usb):
        flash(f"Drive folder {usb} does not exist (is the drive plugged in?).", "error")
    else:
        runs.add_cron(run_dir, usb)
        flash("Scheduled: checked every 30 minutes; starts once the sequencer finishes.", "ok")
    return redirect(url_for("run_page", run_id=run_id))


@app.route("/run/<run_id>/unschedule", methods=["POST"])
def unschedule(run_id):
    run_dir_for(run_id)
    runs.remove_cron(run_id)
    flash("Removed from the schedule.", "ok")
    return redirect(url_for("run_page", run_id=run_id))


def ssh_host():
    """The address the operator's own SSH session reached this server on.

    The machine's hostname (grthub_dragen.biochem.uci.edu) is not in DNS, so
    a tunnel command built from it fails on the operator's computer. Whatever
    address they just logged in with demonstrably works from there.
    """
    parts = os.environ.get("SSH_CONNECTION", "").split()
    return parts[2] if len(parts) == 4 else socket.getfqdn()


def print_link(port, host):
    user = os.environ.get("USER", "you")
    print("1. On your own computer, open a terminal and run:")
    print(f"     ssh -N -L {port}:localhost:{port} {user}@{host}")
    print("2. Then open this link in your browser (once; after that, bookmark")
    print(f"   http://localhost:{port}/ ):")
    print(f"     http://localhost:{port}/?token={LOGIN_TOKEN}\n")


def main():
    global PLATFORM_DIR, LOGIN_TOKEN, PORT
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=8000 + os.getuid() % 1000)
    parser.add_argument("--platform-dir", default=os.environ.get("BCL_GUI_PLATFORM_DIR", PLATFORM_DIR),
                        help="folder holding the run dirs and SampleSheets/ (default: parent of this clone)")
    parser.add_argument("--ssh-host", default=os.environ.get("BCL_GUI_SSH_HOST", ""),
                        help="server address to print in the tunnel command (default: the one you logged in to)")
    parser.add_argument("--print-link", action="store_true",
                        help="print the tunnel command and login link, then exit")
    parser.add_argument("--new-token", action="store_true",
                        help="replace the login token, logging out every browser")
    args = parser.parse_args()
    PLATFORM_DIR = os.path.realpath(args.platform_dir)
    PORT = args.port
    if args.new_token and os.path.exists(TOKEN_FILE):
        os.remove(TOKEN_FILE)
    LOGIN_TOKEN = load_or_create(TOKEN_FILE, lambda: secrets.token_urlsafe(24))
    # Kept on disk too, so a restart doesn't log everyone out.
    app.secret_key = load_or_create(os.path.join(STATE_DIR, "secret_key"), lambda: secrets.token_hex(32))

    host = args.ssh_host or ssh_host()
    if args.print_link:
        print_link(args.port, host)
        return
    print(f"\nManaging runs in {PLATFORM_DIR} on port {args.port}\n")
    if os.environ.get("INVOCATION_ID"):
        # Under systemd: keep the token out of the journal.
        print("Running as a service. For the login link, run `pixi run gui-link` in an SSH session.")
    else:
        print_link(args.port, host)
        print("Leave this window open while you use the page; Ctrl+C stops it.")
        print("Scheduled runs keep going after it stops.\n")
    app.run(host="127.0.0.1", port=args.port, threaded=True)


if __name__ == "__main__":
    main()
