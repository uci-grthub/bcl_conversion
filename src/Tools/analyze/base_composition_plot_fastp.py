#!/usr/bin/env python

import argparse
import json
import pandas as pd
import matplotlib.pyplot as plt

"""
Usage:
 - Provide one fastp JSON file (paired) or two files (R1 R2) as arguments.
 - The script will auto-detect FastQC text format or fastp JSON per-base
     reports (keys like `per_base_sequence_content` or similar).

Run:
 python3 base_composition_plot_fastp.py input_file [second_file] [--out out.png]

Examples:
 # Single fastp JSON (paired):
 python3 base_composition_plot_fastp.py /path/to/sample_fastp.json --out base_comp.png

 # Two files (FastQC or separate fastp):
 python3 base_composition_plot_fastp.py /path/to/R1_fastp.json /path/to/R2_fastp.json --out base_comp.png
 python3 base_composition_plot_fastp.py /path/to/R1_fastqc/fastqc_data.txt /path/to/R2_fastqc/fastqc_data.txt
"""


def parse_fastqc_base_content(file_path):
    """Parses 'Per base sequence content' from fastqc_data.txt."""
    data = []
    in_module = False
    headers = []

    with open(file_path, 'r') as f:
        for line in f:
            line = line.strip()
            # Start of module
            if line.startswith('>>Per base sequence content'):
                in_module = True
                continue
            # End of module
            if line.startswith('>>END_MODULE'):
                break

            if in_module:
                if line.startswith('#'):
                    headers = line[1:].split('\t')
                    continue

                parts = line.split('\t')
                row_dict = {}
                base_val = parts[0]

                # Handle ranges like 10-14 by taking the midpoint
                if '-' in base_val:
                    start, end = map(int, base_val.split('-'))
                    row_dict['Position'] = (start + end) / 2
                else:
                    row_dict['Position'] = int(base_val)

                # Convert percentages (0-100) to frequency (0-1.0)
                for i, col_name in enumerate(headers[1:], start=1):
                    row_dict[col_name] = float(parts[i]) / 100.0
                data.append(row_dict)

    return pd.DataFrame(data)


def parse_fastp_json(file_path):
    """Parse fastp JSON report and extract per-base sequence content.

    The fastp JSON format varies by version. This function attempts to handle
    common shapes:
      - Standard fastp: 'read1_before_filtering' -> 'content_curves'
      - top-level key 'per_base_sequence_content' containing a list of records
      - dict containing separate 'read1'/'read2' arrays

    Returns a DataFrame with columns: Position, A, C, G, T, (optional N)
    """
    with open(file_path, 'r') as fh:
        j = json.load(fh)

    # 1. Try standard fastp JSON structure (read1_before_filtering, etc.)
    if 'read1_before_filtering' in j or 'summary' in j:
        out = {}
        
        def _extract_curves(read_key):
            if read_key not in j:
                return None
            
            section = j[read_key]
            if 'content_curves' not in section:
                return None
            
            curves = section['content_curves']
            # curves is like {'A': [v1, v2...], 'T': [...], ...}
            
            # Determine length from one of the lists
            length = 0
            for base in curves:
                length = len(curves[base])
                break
            
            if length == 0:
                return pd.DataFrame()

            data = {'Position': range(1, length + 1)}
            for base in ['A', 'C', 'G', 'T', 'N']:
                if base in curves:
                    data[base] = curves[base]
                else:
                    data[base] = [0.0] * length
            
            return pd.DataFrame(data)

        df1 = _extract_curves('read1_before_filtering')
        if df1 is not None:
            out['read1'] = df1
            
        df2 = _extract_curves('read2_before_filtering')
        if df2 is not None:
            out['read2'] = df2
            
        if out:
            return out

    # 2. Try 'per_base_sequence_content' key (original logic)
    key = 'per_base_sequence_content'
    if key in j:
        content = j[key]

        # If content is a dict with read1/read2, convert each list to a DataFrame
        def _records_to_df(content_list):
            rows = []
            for rec in content_list:
                pos = rec.get('position') or rec.get('base')
                if isinstance(pos, str) and '-' in pos:
                    s, e = pos.split('-')
                    try:
                        pos = (int(s) + int(e)) / 2
                    except ValueError:
                        pass
                try:
                    pos = float(pos)
                except Exception:
                    pass

                row = {'Position': pos}
                for nt in ('A', 'C', 'G', 'T', 'N'):
                    if nt in rec:
                        val = rec[nt]
                        if isinstance(val, str) and val.endswith('%'):
                            val = val.rstrip('%')
                        try:
                            vf = float(val)
                            if vf > 1.0:
                                vf = vf / 100.0
                            row[nt] = vf
                        except Exception:
                            row[nt] = 0.0
                    else:
                        row[nt] = 0.0
                rows.append(row)
            return pd.DataFrame(rows)

        if isinstance(content, dict):
            out = {}
            for k, v in content.items():
                if isinstance(v, list):
                    out[k] = _records_to_df(v)
                else:
                    # if it's already a structure, try to convert
                    out[k] = _records_to_df(v) if isinstance(v, list) else pd.DataFrame()
            return out

        # If content is a list of records for a single read
        if isinstance(content, list):
            return _records_to_df(content)

    raise ValueError(f"Could not find 'read1_before_filtering' or '{key}' in fastp JSON: {file_path}")

def plot_composition(ax, df, title):
    """Helper function to plot data onto a specific matplotlib axis."""
    # Plot Lines: A=Blue, C=Red, G=Yellow, T=Green
    if 'A' in df.columns:
        ax.plot(df['Position'], df['A'], label='A', color='#1E90FF', linewidth=2)
    if 'C' in df.columns:
        ax.plot(df['Position'], df['C'], label='C', color='#FF0000', linewidth=2)
    if 'G' in df.columns:
        ax.plot(df['Position'], df['G'], label='G', color='#FFD700', linewidth=2)
    if 'T' in df.columns:
        ax.plot(df['Position'], df['T'], label='T', color='#32CD32', linewidth=2)

    ax.set_title(title, fontsize=14, fontweight='bold', fontname='serif')
    ax.set_ylabel("Base Call Frequency", fontsize=12, fontweight='bold', fontname='serif')
    ax.grid(True, linestyle='--', alpha=0.7)
    ax.set_ylim(0, 1)
    ax.set_xlim(left=0)
    
    # Legend settings
    ax.legend(loc='upper right', frameon=False, prop={'family': 'serif', 'weight': 'bold'})
    ax.tick_params(direction='in')



def _load_base_df(file_path):
    """Load per-base composition from either fastqc_data.txt or fastp JSON."""
    # Try fastqc format first (text); if that fails, try fastp JSON
    try:
        df = parse_fastqc_base_content(file_path)
        if not df.empty:
            return df
    except Exception:
        pass

    # Try fastp JSON
    try:
        parsed = parse_fastp_json(file_path)
        # If parse_fastp_json returned a dict of DataFrames (e.g., {'read1': df1})
        if isinstance(parsed, dict):
            # prefer keys with 'read1' or 'read2', otherwise pick first
            if 'read1' in parsed and isinstance(parsed['read1'], pd.DataFrame):
                return parsed['read1']
            # else if only one key present, return its DataFrame
            for v in parsed.values():
                if isinstance(v, pd.DataFrame) and not v.empty:
                    return v
        elif isinstance(parsed, pd.DataFrame):
            return parsed
    except Exception as e:
        raise

def main():
    parser = argparse.ArgumentParser(description='Plot base composition from FastQC or fastp reports')
    parser.add_argument('files', nargs='+', help='Input file(s). Either one fastp JSON (paired) or two files (R1 R2)')
    parser.add_argument('--out', '-o', help='Output PNG path (if not provided, the plot will be shown)')
    args = parser.parse_args()

    df_r1 = None
    df_r2 = None

    try:
        if len(args.files) == 1:
            file_path = args.files[0]
            # Try parsing as fastp JSON first to see if we can get paired data
            try:
                parsed = parse_fastp_json(file_path)
                if isinstance(parsed, dict):
                    # fastp JSON usually has 'read1' and 'read2' keys under 'per_base_sequence_content'
                    df_r1 = parsed.get('read1')
                    df_r2 = parsed.get('read2')
                    
                    # If we didn't find explicit 'read1'/'read2' keys, but we have a dict,
                    # try to assign based on order or keys
                    if df_r1 is None and df_r2 is None and len(parsed) > 0:
                        keys = sorted(list(parsed.keys()))
                        df_r1 = parsed[keys[0]]
                        if len(keys) > 1:
                            df_r2 = parsed[keys[1]]
                elif isinstance(parsed, pd.DataFrame):
                    df_r1 = parsed
            except Exception:
                # If fastp parsing fails (e.g. it's a FastQC file), fall back to _load_base_df
                # which handles FastQC format
                df_r1 = _load_base_df(file_path)
        
        elif len(args.files) >= 2:
            df_r1 = _load_base_df(args.files[0])
            df_r2 = _load_base_df(args.files[1])

        if df_r1 is None and df_r2 is None:
             print("Error: Could not extract data from input files.")
             return

        # Determine layout based on whether we have one or two datasets
        if df_r2 is not None:
            fig, axes = plt.subplots(2, 1, figsize=(10, 12))
            plot_composition(axes[0], df_r1, "Base Composition (READ 1)")
            plot_composition(axes[1], df_r2, "Base Composition (READ 2)")
            axes[1].set_xlabel("Sequence Position", fontsize=12, fontweight='bold', fontname='serif')
        else:
            fig, ax = plt.subplots(1, 1, figsize=(10, 6))
            plot_composition(ax, df_r1, "Base Composition")
            ax.set_xlabel("Sequence Position", fontsize=12, fontweight='bold', fontname='serif')

        plt.tight_layout()

        if args.out:
            plt.savefig(args.out, dpi=300)
            print(f"Saved plot to {args.out}")
        else:
            plt.show()

    except FileNotFoundError:
        print("Error: Could not find one or more input files.")
    except Exception as e:
        print(f"An error occurred: {e}")


if __name__ == '__main__':
    main()