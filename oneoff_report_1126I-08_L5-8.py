#!/usr/bin/env python3
"""One-off: lanes 5-8 subset of the Order 1126I-08 report (xR126).

Cuts Reports/order_1126I-08/index.html down to lanes 5-8 instead of regenerating
it, so sample names (P numbering), stats and plot links stay exactly as in the
full report that was already sent. md5sums.txt is filtered the same way; the
Download_Instructions.pdf is copied unchanged.

  pixi run python oneoff_report_1126I-08_L5-8.py            # build + check (dry run)
  pixi run python oneoff_report_1126I-08_L5-8.py --send     # build + check + email
  --force   rebuild an existing output dir / resend despite .email_receipt
"""
import argparse
import datetime
import os
import re
import shutil
import subprocess
import sys

ORDER = "1126I-08"
KEEP = {5, 6, 7, 8}
SRC_DIR = f"Reports/order_{ORDER}"
OUT_DIR = f"Reports/order_{ORDER}_L5-8"
SENDER = RECEIVER = CC = "kstachel@uci.edu"
SUBJECT = f"Sequencing Report for Order {ORDER} (Lanes 5-8)"
BLOCK = '<div style="background: #e6f2ff;'
SAMPLES_HDR = "<!-- Samples Section Header -->"
NAME_RE = re.compile(r'<h2 style="color: #333333; font-size: 20px; margin: 0 0 15px 0;">(xR126-L(\d)-[^<]+)</h2>')


def die(msg):
    sys.exit(f"ERROR: {msg}")


def check(cond, msg):
    if not cond:
        die(msg)


def lane_links(yaml_text):
    links = {}
    for m in re.finditer(rf"lane(\d+):\n\s+{re.escape(ORDER)}:\n(?:\s+group:.*\n)?\s+link: (\S+)", yaml_text):
        links[int(m.group(1))] = m.group(2)
    return links


def build_html(html):
    # 1. title
    old_title = "(Lane [1, 2, 3, 4, 5, 6, 7, 8])"
    check(html.count(old_title) == 1, f"title {old_title!r} not found exactly once")
    html = html.replace(old_title, "(Lane [5, 6, 7, 8])")

    # 2. Direct Links table rows
    i = html.find("<tbody>")
    j = html.find("</tbody>", i)
    check(i >= 0 and j > i, "Direct Links <tbody> not found")
    rows = re.findall(r"<tr [^>]*>.*?</tr>\n?", html[i + len("<tbody>"):j], flags=re.S)
    check(len(rows) == 8, f"expected 8 Direct Links rows, found {len(rows)}")
    kept_rows = []
    for r in rows:
        tds = re.findall(r"<td[^>]*>(.*?)</td>", r, flags=re.S)
        check(len(tds) >= 3 and tds[2].strip().isdigit(), f"cannot read lane cell in row: {r[:120]}")
        if int(tds[2].strip()) in KEEP:
            kept_rows.append(r)
    check(len(kept_rows) == 4, f"expected 4 kept rows, got {len(kept_rows)}")
    html = html[:i] + "<tbody>\n" + "".join(kept_rows) + html[j:]

    # 3. Sample Details project blocks
    s = html.find(SAMPLES_HDR)
    check(s >= 0, "samples section header not found")
    head, rest = html[:s], html[s:]
    parts = rest.split(BLOCK)
    check(len(parts) == 9, f"expected 8 project blocks, found {len(parts) - 1}")
    out = [parts[0]]
    for p in parts[1:]:
        lanes = {int(l) for _, l in NAME_RE.findall(p)}
        check(len(lanes) == 1, f"project block has lanes {sorted(lanes)}; expected exactly one")
        if lanes <= KEEP:
            out.append(BLOCK + p)
    check(len(out) == 5, f"expected 4 kept project blocks, got {len(out) - 1}")
    return head + "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--send", action="store_true")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()

    src_html = open(f"{SRC_DIR}/index.html").read()
    links = lane_links(open(f"{SRC_DIR}/_merged_links.yaml").read())
    check(sorted(links) == list(range(1, 9)), f"lane links in yaml: {sorted(links)}")

    html = build_html(src_html)

    # md5s
    md5_lines = [l for l in open(f"{SRC_DIR}/md5sums.txt") if re.search(r"\s\./xR126-L[5-8]-", l)]

    # checks
    names = [n for n, _ in NAME_RE.findall(html)]
    orig_names = [n for n, l in NAME_RE.findall(src_html) if int(l) in KEEP]
    check(not re.search(r"xR126-L[1-4]-", html), "lanes 1-4 sample names left in HTML")
    check(len(names) == 48, f"expected 48 samples, found {len(names)}")
    check(names == orig_names, "sample names/order differ from the full report")
    for lane, url in links.items():
        if lane in KEEP:
            check(url in html, f"lane {lane} link {url} missing")
        else:
            check(url not in html, f"lane {lane} link {url} still present")
    check(len(md5_lines) == 96, f"expected 96 md5 lines, found {len(md5_lines)}")
    md5_names = {l.split()[1].lstrip("./").rsplit("-R", 1)[0] for l in md5_lines}
    check(md5_names == set(names), "md5 sample names do not match report samples")

    # write
    if os.path.exists(OUT_DIR):
        receipt = f"{OUT_DIR}/.email_receipt"
        if os.path.exists(receipt) and not a.force:
            die(f"{receipt} exists (already sent); use --force to rebuild/resend")
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(f"{OUT_DIR}/index.html", "w") as f:
        f.write(html)
    with open(f"{OUT_DIR}/md5sums.txt", "w") as f:
        f.writelines(md5_lines)
    shutil.copy2(f"{SRC_DIR}/Download_Instructions.pdf", f"{OUT_DIR}/Download_Instructions.pdf")

    print(f"wrote {OUT_DIR}/ : index.html ({len(html)} B), md5sums.txt ({len(md5_lines)} lines), Download_Instructions.pdf")
    print(f"samples: {len(names)}  ({names[0]} .. {names[-1]})")
    for lane in sorted(KEEP):
        print(f"  lane {lane}: {links[lane]}")

    if not a.send:
        print("dry run: not sent (use --send)")
        return

    receipt = f"{OUT_DIR}/.email_receipt"
    if os.path.exists(receipt) and not a.force:
        die(f"{receipt} exists; use --force to resend")
    cmd = [sys.executable, "src/send_email_retry.py", "src/send_email.py", SENDER, RECEIVER, SUBJECT,
           f"{OUT_DIR}/index.html", f"{OUT_DIR}/md5sums.txt;{OUT_DIR}/Download_Instructions.pdf",
           CC, f"{ORDER}_L5-8"]
    r = subprocess.run(cmd)
    check(r.returncode == 0, f"email send failed (exit {r.returncode})")
    with open(receipt, "w") as f:
        f.write(f"sent_at: {datetime.datetime.now().isoformat(timespec='seconds')}\n"
                f"subject: {SUBJECT}\nto: {RECEIVER}\ncc: {CC}\n")
    print(f"sent; receipt {receipt}")


if __name__ == "__main__":
    main()
