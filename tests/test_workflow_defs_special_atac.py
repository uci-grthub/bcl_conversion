from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys


REPO_ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = REPO_ROOT / "src"
WORKFLOW_DEFS = SRC_DIR / "workflow_defs.smk"


def _load_workflow_defs_module():
    # workflow_defs.smk imports metadata_validation as a top-level module.
    sys.path.insert(0, str(SRC_DIR))
    try:
        loader = SourceFileLoader("workflow_defs_test_module", str(WORKFLOW_DEFS))
        return loader.load_module()
    finally:
        if sys.path and sys.path[0] == str(SRC_DIR):
            sys.path.pop(0)


def test_special_atac_name_matching_variants():
    mod = _load_workflow_defs_module()

    true_cases = [
        "BD_Rhapsody_ATACseq",
        "bd rhapsody atacseq",
        "10xMultiomeATACseq",
        "10x Multiome ATACseq",
        "10x_multiome_atacseq",
    ]
    false_cases = [
        "10xMultiomeGeneExpression",
        "ATACseq",
        "",
        None,
    ]

    for name in true_cases:
        assert mod.is_special_atac_project_or_sheet(name), f"Expected True for {name!r}"

    for name in false_cases:
        assert not mod.is_special_atac_project_or_sheet(name), f"Expected False for {name!r}"


def test_10xmultiome_atac_still_classifies_as_parse_or_10x():
    mod = _load_workflow_defs_module()
    assert mod.is_parse_or_10x("10xMultiomeATACseq")
