import pandas as pd
import os
from io import StringIO

def read_sample_sheet(sheet_path):
    if not os.path.exists(sheet_path):
        print(f"File not found: {sheet_path}")
        return None
    
    with open(sheet_path, 'r') as f:
        lines = f.readlines()
    
    header_row_idx = -1
    for i, line in enumerate(lines):
        if line.strip().startswith("[BCLConvert_Data]") or line.strip().startswith("[Data]"):
            print(f"Found section at index {i}")
            header_row_idx = i + 1
            break
            
    if header_row_idx == -1:
        print("Section not found")
        return None
        
    print(f"Header row index: {header_row_idx}")
    print(f"Header line: {lines[header_row_idx]}")
    
    data_str = "".join(lines[header_row_idx:])
    try:
        df = pd.read_csv(StringIO(data_str))
        print("Columns:", df.columns)
        return df
    except Exception as e:
        print(f"Error: {e}")
        return None

sheet_path = "src/SampleSheet_lane1_R1-151_I1-0_I2-6_R2-151.csv"
read_sample_sheet(sheet_path)
