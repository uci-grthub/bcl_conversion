import pandas as pd
import os
import yaml

with open("snakemake_config.yaml", "r") as f:
    config = yaml.safe_load(f)

excel_path = config.get("metadata")
print(f"Reading {excel_path}")

try:
    df = pd.read_excel(excel_path, sheet_name="Summary", header=2)
    print("Columns:", df.columns.tolist())
    print(df.head())
except Exception as e:
    print(f"Error: {e}")
