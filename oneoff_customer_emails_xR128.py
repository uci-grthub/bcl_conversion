#!/usr/bin/env python3
"""One-off: send each xR128 order report to its customer, greeted by name.

Uses the reports in the PUBLISH mirror (not staging): publish_run.sh rebuilt
them there, so their share links point at the published copy. The pipeline
already sent those to the operator only; this re-sends each one to the order's
contact with "Dear GRT Hub User," replaced by the contact's first name.

  pixi run python oneoff_customer_emails_xR128.py                       # dry run
  pixi run python oneoff_customer_emails_xR128.py --test-to ADDR --order 1026I-53
  pixi run python oneoff_customer_emails_xR128.py --send                # all orders
  pixi run python oneoff_customer_emails_xR128.py --send --order 1026I-53 1126I-03
  --force   resend despite Reports/order_<id>/.customer_email_receipt
"""
import argparse
import datetime
import glob
import os
import subprocess
import sys

import pandas as pd
import yaml

REPO = os.path.dirname(os.path.abspath(__file__))
STAGING = REPO
MIRROR = "/mnt/jbod_localdisk/nextshare/bcl_convert/NovaSeqX/xR128"
METADATA = os.path.join(REPO, "metadata/261109_25B_25HVN2LT4_PE151_xR128.xlsx")
SENDER = "kstachel@uci.edu"
CC = "mloakes@uci.edu"
# Customer contacts and extra bcc addresses live in a gitignored local file,
# never in the repo:
#   bcc: [addr, ...]                       # added to BCC_COMMITTED
#   recipients: {order: [first name, email]}
#   sheet_typos: {order: summary-sheet email}   # sheet contact known wrong
CONTACTS = os.path.join(REPO, "customer_emails_xR128.yaml")
BCC_COMMITTED = ["chungs@uci.edu"]
GREETING = "Dear GRT Hub User,"


def load_contacts():
    if not os.path.isfile(CONTACTS):
        sys.exit(f"ERROR: missing {CONTACTS} (local, gitignored contact list)")
    with open(CONTACTS) as f:
        data = yaml.safe_load(f) or {}
    recipients = {str(k): tuple(v) for k, v in (data.get("recipients") or {}).items()}
    bcc = ",".join(dict.fromkeys(list(data.get("bcc") or []) + BCC_COMMITTED))
    typos = {str(k): v for k, v in (data.get("sheet_typos") or {}).items()}
    return recipients, bcc, typos


RECIPIENTS, BCC, SHEET_TYPOS = load_contacts()


def die(msg):
    sys.exit(f"ERROR: {msg}")


def summary_contacts():
    """order id -> set of contact emails from the metadata Summary sheet."""
    raw = pd.read_excel(METADATA, sheet_name="Summary", header=None)
    hdr = next(i for i, row in raw.iterrows() if "Order ID" in row.values)
    df = raw.iloc[hdr + 1:].set_axis(raw.iloc[hdr], axis=1)
    df = df[df["Order ID"].notna()]
    out = {}
    for oid, mail in zip(df["Order ID"], df["Contact (E-mail)"]):
        out.setdefault(str(oid).strip(), set()).add(str(mail).strip().lower())
    return out


def links(report_dir):
    path = os.path.join(report_dir, "_merged_links.yaml")
    with open(path) as f:
        data = yaml.safe_load(f) or {}
    found = set()
    for lanes in data.values():
        for orders in lanes.values():
            for entry in orders.values():
                found.add(entry["link"])
    return found


def check_all(orders):
    contacts = summary_contacts()
    missing = set(contacts) - set(RECIPIENTS)
    if missing:
        die(f"orders in Summary sheet with no recipient: {sorted(missing)}")
    for oid in orders:
        name, mail = RECIPIENTS[oid]
        expected = SHEET_TYPOS.get(oid, mail).lower()
        if contacts.get(oid) != {expected}:
            die(f"{oid}: recipient {mail} != Summary contact {contacts.get(oid)}")
        mdir = os.path.join(MIRROR, "Reports", f"order_{oid}")
        sdir = os.path.join(STAGING, "Reports", f"order_{oid}")
        for f in ("index.html", "md5sums.txt", "Download_Instructions.pdf", "_merged_links.yaml"):
            if not os.path.isfile(os.path.join(mdir, f)):
                die(f"{oid}: missing {mdir}/{f}")
        with open(os.path.join(mdir, "index.html")) as f:
            html = f.read()
        if html.count(GREETING) != 1:
            die(f"{oid}: expected exactly one '{GREETING}' in mirror index.html")
        # Mirror links must be the published share, not staging's.
        mlinks = links(mdir)
        if not mlinks:
            die(f"{oid}: no share links in mirror _merged_links.yaml")
        if os.path.isfile(os.path.join(sdir, "_merged_links.yaml")):
            shared = mlinks & links(sdir)
            if shared:
                die(f"{oid}: mirror report uses staging link(s) {sorted(shared)}")
        for link in mlinks:
            if link not in html:
                die(f"{oid}: mirror index.html does not contain its share link {link}")


def attachments(mdir):
    files = [os.path.join(mdir, "md5sums.txt"), os.path.join(mdir, "Download_Instructions.pdf")]
    for pat in ("flexbarOut_*.log", "flexbar_barcodes_*.txt", "flexbar_filesizes_*.txt"):
        files += sorted(glob.glob(os.path.join(mdir, pat)))
    return ";".join(files)


def send(oid, to, cc, bcc, dry_run, log_path):
    name, _ = RECIPIENTS[oid]
    mdir = os.path.join(MIRROR, "Reports", f"order_{oid}")
    with open(os.path.join(mdir, "index.html")) as f:
        html = f.read().replace(GREETING, f"Dear {name},")
    html_path = os.path.join(mdir, "index_customer.html")
    with open(html_path, "w") as f:
        f.write(html)
    env = dict(os.environ, EMAIL_BCC=bcc)
    if dry_run:
        env["SEND_EMAIL_DRY_RUN"] = "1"
    cmd = [
        sys.executable, os.path.join(REPO, "src/send_email_retry.py"),
        os.path.join(REPO, "src/send_email.py"), SENDER, to,
        f"Sequencing Report for Order {oid}", html_path, attachments(mdir), cc, oid,
    ]
    with open(log_path, "w") as logf:
        rc = subprocess.run(cmd, stdout=logf, stderr=subprocess.STDOUT, env=env).returncode
    with open(log_path) as logf:
        tail = [l.rstrip() for l in logf if "would send" in l or "sent successfully to" in l]
    return rc, tail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--order", nargs="+", help="only these order ids")
    ap.add_argument("--send", action="store_true", help="really send to customers")
    ap.add_argument("--test-to", help="send to this address only (no cc/bcc)")
    ap.add_argument("--force", action="store_true", help="ignore .customer_email_receipt")
    args = ap.parse_args()

    orders = args.order or list(RECIPIENTS)
    unknown = [o for o in orders if o not in RECIPIENTS]
    if unknown:
        die(f"unknown order(s): {unknown}")
    if args.send and args.test_to:
        die("--send and --test-to are exclusive")
    if not os.environ.get("GMAIL_APP_PASSWORD") and (args.send or args.test_to):
        die("GMAIL_APP_PASSWORD not set (run via `pixi run`, which loads ~/.env)")

    check_all(orders)
    os.makedirs(os.path.join(MIRROR, "logs"), exist_ok=True)
    mode = "SEND" if args.send else ("TEST" if args.test_to else "DRY RUN")
    print(f"[{mode}] {len(orders)} order(s) from {MIRROR}/Reports")

    failed = []
    for oid in orders:
        name, mail = RECIPIENTS[oid]
        receipt = os.path.join(MIRROR, "Reports", f"order_{oid}", ".customer_email_receipt")
        if args.send and os.path.exists(receipt) and not args.force:
            print(f"  {oid}: skip, already sent ({receipt}); --force to resend")
            continue
        if args.test_to:
            to, cc, bcc = args.test_to, args.test_to, ""
        else:
            to, cc, bcc = mail, CC, BCC
        log_path = os.path.join(MIRROR, "logs", f"customer_email_{oid}.log")
        rc, tail = send(oid, to, cc, bcc, dry_run=not (args.send or args.test_to), log_path=log_path)
        status = "ok" if rc == 0 else f"FAILED rc={rc} (see {log_path})"
        print(f"  {oid}: Dear {name}, -> {to}  {status}")
        for line in tail:
            print(f"      {line}")
        if rc != 0:
            failed.append(oid)
            continue
        if args.send:
            with open(receipt, "w") as rf:
                rf.write(f"sent_at: {datetime.datetime.now().isoformat(timespec='seconds')}\n")
                rf.write(f"subject: Sequencing Report for Order {oid}\n")
                rf.write(f"to: {to}\ncc: {cc}\nbcc: {bcc}\n")
    if failed:
        die(f"failed: {failed}")


if __name__ == "__main__":
    main()
