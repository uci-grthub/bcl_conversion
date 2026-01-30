#!/usr/bin/env python3
"""
Script to generate Nextcloud share links for all .fastq.gz files in a project directory.
- Recursively finds all .fastq.gz files under a given root directory
- For each file, constructs the Nextcloud path (as in project_link rule)
- Uses Nextcloud OCS API to create or fetch a share link for each file
- Outputs a YAML mapping of file paths to share links

Usage:
  python3 src/generate_nextcloud_links.py /path/to/project_root > nextcloud_links.yaml

Environment variables required:
  NEXTCLOUD_URL      (e.g. https://precision.biochem.uci.edu)
  NEXTCLOUD_USER     (e.g. kstachel)
  NEXTCLOUD_PASSWORD (e.g. app password)

"""
import os
import sys
import subprocess
import urllib.parse
import yaml
from pathlib import Path

def get_env(var):
    val = os.environ.get(var)
    if not val:
        print(f"ERROR: Environment variable {var} is not set", file=sys.stderr)
        sys.exit(1)
    return val

NEXTCLOUD_URL = get_env("NEXTCLOUD_URL")
NEXTCLOUD_USER = get_env("NEXTCLOUD_USER")
NEXTCLOUD_PASSWORD = get_env("NEXTCLOUD_PASSWORD")

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} /path/to/project_root", file=sys.stderr)
    sys.exit(1)

ROOT_DIR = sys.argv[1]
if not os.path.isdir(ROOT_DIR):
    print(f"ERROR: {ROOT_DIR} is not a directory", file=sys.stderr)
    sys.exit(1)

# Helper: convert local path to Nextcloud path (as in project_link rule)
def local_to_nc_path(local_path):
    abs_path = os.path.abspath(local_path)
    if "/nextcloud2/" in abs_path:
        # Replace /mnt/extusb1/nextcloud2/ with /DragenExt/
        return "/DragenExt/" + abs_path.split("/nextcloud2/", 1)[1]
    else:
        # Fallback: use absolute path
        return abs_path

# Helper: create or fetch share link for a file
def get_share_link(nc_path, max_retries=5):
    import re
    import time
    encoded_path = urllib.parse.quote(nc_path, safe="/")
    # First, try GET to see if a share already exists
    get_cmd = [
        "curl", "-s", "-w", "\nHTTP_CODE:%{http_code}",
        "-X", "GET",
        "-u", f"{NEXTCLOUD_USER}:{NEXTCLOUD_PASSWORD}",
        "-H", "OCS-APIRequest: true",
        f"{NEXTCLOUD_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares?path={encoded_path}&reshares=true"
    ]
    result = subprocess.run(get_cmd, capture_output=True, text=True, timeout=30)
    stdout_lines = result.stdout.split('\n')
    for line in stdout_lines:
        if line.startswith('HTTP_CODE:'):
            stdout_lines.remove(line)
            break
    share_xml = '\n'.join(stdout_lines)
    match = re.search(r'<url>(.*?)</url>', share_xml)
    if match:
        link = match.group(1)
        if verify_link_exists(link):
            return link

    # If no existing link, try to create one with exponential backoff
    for attempt in range(1, max_retries + 1):
        wait_time = 3 * (2 ** (attempt - 1))
        post_cmd = [
            "curl", "-s", "-w", "\nHTTP_CODE:%{http_code}",
            "-X", "POST",
            "-u", f"{NEXTCLOUD_USER}:{NEXTCLOUD_PASSWORD}",
            "-H", "OCS-APIRequest: true",
            "-d", f"path={nc_path}",
            "-d", "shareType=3",
            f"{NEXTCLOUD_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares"
        ]
        result = subprocess.run(post_cmd, capture_output=True, text=True, timeout=30)
        stdout_lines = result.stdout.split('\n')
        for line in stdout_lines:
            if line.startswith('HTTP_CODE:'):
                stdout_lines.remove(line)
                break
        share_xml = '\n'.join(stdout_lines)
        match = re.search(r'<url>(.*?)</url>', share_xml)
        if match:
            link = match.group(1)
            if verify_link_exists(link):
                return link
        if attempt < max_retries:
            time.sleep(wait_time)
    return None

# Helper: verify that a Nextcloud share link exists (simple HEAD request)
def verify_link_exists(link):
    if not link:
        return False
    try:
        result = subprocess.run([
            "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-I", link
        ], capture_output=True, text=True, timeout=15)
        return result.stdout.strip().startswith("2") or result.stdout.strip().startswith("3")
    except Exception:
        return False

def main():
    file_links = {}
    for dirpath, _, filenames in os.walk(ROOT_DIR):
        for fname in filenames:
            if fname.endswith('.fastq.gz'):
                local_path = os.path.join(dirpath, fname)
                nc_path = local_to_nc_path(local_path)
                print(f"Processing: {local_path}", file=sys.stderr)
                link = get_share_link(nc_path)
                if link:
                    file_links[local_path] = link
                else:
                    print(f"  ERROR: Could not get share link for {local_path}", file=sys.stderr)
    yaml.dump(file_links, sys.stdout, default_flow_style=False)

if __name__ == "__main__":
    main()
