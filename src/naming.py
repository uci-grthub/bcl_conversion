"""DRAGEN-safe names shared by the Snakefile and the standalone scripts.

DRAGEN Sample_ID and Sample_Project values may only contain A-Z a-z 0-9 - _.
Every place that turns a workbook sample or project name into a name or a
lookup key uses these helpers, so the Summary sheet, the generated sample
sheets and the post-hoc scripts always agree on the same string.
"""

import re


def dragen_safe_name(s):
    """Runs of characters outside A-Z a-z 0-9 - _ become one '_'; no '__', no edge '_'."""
    s = re.sub(r'[^a-zA-Z0-9\-_]+', '_', str(s))
    return re.sub(r'_+', '_', s).strip('_')


def normalize_project_name(value):
    """Project name as used for Sample_Project, DRAGEN's project folder and lookup keys.

    A missing value comes back as 'nan', which callers already filter.
    """
    return dragen_safe_name(str(value).strip())
