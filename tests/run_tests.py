#!/usr/bin/env python3
"""Run the test suite without pytest.

pytest is not in pixi.toml, so this runner exists to keep the suite executable
in the pipeline's own environment:

    pixi run python tests/run_tests.py            # everything
    pixi run python tests/run_tests.py backfill   # only matching files

The tests are written as plain pytest functions, so `pytest tests/` works
unchanged once pytest is available.
"""
import glob
import inspect
import os
import shutil
import sys
import tempfile
import traceback

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TESTS_DIR)
for _path in (TESTS_DIR, os.path.join(REPO, "src")):
    if _path not in sys.path:
        sys.path.insert(0, _path)


def discover(patterns):
    paths = sorted(glob.glob(os.path.join(TESTS_DIR, "test_*.py")))
    if patterns:
        paths = [p for p in paths if any(pat in os.path.basename(p) for pat in patterns)]
    return paths


def run_module(path, results):
    module_name = os.path.splitext(os.path.basename(path))[0]
    module = __import__(module_name)
    tests = [(name, obj) for name, obj in vars(module).items()
             if name.startswith("test_") and inspect.isfunction(obj)
             and obj.__module__ == module_name]
    tests.sort(key=lambda item: inspect.getsourcelines(item[1])[1])

    print(f"\n{module_name}")
    for name, func in tests:
        # Minimal stand-in for pytest's tmp_path fixture.
        needs_tmp = "tmp_path" in inspect.signature(func).parameters
        tmp_dir = tempfile.mkdtemp(prefix=f"{name}_") if needs_tmp else None
        original_cwd = os.getcwd()
        try:
            func(tmp_dir) if needs_tmp else func()
            print(f"  PASS  {name}")
            results["passed"] += 1
        except Exception:
            print(f"  FAIL  {name}")
            print(textwrap_indent(traceback.format_exc(), "        "))
            results["failed"].append(f"{module_name}::{name}")
        finally:
            os.chdir(original_cwd)
            if tmp_dir:
                shutil.rmtree(tmp_dir, ignore_errors=True)


def textwrap_indent(text, prefix):
    return "".join(prefix + line for line in text.splitlines(keepends=True))


def main():
    paths = discover(sys.argv[1:])
    if not paths:
        print("No test files matched.")
        return 1

    results = {"passed": 0, "failed": []}
    for path in paths:
        run_module(path, results)

    print(f"\n{results['passed']} passed, {len(results['failed'])} failed")
    for name in results["failed"]:
        print(f"  {name}")
    return 1 if results["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
