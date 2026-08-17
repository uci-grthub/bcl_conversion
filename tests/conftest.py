"""pytest configuration: make tests/ and src/ importable.

The suite also runs without pytest — see tests/run_tests.py.
"""
import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TESTS_DIR)

for path in (TESTS_DIR, os.path.join(REPO, "src")):
    if path not in sys.path:
        sys.path.insert(0, path)
