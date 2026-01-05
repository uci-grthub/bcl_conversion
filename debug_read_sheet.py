import pandas as pd
import os

sheet_path = "src/SampleSheet_lane1_R1-151_I1-0_I2-6_R2-151.csv"
df = pd.read_csv(sheet_path, header=None)
print(df.head(15))
