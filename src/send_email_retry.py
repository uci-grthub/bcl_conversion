#!/usr/bin/env python3
"""Wrapper to run the existing send_email.py with retries, backoff and a per-order lock.

Usage:
  python3 src/send_email_retry.py <send_script> <sender> <receiver> <subject> <html> <attachments> <cc> <order_id>

This script will attempt to call the `send_script` repeatedly on transient failures
and will serialize attempts for the same order_id using a file lock.
"""
import argparse
import subprocess
import sys
import time
import random
import fcntl
import os


def run_with_lock(lock_path, fn, *args, **kwargs):
    os.makedirs(os.path.dirname(lock_path), exist_ok=True)
    with open(lock_path, 'w') as lf:
        try:
            fcntl.flock(lf, fcntl.LOCK_EX)
            return fn(*args, **kwargs)
        finally:
            try:
                fcntl.flock(lf, fcntl.LOCK_UN)
            except Exception:
                pass


def is_retryable_output(text):
    if not text:
        return False
    # Common SMTP temporary error codes (421, 4xx) and Gmail-specific message
    if "421" in text:
        return True
    if "4.3.0" in text or "Temporary System Problem" in text:
        return True
    return False


def call_send(send_script, sender, receiver, subject, html, attachments, cc):
    cmd = [sys.executable, send_script, sender, receiver, subject, html, attachments, cc]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    out = (proc.stdout or "") + (proc.stderr or "")
    return proc.returncode, out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('send_script')
    parser.add_argument('sender')
    parser.add_argument('receiver')
    parser.add_argument('subject')
    parser.add_argument('html')
    parser.add_argument('attachments')
    parser.add_argument('cc')
    parser.add_argument('order_id')
    parser.add_argument('--max-retries', type=int, default=6)
    parser.add_argument('--base-sleep', type=float, default=5.0)
    parser.add_argument('--lock-dir', default='/tmp/send_email_locks')
    args = parser.parse_args()

    lock_path = os.path.join(args.lock_dir, f"order_{args.order_id}.lock")

    def attempt_send():
        tries = 0
        while tries < args.max_retries:
            tries += 1
            rc, out = call_send(args.send_script, args.sender, args.receiver, args.subject, args.html, args.attachments, args.cc)
            timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
            print(f"[{timestamp}] Attempt {tries}/{args.max_retries}, exit={rc}")
            if out:
                print(out)

            if rc == 0:
                print(f"Email sent successfully on attempt {tries}")
                return 0

            # If output indicates temporary SMTP issue, retry
            if is_retryable_output(out):
                backoff = args.base_sleep * (2 ** (tries - 1))
                # add jitter up to 20%
                jitter = backoff * 0.2 * (random.random() * 2 - 1)
                sleep_time = max(1.0, backoff + jitter)
                print(f"Transient error detected; sleeping {sleep_time:.1f}s before retrying...")
                time.sleep(sleep_time)
                continue

            # Non-retryable error: stop and return non-zero
            print("Non-retryable error or permanent failure; not retrying.")
            return rc if rc != 0 else 1

        print(f"Exceeded max retries ({args.max_retries}); giving up.")
        return 2

    # Acquire lock per order to serialize sends for the same order
    rc = run_with_lock(lock_path, attempt_send)
    sys.exit(rc)


if __name__ == '__main__':
    main()
