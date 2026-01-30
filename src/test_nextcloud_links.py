#!/usr/bin/env python3
"""
Script to test all Nextcloud share links in a YAML file.
Usage:
  python3 src/test_nextcloud_links.py nextcloud_links.yaml
"""
import sys
import yaml
import subprocess

def test_link(url):
    try:
        result = subprocess.run([
            "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-I", url
        ], capture_output=True, text=True, timeout=15)
        code = result.stdout.strip()
        return code, code.startswith("2") or code.startswith("3")
    except Exception as e:
        return str(e), False

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} nextcloud_links.yaml", file=sys.stderr)
        sys.exit(1)
    with open(sys.argv[1]) as f:
        links = yaml.safe_load(f)
    total = len(links)
    ok = 0
    for path, url in links.items():
        code, success = test_link(url)
        status = "OK" if success else f"FAIL ({code})"
        print(f"{status}\t{path}\t{url}")
        if success:
            ok += 1
    print(f"\n{ok}/{total} links are valid.")

if __name__ == "__main__":
    main()
