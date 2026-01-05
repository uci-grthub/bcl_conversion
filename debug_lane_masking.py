import pandas as pd
import os
import yaml

with open("snakemake_config.yaml", "r") as f:
    config = yaml.safe_load(f)

excel_path = config.get("metadata")
print(f"Reading {excel_path}")

if not os.path.exists(excel_path):
    print("File does not exist")
    exit(1)

try:
    # Read without header first to see structure
    df_raw = pd.read_excel(excel_path, sheet_name="Summary", header=None)
    print("First 5 rows of raw Summary sheet:")
    print(df_raw.head())

    # Try reading with default header
    df = pd.read_excel(excel_path, sheet_name="Summary")
    print("\nColumns with default header:")
    print(df.columns.tolist())
    print(df.head())
    
    if 'Lane' in df.columns and 'Masking' in df.columns:
        print("\nLane and Masking columns found.")
        print(df[['Lane', 'Masking']].head())
    else:
        print("\nLane or Masking column NOT found.")

except Exception as e:
    print(f"Error: {e}")
