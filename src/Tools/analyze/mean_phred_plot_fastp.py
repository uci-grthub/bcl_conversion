#!/usr/bin/env python

import argparse
import json
import pandas as pd
import matplotlib.pyplot as plt

"""
Usage:
    python3 mean_phred_plot_fastp.py input_file [second_file] [--out OUT.png] [--ylim MIN MAX]

Examples:
    # Single fastp JSON (paired):
    python3 mean_phred_plot_fastp.py sample_fastp.json --out mean_phred.png

    # Two files (FastQC or separate fastp):
    python3 mean_phred_plot_fastp.py sample_R1_fastp.json sample_R2_fastp.json --out mean_phred.png
    python3 mean_phred_plot_fastp.py sample_R1_fastqc/fastqc_data.txt sample_R2_fastqc/fastqc_data.txt

The script accepts either FastQC `fastqc_data.txt` files or fastp JSON reports
and will auto-detect the format. Use `--out` to save the plot, otherwise it will
be shown interactively.
"""


def parse_fastqc_quality(file_path):
    """
    Parses the 'Per base sequence quality' module from a fastqc_data.txt file.
    Returns a DataFrame with 'Position' and 'Mean_Phred' columns.
    """
    data = []
    in_module = False

    with open(file_path, 'r') as f:
        for line in f:
            line = line.strip()
            # Start of the relevant module
            if line.startswith('>>Per base sequence quality'):
                in_module = True
                continue
            # End of the module
            if line.startswith('>>END_MODULE'):
                in_module = False

            # If we are in the module, extract data (skip the header line starting with #)
            if in_module and not line.startswith('#'):
                parts = line.split('\t')
                # FastQC columns: Base, Mean, Median, Lower Quartile, Upper Quartile, 10th, 90th
                # We need Base (col 0) and Mean (col 1)

                # Handle base ranges (e.g., "10-14") by taking the midpoint for plotting
                base_val = parts[0]
                if '-' in base_val:
                    start, end = map(int, base_val.split('-'))
                    x_pos = (start + end) / 2
                else:
                    x_pos = int(base_val)

                mean_score = float(parts[1])
                data.append((x_pos, mean_score))

    df = pd.DataFrame(data, columns=['Position', 'Mean_Phred'])
    return df


def parse_fastp_quality_json(file_path):
    """Parse mean PHRED per position from a fastp JSON report.

    This function searches for quality curves in standard fastp JSON
    (read1_before_filtering -> quality_curves -> mean) or legacy formats.

    Returns either a DataFrame or a dict {'read1': df1, 'read2': df2}.
    """
    with open(file_path, 'r') as fh:
        j = json.load(fh)

    # 1. Try standard fastp JSON structure (read1_before_filtering, etc.)
    if 'read1_before_filtering' in j or 'summary' in j:
        out = {}
        
        def _extract_quality(read_key):
            if read_key not in j:
                return None
            
            section = j[read_key]
            if 'quality_curves' not in section:
                return None
            
            curves = section['quality_curves']
            if 'mean' not in curves:
                return None
            
            means = curves['mean']
            if not means:
                return pd.DataFrame()

            data = {
                'Position': range(1, len(means) + 1),
                'Mean_Phred': means
            }
            return pd.DataFrame(data)

        df1 = _extract_quality('read1_before_filtering')
        if df1 is not None:
            out['read1'] = df1
            
        df2 = _extract_quality('read2_before_filtering')
        if df2 is not None:
            out['read2'] = df2
            
        if out:
            return out

    # potential keys to try
    candidates = [
        'per_base_sequence_quality',
        'per_base_quality',
        'per_base_sequence_stats',
        'per_cycle_quality',
        'per_cycle_quality_score',
    ]

    found = None
    for k in candidates:
        if k in j:
            found = j[k]
            break

    # If not found, try keys that contain 'per' and 'quality'
    if found is None:
        for k, v in j.items():
            if isinstance(k, str) and 'per' in k.lower() and 'quality' in k.lower():
                found = v
                break

    if found is None:
        raise ValueError(f"No per-base quality information found in {file_path}")

    def _records_to_df(content_list):
        rows = []
        for rec in content_list:
            # rec may have 'position' or 'base' and 'mean' or 'average'
            pos = rec.get('position') or rec.get('base') or rec.get('cycle')
            if isinstance(pos, str) and '-' in pos:
                s, e = pos.split('-')
                try:
                    pos = (int(s) + int(e)) / 2
                except Exception:
                    pass
            try:
                pos = float(pos)
            except Exception:
                pass

            # detect mean field name
            mean_keys = ['mean', 'average', 'mean_quality', 'mean_score']
            mean_val = None
            for mk in mean_keys:
                if mk in rec:
                    mean_val = rec[mk]
                    break
            if mean_val is None:
                # try keys with 'mean' in name
                for k in rec.keys():
                    if 'mean' in k.lower() or 'average' in k.lower():
                        mean_val = rec[k]
                        break

            if mean_val is None:
                # fallback: try 'value' or first numeric field
                for k, v in rec.items():
                    if k in ('position', 'base', 'cycle'):
                        continue
                    try:
                        mean_val = float(v)
                        break
                    except Exception:
                        continue

            try:
                mean_val = float(mean_val)
            except Exception:
                mean_val = 0.0

            rows.append({'Position': pos, 'Mean_Phred': mean_val})
        return pd.DataFrame(rows)

    # If found is a dict, expect keys like 'read1'/'read2'
    if isinstance(found, dict):
        out = {}
        for k, v in found.items():
            if isinstance(v, list):
                out[k] = _records_to_df(v)
            else:
                out[k] = pd.DataFrame()
        return out

    if isinstance(found, list):
        return _records_to_df(found)

    raise ValueError('Unrecognized fastp per-base quality format')


def _load_quality(file_path):
    """Attempt to load per-base mean PHRED from FastQC text or fastp JSON."""
    # try FastQC first
    try:
        df = parse_fastqc_quality(file_path)
        if not df.empty:
            return df
    except Exception:
        pass

    # try fastp JSON
    try:
        parsed = parse_fastp_quality_json(file_path)
        if isinstance(parsed, dict):
            # prefer read1 if present, else first non-empty
            if 'read1' in parsed and not parsed['read1'].empty:
                return parsed['read1']
            for v in parsed.values():
                if isinstance(v, pd.DataFrame) and not v.empty:
                    return v
            # no useful data
            raise ValueError('fastp JSON parsed but no per-read data found')
        elif isinstance(parsed, pd.DataFrame):
            return parsed
    except Exception as e:
        raise

def main():
    parser = argparse.ArgumentParser(description='Plot mean PHRED per position from FastQC or fastp reports')
    parser.add_argument('files', nargs='+', help='Input file(s). Either one fastp JSON (paired) or two files (R1 R2)')
    parser.add_argument('--out', '-o', help='Output PNG path (if not provided, the plot will be shown)')
    parser.add_argument('--ylim', nargs=2, type=float, metavar=('MIN', 'MAX'), help='Y-axis limits for PHRED scores')
    parser.add_argument('--title', '-t', help='Sample name to display in plot title')
    args = parser.parse_args()

    df_r1 = None
    df_r2 = None

    try:
        if len(args.files) == 1:
            file_path = args.files[0]
            # Try parsing as fastp JSON first
            try:
                parsed = parse_fastp_quality_json(file_path)
                if isinstance(parsed, dict):
                    df_r1 = parsed.get('read1')
                    df_r2 = parsed.get('read2')
                    
                    if df_r1 is None and df_r2 is None and len(parsed) > 0:
                        keys = sorted(list(parsed.keys()))
                        df_r1 = parsed[keys[0]]
                        if len(keys) > 1:
                            df_r2 = parsed[keys[1]]
                elif isinstance(parsed, pd.DataFrame):
                    df_r1 = parsed
            except Exception:
                # Fallback to FastQC/generic loader
                df_r1 = _load_quality(file_path)
        
        elif len(args.files) >= 2:
            df_r1 = _load_quality(args.files[0])
            df_r2 = _load_quality(args.files[1])

        if df_r1 is None and df_r2 is None:
             print("Error: Could not extract data from input files.")
             return

        plt.figure(figsize=(10, 6))
        
        if df_r1 is not None:
            plt.plot(df_r1['Position'], df_r1['Mean_Phred'], label='READ 1', color='#3385ff', linewidth=2)
        
        if df_r2 is not None:
            plt.plot(df_r2['Position'], df_r2['Mean_Phred'], label='READ 2', color='#e63939', linewidth=2)

        title = args.title if args.title else "Sequencing Data Quality"
        plt.title(title, fontsize=14, fontweight='bold', fontname='serif')
        plt.xlabel("Sequence Position", fontsize=12, fontweight='bold', fontname='serif')
        plt.ylabel("Mean PHRED Quality Score", fontsize=12, fontweight='bold', fontname='serif')
        plt.grid(True, linestyle='--', alpha=0.7)

        if args.ylim:
            plt.ylim(args.ylim[0], args.ylim[1])
        else:
            plt.ylim(25, 41)

        plt.legend(loc='upper right', frameon=False, prop={'family': 'serif', 'weight': 'bold'})
        plt.tick_params(direction='in')

        plt.tight_layout()
        if args.out:
            plt.savefig(args.out, dpi=300)
            print(f"Saved plot to {args.out}")
        else:
            plt.show()

    except FileNotFoundError:
        print("Error: Could not find one or more input files. Please check the paths.")
    except Exception as e:
        print(f"An error occurred: {e}")


if __name__ == '__main__':
    main()