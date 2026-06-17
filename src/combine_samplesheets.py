#!/usr/bin/env python3
"""Merge validated per-lane BCL Convert SampleSheets into one all-lane sheet.

Each input is a validated per-lane sheet (results/{config_id}/SampleSheet_{config_id}_validated.csv)
with a [Header], [BCLConvert_Settings] and [BCLConvert_Data] section. The data
rows already carry their own Lane, OverrideCycles and per-sample
BarcodeMismatchesIndex1/2, so combining is a concatenation of the data sections
plus a union of the (otherwise run-global) settings block.

Usage:
    combine_samplesheets.py OUTPUT.csv INPUT1.csv INPUT2.csv ...
"""
import sys
import io
import pandas as pd


def parse_sheet(path):
    """Return (settings_dict, data_dataframe) for one validated sheet."""
    settings = {}
    data_lines = []
    section = None
    with open(path) as f:
        for raw in f:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                section = stripped.strip("[]")
                continue
            if not stripped:
                continue
            if section == "BCLConvert_Settings":
                key, _, val = line.partition(",")
                settings[key.strip()] = val.strip()
            elif section == "BCLConvert_Data":
                data_lines.append(line)
    if not data_lines:
        raise ValueError(f"No [BCLConvert_Data] rows found in {path}")
    df = pd.read_csv(io.StringIO("\n".join(data_lines)), dtype=str).fillna("")
    return settings, df


def union_settings(settings_list):
    """Union the per-lane settings blocks into one run-global block.

    - CreateFastqForIndexReads / TrimUMI: enable (1 / 0) if ANY lane requested it.
      Both are no-ops for lanes whose OverrideCycles lack the relevant segment.
    - Other keys must agree across the lanes that define them.
    """
    out = {}
    # CreateFastqForIndexReads: 1 if any lane sets 1.
    cfir = ["1" for s in settings_list if s.get("CreateFastqForIndexReads") == "1"]
    out["CreateFastqForIndexReads"] = "1" if cfir else "0"
    # TrimUMI: 0 if any lane sets 0 (disables UMI trimming for UMI lanes; no-op otherwise).
    if any(s.get("TrimUMI") == "0" for s in settings_list):
        out["TrimUMI"] = "0"
    # Remaining keys: require agreement among lanes that define them.
    handled = {"CreateFastqForIndexReads", "TrimUMI"}
    for key in ["MinimumTrimmedReadLength", "MaskShortReads", "FastqCompressionFormat"]:
        vals = {s[key] for s in settings_list if key in s}
        if not vals:
            continue
        if len(vals) > 1:
            raise ValueError(f"Conflicting values for {key} across lanes: {sorted(vals)}")
        out[key] = next(iter(vals))
        handled.add(key)
    # Pass through any other settings, requiring agreement.
    for s in settings_list:
        for key, val in s.items():
            if key in handled:
                continue
            if key in out and out[key] != val:
                raise ValueError(f"Conflicting values for {key} across lanes: {out[key]!r} vs {val!r}")
            out[key] = val
    return out


def main():
    if len(sys.argv) < 3:
        sys.exit("Usage: combine_samplesheets.py OUTPUT.csv INPUT1.csv [INPUT2.csv ...]")
    out_path, in_paths = sys.argv[1], sys.argv[2:]

    settings_list, frames = [], []
    for p in in_paths:
        settings, df = parse_sheet(p)
        settings_list.append(settings)
        frames.append(df)

    settings = union_settings(settings_list)

    # Union columns across lanes (e.g. some lanes lack BarcodeMismatchesIndex2),
    # preserving the canonical column order. Missing per-sample cells stay blank,
    # which DRAGEN ignores.
    canonical = ["Lane", "Sample_ID", "Sample_Name", "index", "index2",
                 "Sample_Project", "OverrideCycles",
                 "BarcodeMismatchesIndex1", "BarcodeMismatchesIndex2"]
    all_cols = [c for c in canonical if any(c in f.columns for f in frames)]
    for f in frames:
        for c in all_cols:
            if c not in f.columns:
                f[c] = ""
    combined = pd.concat([f[all_cols] for f in frames], ignore_index=True).fillna("")
    # Sort by lane so the sheet reads in lane order (does not affect demux).
    combined["__lane_sort__"] = pd.to_numeric(combined["Lane"], errors="coerce").fillna(0)
    combined = combined.sort_values("__lane_sort__", kind="stable").drop(columns="__lane_sort__")

    # Emit settings in a stable, DRAGEN-friendly order.
    settings_order = ["CreateFastqForIndexReads", "TrimUMI",
                      "MinimumTrimmedReadLength", "MaskShortReads",
                      "FastqCompressionFormat"]
    ordered_keys = [k for k in settings_order if k in settings]
    ordered_keys += [k for k in settings if k not in ordered_keys]

    import os
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w") as f:
        f.write("[Header]\n")
        f.write("FileFormatVersion,2\n")
        f.write("\n")
        f.write("[BCLConvert_Settings]\n")
        for k in ordered_keys:
            f.write(f"{k},{settings[k]}\n")
        f.write("\n")
        f.write("[BCLConvert_Data]\n")
        combined.to_csv(f, index=False)

    print(f"Wrote combined sheet: {out_path} ({len(combined)} rows, {len(in_paths)} lanes)")


if __name__ == "__main__":
    main()
