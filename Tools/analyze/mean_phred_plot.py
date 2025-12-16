#!/usr/bin/env python

import pandas as pd
import matplotlib.pyplot as plt

def parse_fastqc_quality(file_path):
    """
    Parses the 'Per base sequence quality' module from a fastqc_data.txt file.
    Returns a DataFrame with 'Base' and 'Mean' columns.
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

# --- USER CONFIGURATION: Update these paths to your actual fastqc_data.txt files ---
r1_file = 'path/to/sample_R1_fastqc/fastqc_data.txt'
r2_file = 'path/to/sample_R2_fastqc/fastqc_data.txt'

# Load the data
try:
    df_r1 = parse_fastqc_quality(r1_file)
    df_r2 = parse_fastqc_quality(r2_file)

    # --- PLOTTING ---
    plt.figure(figsize=(10, 6))

    # Plot R1 (Blue)
    plt.plot(df_r1['Position'], df_r1['Mean_Phred'], 
             label='READ 1', color='#3385ff', linewidth=2)

    # Plot R2 (Red)
    plt.plot(df_r2['Position'], df_r2['Mean_Phred'], 
             label='READ 2', color='#e63939', linewidth=2)

    # Styling to match your image
    plt.title("Sequencing Data Quality", fontsize=14, fontweight='bold', fontname='serif')
    plt.xlabel("Sequence Position", fontsize=12, fontweight='bold', fontname='serif')
    plt.ylabel("Mean PHRED Quality Score", fontsize=12, fontweight='bold', fontname='serif')

    # Grid styling
    plt.grid(True, linestyle='--', alpha=0.7)

    # Axis limits (adjust as needed based on your data)
    plt.ylim(35, 41)  # Matching the specific zoom of your example image
    # plt.ylim(0, 42) # Standard full scale

    # Legend
    plt.legend(loc='upper right', frameon=False, prop={'family': 'serif', 'weight': 'bold'})

    # Ticks styling
    plt.tick_params(direction='in')
    
    # Save or Show
    plt.tight_layout()
    plt.show()
    # plt.savefig("quality_overlay.png", dpi=300)

except FileNotFoundError:
    print("Error: Could not find the fastqc_data.txt files. Please check the paths.")
except Exception as e:
    print(f"An error occurred: {e}")