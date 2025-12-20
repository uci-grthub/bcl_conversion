#!/usr/bin/evn python

import pandas as pd
import matplotlib.pyplot as plt

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
    ax.set_ylim(0, 0.5)
    ax.set_xlim(left=0)
    
    # Legend settings
    ax.legend(loc='upper right', frameon=False, prop={'family': 'serif', 'weight': 'bold'})
    ax.tick_params(direction='in')

# --- USER CONFIGURATION ---
r1_file = 'path/to/R1_fastqc/fastqc_data.txt'
r2_file = 'path/to/R2_fastqc/fastqc_data.txt'

try:
    # 1. Parse both files
    df_r1 = parse_fastqc_base_content(r1_file)
    df_r2 = parse_fastqc_base_content(r2_file)

    # 2. Setup Figure: 2 Rows, 1 Column
    # Increased height (12) to fit two plots vertically
    fig, axes = plt.subplots(2, 1, figsize=(10, 12)) 

    # 3. Plot Data (Top is Read 1, Bottom is Read 2)
    plot_composition(axes[0], df_r1, "Base Composition (READ 1)")
    plot_composition(axes[1], df_r2, "Base Composition (READ 2)")
    
    # Add X-label only to the bottom plot to reduce clutter
    axes[1].set_xlabel("Sequence Position", fontsize=12, fontweight='bold', fontname='serif')

    # 4. Final Layout Adjustment
    plt.tight_layout()
    plt.show()
    # plt.savefig("base_composition_vertical.png", dpi=300)

except FileNotFoundError:
    print("Error: Could not find one or more fastqc_data.txt files.")
except Exception as e:
    print(f"An error occurred: {e}")