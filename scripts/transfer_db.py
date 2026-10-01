#!/usr/bin/env python3
"""transfer_db -- SQLite log of measured HPC3 backup transfer times.

backup_raw_run.sh and backup_processed_run.sh call `record` after every real
(non-dry-run) transfer, so transfer times are measured from the transfer itself
instead of reconstructed afterwards from ctime spreads or truncated rsync logs.

    python3 scripts/transfer_db.py record --kind raw --name <dir> ... --stats-file <rsync output>
    python3 scripts/transfer_db.py report [--kind raw|processed] [--run xR118] [--limit N]

The database is TRANSFER_DB, default /mnt/jbod_localdisk/nextshare/bcl_convert/NovaSeqX/
transfer_times.sqlite -- one file shared by every run dir, since each run dir
carries its own copy of these scripts.

Byte counts come from rsync's --stats summary. The backup scripts run rsync with
-h, which prints those in powers of 1000 to three significant figures, so the
bytes (and rates) here are accurate to ~0.5%; that is plenty for sizing --time
limits and spotting a stalled link.
"""

import argparse
import os
import re
import sqlite3
import sys
from datetime import datetime

DEFAULT_DB = "/mnt/jbod_localdisk/nextshare/bcl_convert/NovaSeqX/transfer_times.sqlite"

SCHEMA = """
CREATE TABLE IF NOT EXISTS transfers (
    id                INTEGER PRIMARY KEY,
    kind              TEXT NOT NULL,      -- raw | processed
    name              TEXT NOT NULL,      -- dir transferred: raw run dir name, or processed run id
    run_id            TEXT,               -- processed run id (xR###) when known
    src               TEXT NOT NULL,
    dest              TEXT NOT NULL,      -- host:path
    local_host        TEXT,
    user              TEXT,
    started_at        TEXT NOT NULL,      -- ISO 8601, local time with offset
    finished_at       TEXT NOT NULL,
    seconds           INTEGER NOT NULL,   -- wall time of the main rsync only (not verify)
    total_bytes       INTEGER,            -- rsync "Total file size"
    transferred_bytes INTEGER,            -- rsync "Total transferred file size" (less on a resume)
    sent_bytes        INTEGER,            -- bytes on the wire
    rsync_exit        INTEGER,            -- NULL when unknown (backfilled from a log)
    status            TEXT NOT NULL,      -- ok | failed | incomplete
    bwlimit           TEXT,
    notes             TEXT                -- provenance of backfilled rows
);
CREATE VIEW IF NOT EXISTS transfer_rates AS
SELECT id, kind, name, run_id, dest, started_at, finished_at, status,
       ROUND(seconds / 3600.0, 2)                                  AS hours,
       ROUND(total_bytes / 1e12, 3)                                AS total_tb,
       ROUND(transferred_bytes / 1e12, 3)                          AS transferred_tb,
       ROUND(transferred_bytes / NULLIF(seconds, 0) / 1048576.0, 1) AS mib_per_s,
       notes
FROM transfers;
"""

UNITS = {"": 1, "K": 1e3, "M": 1e6, "G": 1e9, "T": 1e12, "P": 1e15}


def parse_size(text):
    """'2.12T' / '1,234,567' / '313.63K' -> int bytes."""
    m = re.fullmatch(r"([\d.,]+)([KMGTP]?)", text.strip())
    if not m:
        return None
    return int(float(m.group(1).replace(",", "")) * UNITS[m.group(2)])


def parse_stats(path):
    """Pull the byte counts out of rsync --stats output (progress2 noise and all)."""
    out = {"total_bytes": None, "transferred_bytes": None, "sent_bytes": None}
    if not path or not os.path.exists(path):
        return out
    with open(path, "rb") as fh:
        # progress2 separates updates with \r; only the newline-terminated
        # summary lines matter, and they always come last.
        text = fh.read().decode("utf-8", "replace").replace("\r", "\n")
    patterns = {
        "total_bytes": r"^Total file size: ([\d.,]+[KMGTP]?) bytes",
        "transferred_bytes": r"^Total transferred file size: ([\d.,]+[KMGTP]?) bytes",
        "sent_bytes": r"^Total bytes sent: ([\d.,]+[KMGTP]?)",
    }
    for key, pat in patterns.items():
        hits = re.findall(pat, text, re.MULTILINE)
        if hits:
            out[key] = parse_size(hits[-1])
    return out


def connect(path):
    con = sqlite3.connect(path, timeout=60)
    con.executescript(SCHEMA)
    return con


def iso(epoch):
    return datetime.fromtimestamp(epoch).astimezone().isoformat(timespec="seconds")


def cmd_record(args):
    stats = parse_stats(args.stats_file)
    # Explicit byte counts (backfill from old logs) win over the parsed stats.
    for key in stats:
        if getattr(args, key) is not None:
            stats[key] = getattr(args, key)
    row = {
        "kind": args.kind,
        "name": args.name,
        "run_id": args.run_id or None,
        "src": args.src,
        "dest": args.dest,
        "local_host": args.local_host or os.uname().nodename,
        "user": os.environ.get("USER") or os.environ.get("LOGNAME"),
        "started_at": iso(args.started),
        "finished_at": iso(args.finished),
        "seconds": args.finished - args.started,
        "rsync_exit": args.rsync_exit,
        "status": args.status,
        "bwlimit": args.bwlimit or None,
        "notes": args.notes or None,
        **stats,
    }
    with connect(args.db) as con:
        cols = ", ".join(row)
        marks = ", ".join(f":{k}" for k in row)
        cur = con.execute(f"INSERT INTO transfers ({cols}) VALUES ({marks})", row)
    rate = ""
    if stats["transferred_bytes"] and row["seconds"]:
        rate = f", {stats['transferred_bytes'] / row['seconds'] / 2**20:.0f} MiB/s"
    print(f"recorded transfer #{cur.lastrowid} in {args.db}: "
          f"{row['seconds'] / 3600:.2f} h{rate}, status {args.status}")


def cmd_report(args):
    if not os.path.exists(args.db):
        sys.exit(f"no transfer database at {args.db}")
    where, params = [], []
    if args.kind:
        where.append("kind = ?")
        params.append(args.kind)
    if args.run:
        where.append("(run_id = ? OR name = ?)")
        params += [args.run, args.run]
    sql = "SELECT * FROM transfer_rates"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY started_at DESC LIMIT ?"
    params.append(args.limit)
    with connect(args.db) as con:
        cur = con.execute(sql, params)
        cols = [d[0] for d in cur.description]
        rows = [["" if v is None else str(v) for v in r] for r in cur.fetchall()]
    widths = [max(len(c), *(len(r[i]) for r in rows)) if rows else len(c)
              for i, c in enumerate(cols)]
    print("  ".join(c.ljust(w) for c, w in zip(cols, widths)))
    for r in rows:
        print("  ".join(v.ljust(w) for v, w in zip(r, widths)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", default=os.environ.get("TRANSFER_DB") or DEFAULT_DB)
    sub = ap.add_subparsers(dest="cmd", required=True)

    rec = sub.add_parser("record", help="insert one transfer")
    rec.add_argument("--kind", required=True, choices=["raw", "processed"])
    rec.add_argument("--name", required=True)
    rec.add_argument("--run-id")
    rec.add_argument("--src", required=True)
    rec.add_argument("--dest", required=True)
    rec.add_argument("--started", type=int, required=True, help="epoch seconds")
    rec.add_argument("--finished", type=int, required=True, help="epoch seconds")
    rec.add_argument("--rsync-exit", type=int, help="omit when unknown")
    rec.add_argument("--status", required=True, choices=["ok", "failed", "incomplete"])
    rec.add_argument("--stats-file", help="captured rsync --stats output")
    rec.add_argument("--total-bytes", type=int, help="override the parsed value")
    rec.add_argument("--transferred-bytes", type=int, help="override the parsed value")
    rec.add_argument("--sent-bytes", type=int, help="override the parsed value")
    rec.add_argument("--bwlimit")
    rec.add_argument("--local-host", help="host the rsync ran on (default: this one)")
    rec.add_argument("--notes")
    rec.set_defaults(func=cmd_record)

    rep = sub.add_parser("report", help="print recorded transfers, newest first")
    rep.add_argument("--kind", choices=["raw", "processed"])
    rep.add_argument("--run", help="processed run id or transferred dir name")
    rep.add_argument("--limit", type=int, default=50)
    rep.set_defaults(func=cmd_report)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
