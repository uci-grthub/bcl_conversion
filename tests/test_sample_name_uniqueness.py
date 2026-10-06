"""filldown_and_make_unique_sample_names: _N suffixes are scoped to (Lane, Project).

DRAGEN only needs Sample_ID unique within a lane. A bulk project sequenced on two
lanes (xR121 MaccF_RNAseq_32plex on lanes 7 and 8) used to come out as name_1 in
one lane and name_2 in the other, so the customer saw two names per library.
"""
import pandas as pd

from _helpers import load_workflow_defs_function

filldown_and_make_unique_sample_names = load_workflow_defs_function(
    "filldown_and_make_unique_sample_names", "def generate_miseq_samplesheets(")


def _frame(rows):
    return pd.DataFrame(rows, columns=["Lane", "Project", "Sample_Name"])


def test_same_sample_on_two_lanes_keeps_one_name():
    df = _frame([
        (7, "MaccF_RNAseq_32plex", "NHP7_Hippo_S2"),
        (7, "MaccF_RNAseq_32plex", "NHP7_Cereb_S4"),
        (8, "MaccF_RNAseq_32plex", "NHP7_Hippo_S2"),
        (8, "MaccF_RNAseq_32plex", "NHP7_Cereb_S4"),
    ])
    out = filldown_and_make_unique_sample_names(df)
    assert out["Sample_Name"].tolist() == df["Sample_Name"].tolist()


def test_duplicate_within_one_lane_is_suffixed():
    df = _frame([
        (3, "AcmeC_WGS_8plex", "S1"),
        (3, "AcmeC_WGS_8plex", "S1"),
        (3, "AcmeC_WGS_8plex", "S2"),
        (4, "AcmeC_WGS_8plex", "S1"),
    ])
    out = filldown_and_make_unique_sample_names(df)
    assert out["Sample_Name"].tolist() == ["S1_1", "S1_2", "S2", "S1"]


def test_filled_down_names_in_one_lane_are_suffixed():
    df = _frame([
        (2, "AcmeC_WGS_8plex", "S1"),
        (2, "AcmeC_WGS_8plex", None),
    ])
    out = filldown_and_make_unique_sample_names(df)
    assert out["Sample_Name"].tolist() == ["S1_1", "S1_2"]


def test_10x_project_is_never_suffixed():
    df = _frame([
        (1, "KessK_10xFlexv2_Carina_4plex", "Carina_Flex1"),
        (1, "KessK_10xFlexv2_Carina_4plex", "Carina_Flex1"),
    ])
    out = filldown_and_make_unique_sample_names(df)
    assert out["Sample_Name"].tolist() == ["Carina_Flex1", "Carina_Flex1"]


def test_without_lane_column_falls_back_to_per_project():
    df = pd.DataFrame({"Project": ["AcmeC_WGS_8plex"] * 2, "Sample_Name": ["S1", "S1"]})
    out = filldown_and_make_unique_sample_names(df)
    assert out["Sample_Name"].tolist() == ["S1_1", "S1_2"]


sanitize_sample_name = load_workflow_defs_function(
    "sanitize_sample_name", "def filldown_and_make_unique_sample_names(",
    start_marker="from naming import")


def test_sanitized_name_has_no_repeated_underscores():
    """The xR121 MaccF names as submitted, line breaks and all."""
    assert (sanitize_sample_name("NHP7_13010671\n_Olfactory Bulb  &  Tract, S1")
            == "NHP7_13010671_Olfactory_Bulb_Tract_S1")
    assert sanitize_sample_name("NHP7_13010671\n_Hippo, S2    ") == "NHP7_13010671_Hippo_S2"
    assert sanitize_sample_name("a__b___c") == "a_b_c"


def test_sanitize_keeps_hyphens_and_trims_edge_underscores():
    assert sanitize_sample_name("_Amyg/Piriform_") == "Amyg_Piriform"
    assert sanitize_sample_name("Amyg-Piriform") == "Amyg-Piriform"


def test_sanitize_blank_or_symbol_only_falls_back_to_sample():
    assert sanitize_sample_name("") == "Sample"
    assert sanitize_sample_name(float("nan")) == "Sample"
    assert sanitize_sample_name("&&//") == "Sample"


normalize_project_name = load_workflow_defs_function(
    "normalize_project_name", "def filldown_and_make_unique_sample_names(",
    start_marker="from naming import")


def test_project_name_has_no_repeated_underscores():
    assert normalize_project_name("MaccF RNAseq, 32plex ") == "MaccF_RNAseq_32plex"
    assert normalize_project_name("KessK__10x3V4  GEX/Masrilab_4") == "KessK_10x3V4_GEX_Masrilab_4"


def test_clean_project_name_is_unchanged():
    """Names that were already safe keep their exact folder name."""
    assert normalize_project_name("BeieK_10xMultiome_GEX_072126") == "BeieK_10xMultiome_GEX_072126"
    assert normalize_project_name("Acme-C_WGS_8plex") == "Acme-C_WGS_8plex"
