import pandas as pd
import os
import yaml

with open("snakemake_config.yaml", "r") as f:
    config = yaml.safe_load(f)

excel_path = config.get("metadata")
print(f"Reading {excel_path}")

try:
    df = pd.read_excel(excel_path, sheet_name="Barcode List", header=1)
    print("Columns:", df.columns.tolist())
    print(df.head())
    
    if 'Lane' in df.columns:
        print("Lane column found.")
        print(df['Lane'].unique())
        
except Exception as e:
    print(f"Error: {e}")
