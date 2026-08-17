#!/usr/bin/env python3
"""
Repoint existing public share links at a different copy of the same run data.

The OCS Shares API cannot move a share to a new path -- a share is bound to a
fileid and PUT /shares/{id} has no `path` parameter. It does accept `token`,
so the customer-facing URL can be preserved by moving its token onto a share
that already points at the desired path:

    1. GET  the share on the source path      -> id S, token T
    2. GET  (or POST) the share on the dest   -> id J
    3. PUT  token=<scratch> on S              -- frees T (tokens are unique)
    4. PUT  token=T on J                      -- URL now serves the dest path
    5. GET  J and confirm token + path

Step 3 parks the source share rather than deleting it, so the whole operation
is reversible: PUT token=T back onto S.

Usage:
    pixi run python scripts/repoint_shares.py --snapshot        # read-only, do this first
    pixi run python scripts/repoint_shares.py                   # dry run (default)
    pixi run python scripts/repoint_shares.py --only <project> --apply
    pixi run python scripts/repoint_shares.py --apply
    pixi run python scripts/repoint_shares.py --rollback logs/repoint_shares_snapshot_<ts>.json

Credentials come from the environment (NEXTCLOUD_URL / NEXTCLOUD_USER /
NEXTCLOUD_PASSWORD), which pixi's activation loads from ~/.env or ../.env.
"""

import argparse
import glob
import json
import os
import random
import re
import string
import subprocess
import sys
import time
import urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Pure helpers only. The curl wrappers in that module echo the full command --
# including `-u user:password` -- to stdout, which would put the Nextcloud
# password in the snapshot log we are about to write, so this file does its own
# (quiet) requests below.
from test_nextcloud_token import load_env_file, require_env  # noqa: E402

OCS_BASE = "/ocs/v2.php/apps/files_sharing/api/v1/shares"
SHARE_TYPE_PUBLIC_LINK = "3"

DEFAULT_SRC_PREFIX = "/dragenshare/testing_illumina/NovaSeqX/xR105"
DEFAULT_DST_PREFIX = "/Jbod2/bcl_convert/NovaSeqX/xR105_ks"


# --------------------------------------------------------------------------
# OCS plumbing
# --------------------------------------------------------------------------

class Nextcloud:
    def __init__(self, url, user, password):
        self.url = url.rstrip("/")
        self.user = user
        self.password = password

    def _curl(self, method, path_and_query, data=None, retries=5):
        """Run one OCS request. Returns (body, http_code). Never logs credentials."""
        for attempt in range(1, retries + 1):
            cmd = [
                "curl", "-s", "-w", "\nHTTP_CODE:%{http_code}",
                "-X", method,
                "-u", f"{self.user}:{self.password}",
                "-H", "OCS-APIRequest: true",
            ]
            for key, val in (data or {}).items():
                cmd += ["-d", f"{key}={val}"]
            cmd.append(f"{self.url}{path_and_query}")

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            lines = result.stdout.split("\n")
            code = next((l.split(":", 1)[1] for l in lines if l.startswith("HTTP_CODE:")), None)
            body = "\n".join(l for l in lines if not l.startswith("HTTP_CODE:"))
            if code == "429" and attempt < retries:
                time.sleep(min(5 * attempt, 30))
                continue
            return body, code
        return body, code

    def shares_for_path(self, nc_path):
        q = urllib.parse.quote(nc_path, safe="/")
        return self._curl("GET", f"{OCS_BASE}?path={q}&reshares=true")

    def share_by_id(self, share_id):
        return self._curl("GET", f"{OCS_BASE}/{share_id}")

    def create_public_share(self, nc_path):
        return self._curl("POST", OCS_BASE,
                          {"path": nc_path, "shareType": SHARE_TYPE_PUBLIC_LINK})

    def set_token(self, share_id, token):
        return self._curl("PUT", f"{OCS_BASE}/{share_id}", {"token": token})


FIELDS = ("id", "share_type", "token", "url", "path", "uid_owner",
          "permissions", "expiration", "file_source")


def parse_elements(body):
    """Pull the <element> records out of an OCS XML response."""
    try:
        root = ET.fromstring(body)
    except ET.ParseError:
        return []
    data = root.find("data")
    if data is None:
        return []
    elements = data.findall("element") or ([data] if data.find("id") is not None else [])
    out = []
    for el in elements:
        rec = {}
        for f in FIELDS:
            node = el.find(f)
            rec[f] = node.text if node is not None else None
        out.append(rec)
    return out


def public_links(elements):
    """Every public-link share in an OCS result set. A path can carry several."""
    return [r for r in elements if r.get("share_type") == SHARE_TYPE_PUBLIC_LINK]


def public_link(elements, prefer_token=None):
    """Pick the public-link share to act on.

    A path can hold more than one public link (re-running project_link against a
    path that already had a share adds another). When we know which token we care
    about, match on it -- taking whichever came back first otherwise picks an
    unrelated share and makes a live link look like a mismatch.
    """
    links = public_links(elements)
    if prefer_token:
        for rec in links:
            if rec.get("token") == prefer_token:
                return rec
    return links[0] if links else None


def ocs_status(body):
    m = re.search(r"<statuscode>(\d+)</statuscode>", body or "")
    return m.group(1) if m else None


# --------------------------------------------------------------------------
# Project inventory
# --------------------------------------------------------------------------

def discover_projects():
    """(config_id, project, order_id, token) for every project_links yaml on disk."""
    import yaml

    rows = []
    for path in sorted(glob.glob("logs/lane*/project_links_lane*---*.yaml")):
        with open(path) as fh:
            data = yaml.safe_load(fh) or {}
        for project, configs in data.items():
            for config_id, orders in configs.items():
                for order_id, val in orders.items():
                    link = val.get("link") if isinstance(val, dict) else val
                    token = link.rsplit("/s/", 1)[-1] if link else None
                    rows.append({
                        "yaml": path,
                        "project": project,
                        "config_id": config_id,
                        "order_id": order_id,
                        "yaml_link": link,
                        "yaml_token": token,
                    })
    return rows


def scratch_token(seed):
    alphabet = string.ascii_letters + string.digits
    return "prk" + "".join(random.choice(alphabet) for _ in range(12))


# --------------------------------------------------------------------------
# Snapshot
# --------------------------------------------------------------------------

def take_snapshot(nc, rows, src_prefix, dst_prefix, stamp):
    """Read-only capture of both sides. Returns (snapshot_dict, ok)."""
    snap = {
        "taken": datetime.now().isoformat(timespec="seconds"),
        "nextcloud_url": nc.url,
        "nextcloud_user": nc.user,
        "src_prefix": src_prefix,
        "dst_prefix": dst_prefix,
        "projects": [],
    }
    ok = True
    for row in rows:
        src_path = f"{src_prefix}/output/{row['config_id']}/{row['project']}"
        dst_path = f"{dst_prefix}/output/{row['config_id']}/{row['project']}"
        entry = dict(row, src_path=src_path, dst_path=dst_path)

        for side, nc_path in (("src", src_path), ("dst", dst_path)):
            body, code = nc.shares_for_path(nc_path)
            entry[f"{side}_http"] = code
            entry[f"{side}_raw"] = body
            if code != "200":
                # 404 here means "no share on this path", which is legitimate
                # state to record; anything else is a failed read.
                if ocs_status(body) not in ("404",):
                    ok = False
                entry[f"{side}_share"] = None
                entry[f"{side}_shares"] = []
                continue
            elements = parse_elements(body)
            entry[f"{side}_shares"] = public_links(elements)
            entry[f"{side}_share"] = public_link(elements, prefer_token=row["yaml_token"])

        snap["projects"].append(entry)
        time.sleep(0.2)
    return snap, ok


def write_snapshot(snap, stamp):
    os.makedirs("logs", exist_ok=True)
    json_path = f"logs/repoint_shares_snapshot_{stamp}.json"
    log_path = f"logs/repoint_shares_snapshot_{stamp}.log"

    with open(json_path, "w") as fh:
        json.dump(snap, fh, indent=2)

    with open(log_path, "w") as fh:
        fh.write(f"share snapshot {snap['taken']}\n")
        fh.write(f"server   : {snap['nextcloud_url']} (user {snap['nextcloud_user']})\n")
        fh.write(f"src      : {snap['src_prefix']}\n")
        fh.write(f"dst      : {snap['dst_prefix']}\n")
        fh.write(f"projects : {len(snap['projects'])}\n\n")
        for e in snap["projects"]:
            fh.write(f"=== {e['project']}  [{e['config_id']}  order {e['order_id']}]\n")
            fh.write(f"    yaml token : {e['yaml_token']}  ({e['yaml']})\n")
            for side in ("src", "dst"):
                sh = e.get(f"{side}_share")
                label = "src (staging)" if side == "src" else "dst (jbod)   "
                path = e[f"{side}_path"]
                if not sh:
                    fh.write(f"    {label}: MISSING  http={e[f'{side}_http']}  {path}\n")
                    continue
                fh.write(f"    {label}: id={sh['id']} token={sh['token']} "
                         f"perms={sh['permissions']} exp={sh['expiration'] or '-'} "
                         f"fileid={sh['file_source']}\n")
                fh.write(f"                    path={sh['path']}\n")
                fh.write(f"                    url={sh['url']}\n")
                others = [o for o in e.get(f"{side}_shares", []) if o["id"] != sh["id"]]
                for o in others:
                    fh.write(f"                    also on this path: id={o['id']} "
                             f"token={o['token']}\n")
            fh.write("\n")
    return json_path, log_path


def summarize(snap):
    """Classify each project against the desired end state."""
    plans = []
    for e in snap["projects"]:
        src, dst = e.get("src_share"), e.get("dst_share")
        want = e["yaml_token"]
        if dst and dst["token"] == want:
            state = "done"          # jbod share already owns the advertised token
        elif not src and not dst:
            state = "no-share"      # nothing on either side
        elif not src:
            state = "no-source"     # token lives somewhere we did not look
        elif src["token"] != want:
            state = "token-mismatch"
        elif not dst:
            state = "create-dst"
        else:
            state = "repoint"
        plans.append(dict(e, state=state))
    return plans


# --------------------------------------------------------------------------
# Cutover
# --------------------------------------------------------------------------

def cutover(nc, plans, stamp, apply):
    log_path = f"logs/repoint_shares_{stamp}.log"
    mode = "APPLY" if apply else "DRY RUN"
    failures = []

    with open(log_path, "w", buffering=1) as fh:
        def say(msg):
            print(msg)
            fh.write(msg + "\n")

        say(f"# repoint_shares {mode} {datetime.now().isoformat(timespec='seconds')}")
        for p in plans:
            name = p["project"]
            src, dst = p.get("src_share"), p.get("dst_share")
            want = p["yaml_token"]

            if p["state"] == "done":
                say(f"[skip] {name}: jbod share {dst['id']} already holds {want}")
                continue
            if p["state"] in ("no-share", "no-source", "token-mismatch"):
                say(f"[skip] {name}: {p['state']} "
                    f"(src={src['token'] if src else None} want={want})")
                continue

            park = scratch_token(want)
            say(f"[plan] {name}")
            say(f"       park  src share {src['id']} token {want} -> {park}")
            if p["state"] == "create-dst":
                say(f"       POST  new public share on {p['dst_path']}")
            else:
                say(f"       set   dst share {dst['id']} token {dst['token']} -> {want}")
            if not apply:
                continue

            # 1. create the destination share if it does not exist yet
            if p["state"] == "create-dst":
                body, code = nc.create_public_share(p["dst_path"])
                rec = public_link(parse_elements(body))
                if code not in ("200", "201") or not rec:
                    say(f"       FAIL  POST http={code} ocs={ocs_status(body)}")
                    failures.append(name)
                    continue
                dst = rec
                say(f"       ok    created dst share {dst['id']} token {dst['token']}")

            # 2. free the token from the source share
            body, code = nc.set_token(src["id"], park)
            if code != "200":
                say(f"       FAIL  park http={code} ocs={ocs_status(body)} -- src untouched")
                failures.append(name)
                continue
            say(f"       ok    src share {src['id']} parked as {park}")

            # 3. move the real token onto the destination share
            body, code = nc.set_token(dst["id"], want)
            if code != "200":
                say(f"       FAIL  set token http={code} ocs={ocs_status(body)}")
                say(f"       ROLLBACK restoring {want} to src share {src['id']}")
                rb_body, rb_code = nc.set_token(src["id"], want)
                say(f"       rollback http={rb_code} ocs={ocs_status(rb_body)}")
                failures.append(name)
                continue

            # 4. confirm from the server, not from the PUT response
            body, code = nc.share_by_id(dst["id"])
            rec = (public_link(parse_elements(body), prefer_token=want)
                   or (parse_elements(body) or [None])[0])
            if not rec or rec.get("token") != want:
                say(f"       FAIL  verify: share {dst['id']} token="
                    f"{rec.get('token') if rec else None} expected={want}")
                failures.append(name)
                continue
            say(f"       ok    dst share {dst['id']} now serves {want}")
            say(f"       ok    path={rec.get('path')}")
            time.sleep(0.3)

        say(f"# done: {len(plans)} projects, {len(failures)} failures")
        if failures:
            say("# failed: " + ", ".join(failures))

    return log_path, failures


def rollback(nc, snapshot_path):
    with open(snapshot_path) as fh:
        snap = json.load(fh)
    failures = []
    for e in snap["projects"]:
        src = e.get("src_share")
        if not src:
            continue
        body, code = nc.set_token(src["id"], src["token"])
        status = "ok" if code == "200" else f"FAIL http={code} ocs={ocs_status(body)}"
        print(f"[rollback] {e['project']}: share {src['id']} -> {src['token']}  {status}")
        if code != "200":
            failures.append(e["project"])
    return failures


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--snapshot", action="store_true",
                    help="read-only: capture current share state and exit")
    ap.add_argument("--apply", action="store_true",
                    help="perform the cutover (default is a dry run)")
    ap.add_argument("--only", help="limit to a single project folder name")
    ap.add_argument("--src-prefix", default=DEFAULT_SRC_PREFIX)
    ap.add_argument("--dst-prefix", default=DEFAULT_DST_PREFIX)
    ap.add_argument("--rollback", metavar="SNAPSHOT_JSON",
                    help="restore source-share tokens recorded in a snapshot file")
    args = ap.parse_args()

    load_env_file(os.path.expanduser("~/.env"))
    load_env_file("/staging/nextcloud/testing_illumina/.env")
    nc = Nextcloud(require_env("NEXTCLOUD_URL"),
                   os.environ.get("NEXTCLOUD_USER") or require_env("NEXTCLOUD_USER"),
                   require_env("NEXTCLOUD_PASSWORD"))

    if args.rollback:
        return 1 if rollback(nc, args.rollback) else 0

    rows = discover_projects()
    if args.only:
        rows = [r for r in rows if r["project"] == args.only]
        if not rows:
            sys.exit(f"no project matching {args.only!r} in logs/lane*/project_links_*.yaml")

    stamp = datetime.now().strftime("%Y%m%dT%H%M%S")
    print(f"reading share state for {len(rows)} project(s)...")
    snap, ok = take_snapshot(nc, rows, args.src_prefix, args.dst_prefix, stamp)
    json_path, log_path = write_snapshot(snap, stamp)
    print(f"snapshot: {json_path}\n          {log_path}")
    if not ok:
        print("ERROR: at least one share query failed; snapshot is incomplete", file=sys.stderr)
        return 1

    plans = summarize(snap)
    counts = {}
    for p in plans:
        counts[p["state"]] = counts.get(p["state"], 0) + 1
    print("state: " + "  ".join(f"{k}={v}" for k, v in sorted(counts.items())))

    if args.snapshot:
        return 0

    cut_log, failures = cutover(nc, plans, stamp, args.apply)
    print(f"log: {cut_log}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
