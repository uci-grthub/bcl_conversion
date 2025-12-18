import pandas as pd
import os
import yaml

with open("snakemake_config.yaml", "r") as f:
    config = yaml.safe_load(f)

excel_path = config.get("metadata")
print(f"Reading {excel_path}")

try:
    df = pd.read_excel(excel_path, sheet_name="Summary")
    print("Columns:", df.columns.tolist())
    
    if 'Lane' in df.columns and 'Masking' in df.columns:
        groups = df[['Lane', 'Masking']].drop_duplicates().values.tolist()
        print("Groups (Lane, Masking):")
        for g in groups:
            print(g)
            
except Exception as e:
    print(f"Error: {e}")
