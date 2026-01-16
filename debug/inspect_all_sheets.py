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
    xl = pd.ExcelFile(excel_path)
    print("Sheet names:", xl.sheet_names)
    
    for sheet in xl.sheet_names:
        if sheet == "Summary": continue
        print(f"\n--- Inspecting sheet: {sheet} ---")
        # Read raw
        df = pd.read_excel(excel_path, sheet_name=sheet, header=None)
        
        # Find where data starts
        start_row = -1
        header_row = -1
        
        # Look for "Lane" or "Sample_ID" or "Sample_Name"
        for i, row in df.iterrows():
            row_values = [str(x).strip() for x in row.values]
            if "Lane" in row_values and ("Sample_ID" in row_values or "Sample Name" in row_values or "Sample_Name" in row_values):
                header_row = i
                print(f"Found header at row {i}: {row_values}")
                break
            if "[Data]" in row_values:
                print(f"Found [Data] at row {i}")
                # Usually header is next
                
        if header_row != -1:
            df_data = pd.read_excel(excel_path, sheet_name=sheet, header=header_row)
            print("Columns:", df_data.columns.tolist())
            print(df_data.head())
        else:
            print("Could not find header row with Lane and Sample info.")
            print("First 10 rows:")
            print(df.head(10))

except Exception as e:
    print(f"Error: {e}")
