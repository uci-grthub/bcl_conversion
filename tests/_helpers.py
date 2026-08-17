"""Shared plumbing for the test suite.

The pipeline's helpers live in a Snakemake include file (src/workflow_defs.smk)
and inside rule bodies in the Snakefile, neither of which is importable. Rather
than duplicating that logic here — which would let a test keep passing after the
real code changed — these loaders extract the shipped source and exec it.
"""
import os
import sys
import textwrap

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")

if os.path.join(REPO, "src") not in sys.path:
    sys.path.insert(0, os.path.join(REPO, "src"))

# The barcode-free prefix shared by every delivered artifact of one sample.
FIXTURE_MAP = os.path.join(FIXTURES, "renaming_map_lane5.csv")
FIXTURE_CONFIG_ID = "lane5"
FIXTURE_RUN = "xR106"
FIXTURE_DUAL_PROJECT = "AcmeC_WGS_8plex"
FIXTURE_SINGLE_PROJECT = "SoloS_Amplicon_2plex"
FIXTURE_DELIVERED_DIR = "AcmeL_0626I-49_xR106_L5_G1"
FIXTURE_ORDER_ID = "0626I-49"


def revcomp(seq):
    return str(seq).translate(str.maketrans("ATGCNatgcn", "TACGNtacgn"))[::-1]


def _exec_source(source, extra_globals=None):
    namespace = {"os": os, "sys": sys}
    namespace.update(extra_globals or {})
    exec(compile(source, "<pipeline-source>", "exec"), namespace)
    return namespace


def load_workflow_defs_helpers():
    """revcomp / RC_ORIENTATION_COLUMNS / apply_orientation_to_map from workflow_defs.smk.

    Only the leading helper block is taken; the rest of the file needs a live
    Snakemake workflow namespace.
    """
    import pandas as pd

    path = os.path.join(REPO, "src", "workflow_defs.smk")
    with open(path) as handle:
        source = handle.read()
    start = source.index("def revcomp(seq):")
    end = source.index("# Sanitize Masking strings for filenames")
    return _exec_source(source[start:end], {"pd": pd})


def load_snakefile_function(name, end_marker):
    """A module-level function defined in the Snakefile, by name.

    The Snakefile sees everything workflow_defs.smk defines via `include:`, so
    the whole helper namespace is injected rather than a hand-picked subset.
    """
    import pandas as pd

    with open(os.path.join(REPO, "Snakefile")) as handle:
        source = handle.read()
    start = source.index(f"def {name}(")
    globals_ = {"pd": pd}
    globals_.update(load_workflow_defs_helpers())
    namespace = _exec_source(source[start:source.index(end_marker, start)], globals_)
    return namespace[name]


def load_rule_body(rule_name, end_marker):
    """The `run:` body of a rule, dedented and ready to exec with stub globals.

    Lets a test drive the shipped rule code without standing up a workflow.
    """
    with open(os.path.join(REPO, "Snakefile")) as handle:
        source = handle.read()
    start = source.index(f"rule {rule_name}:")
    rule_source = source[start:source.index(end_marker, start)]
    body_start = rule_source.index("    run:") + len("    run:\n")
    return textwrap.dedent(rule_source[body_start:])


class Stub:
    """Stand-in for Snakemake's input/output/wildcards namespaces."""

    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)


def live_run_lanes():
    """Lanes of the run checked out here that have a renaming map, or [].

    The suite's core checks use the committed fixture so they work anywhere;
    these extra lanes let the same invariants run against real data when a run
    directory happens to be present.
    """
    import glob

    lanes = []
    for path in sorted(glob.glob(os.path.join(REPO, "results", "lane*", "renaming_map_lane*.csv"))):
        if path.endswith("_effective.csv"):
            continue
        config_id = os.path.basename(os.path.dirname(path))
        decision = os.path.join(REPO, "logs", config_id, f"orientation_decision_{config_id}.json")
        lanes.append((config_id, path, decision))
    return lanes
