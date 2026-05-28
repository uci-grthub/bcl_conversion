#!/usr/bin/env python3
"""
Test script for Nextcloud OCS share token management.

Usage:
  # Create/find a share and print its auto-assigned token
  python scripts/test_nextcloud_token.py --path /DragenExt3/path/to/folder

  # Create/find a share then reassign a specific token (e.g. to restore a known link)
  python scripts/test_nextcloud_token.py --path /DragenExt3/path/to/folder --token abc123xyz

  # Reassign a token on an already-known share ID (skip the POST step)
  python scripts/test_nextcloud_token.py --share-id 42 --token abc123xyz

Reads credentials from environment variables:
  NEXTCLOUD_URL, NEXTCLOUD_USER, NEXTCLOUD_PASSWORD
"""

import argparse
import os
import re
import subprocess
import sys
import urllib.parse


def require_env(name):
    val = os.environ.get(name)
    if not val:
        sys.exit(f"Error: {name} environment variable not set")
    return val


def extract_xml(text, tag):
    m = re.search(rf'<{tag}>(.*?)</{tag}>', text)
    return m.group(1) if m else None


def run_curl(cmd, label):
    print(f"\n[{label}]")
    print("  " + " ".join(f"'{a}'" if " " in a else a for a in cmd))
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    stdout = result.stdout
    stderr = result.stderr
    # Split off HTTP_CODE trailer if present
    lines = stdout.split("\n")
    http_code = next((l.split(":", 1)[1] for l in lines if l.startswith("HTTP_CODE:")), None)
    body = "\n".join(l for l in lines if not l.startswith("HTTP_CODE:"))
    if stderr:
        print(f"  stderr: {stderr.strip()}")
    if http_code:
        print(f"  HTTP {http_code}")
    return body, http_code


def get_existing_share(nc_url, user, password, nc_path):
    encoded = urllib.parse.quote(nc_path, safe="/")
    cmd = [
        "curl", "-s", "-w", "\nHTTP_CODE:%{http_code}",
        "-X", "GET",
        "-u", f"{user}:{password}",
        "-H", "OCS-APIRequest: true",
        f"{nc_url}/ocs/v2.php/apps/files_sharing/api/v1/shares?path={encoded}&reshares=true",
    ]
    body, http_code = run_curl(cmd, "GET existing shares")
    return body, http_code


def create_share(nc_url, user, password, nc_path):
    cmd = [
        "curl", "-s", "-w", "\nHTTP_CODE:%{http_code}",
        "-X", "POST",
        "-u", f"{user}:{password}",
        "-H", "OCS-APIRequest: true",
        "-d", f"path={nc_path}",
        "-d", "shareType=3",
        f"{nc_url}/ocs/v2.php/apps/files_sharing/api/v1/shares",
    ]
    body, http_code = run_curl(cmd, "POST create share")
    return body, http_code


def update_share_token(nc_url, user, password, share_id, new_token):
    cmd = [
        "curl", "-s", "-w", "\nHTTP_CODE:%{http_code}",
        "-X", "PUT",
        "-u", f"{user}:{password}",
        "-H", "OCS-APIRequest: true",
        "-d", f"token={new_token}",
        f"{nc_url}/ocs/v2.php/apps/files_sharing/api/v1/shares/{share_id}",
    ]
    body, http_code = run_curl(cmd, f"PUT update token for share {share_id}")
    return body, http_code


def main():
    parser = argparse.ArgumentParser(description="Test Nextcloud OCS share token management")
    parser.add_argument("--path", help="Nextcloud path to share (e.g. /DragenExt3/...)")
    parser.add_argument("--share-id", help="Known share ID (skips POST/GET step)")
    parser.add_argument("--token", help="Custom token to assign via PUT (optional)")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without executing")
    args = parser.parse_args()

    if not args.path and not args.share_id:
        parser.error("Provide --path and/or --share-id")

    nc_url = require_env("NEXTCLOUD_URL").rstrip("/")
    user = require_env("NEXTCLOUD_USER")
    password = require_env("NEXTCLOUD_PASSWORD")

    share_id = args.share_id
    share_token = None
    share_url = None

    # --- Step 1: resolve share ID if not provided ---
    if not share_id:
        body, http_code = create_share(nc_url, user, password, args.path)
        print(f"\n  Response body:\n{body}")

        if http_code in ("200", "201"):
            share_id = extract_xml(body, "id")
            share_token = extract_xml(body, "token")
            share_url = extract_xml(body, "url")
        elif http_code in ("400", "403"):
            print("  Share may already exist — fetching via GET")
            body, http_code = get_existing_share(nc_url, user, password, args.path)
            print(f"\n  Response body:\n{body}")
            share_id = extract_xml(body, "id")
            share_token = extract_xml(body, "token")
            share_url = extract_xml(body, "url")
        else:
            sys.exit(f"Unexpected HTTP {http_code} from POST")

        if not share_id:
            sys.exit("Could not extract share ID from response")

        print(f"\n  Share ID    : {share_id}")
        print(f"  Token       : {share_token}")
        print(f"  URL         : {share_url}")

    # --- Step 2: optionally update token ---
    if args.token:
        print(f"\nWill update share {share_id} token -> '{args.token}'")
        body, http_code = update_share_token(nc_url, user, password, share_id, args.token)
        print(f"\n  Response body:\n{body}")

        if http_code == "200":
            new_token = extract_xml(body, "token")
            new_url = extract_xml(body, "url")
            print(f"\n  New Token   : {new_token}")
            print(f"  New URL     : {new_url}")
        else:
            print(f"  PUT failed with HTTP {http_code}")
    else:
        print("\n(No --token specified; using server-assigned token above)")


if __name__ == "__main__":
    main()
