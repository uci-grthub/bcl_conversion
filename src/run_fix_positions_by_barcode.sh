#!/bin/bash
set -e

# List of config_ids based on output/ and results/ renaming_map files
CONFIG_IDS=(
  lane1_R1-26_I1-10_I2-10_R2-90
  lane2_R1-26_I1-10_I2-10_R2-90
  lane2_R1-28_I1-10_I2-10_R2-90
  lane3_R1-151_I1-6_I2-0_R2-151
  lane3_R1-151_I1-8_I2-8_R2-151
  lane3_R1-51_I1-8_I2-0_R2-71
  lane4_R1-151_I1-8_I2-8_R2-151
  lane4_R1-51_I1-8_I2-0_R2-71
  lane5_R1-151_I1-8_I2-8_R2-151
  lane5_R1-51_I1-8_I2-0_R2-71
  lane6_R1-51_I1-8_I2-0_R2-71
  lane7_R1-151_I1-6_I2-0_R2-151
  lane7_R1-151_I1-8_I2-8_R2-151
  lane8_R1-151_I1-8_I2-8_R2-151
  lane8_R1-51_I1-8_I2-0_R2-71
)

for config_id in "${CONFIG_IDS[@]}"; do
  echo "Running fix_positions_by_barcode for $config_id"
  python3 src/fix_positions_by_barcode.py "$config_id" "output/$config_id" "results/renaming_map_$config_id.csv"
done
