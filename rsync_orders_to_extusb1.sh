#!/bin/bash
# Rsync selected order ID output folders to /mnt/extusb1/nextcloud2/xR086
# Preserves lane subdirectory structure: xR086/lane*/SAMPLE_DIR/

set -euo pipefail

DEST="/mnt/extusb1/nextcloud2/xR086"

dirs=(
    "lane1/ChatS_0226I-08_xR086_L1_G1"
    "lane1/KolA_0126I-18_xR086_L1_G3"
    "lane2/VilaE_1225I-28_xR086_L2_G2"
    "lane2/ChenR_0326I-29_xR086_L2_G3"
    "lane2/MaraI_0226I-10_xR086_L2_G4"
    "lane3/FleiA_0326I-21_xR086_L3_G2"
    "lane3/WuM_0326I-26_xR086_L3_G3"
    "lane4/FelgP_0326I-25_xR086_L4_G4"
    "lane4/PlikM_0126I-45_xR086_L4_G1"
    "lane4/XingY_0326I-03_xR086_L4_G3"
    "lane5/FleiA_0326I-21_xR086_L5_G2"
    "lane6/CarrM_0326I-19_xR086_L6_G1"
    "lane7/FelgP_0326I-25_xR086_L7_G2"
    "lane8/FelgP_0326I-25_xR086_L8_G1"
)

SRC_BASE="$(dirname "$0")/output"

for rel in "${dirs[@]}"; do
    lane=$(dirname "$rel")
    mkdir -p "${DEST}/${lane}"
    echo "==> Syncing ${rel}"
    rsync -aW "${SRC_BASE}/${rel}/" "${DEST}/${rel}/"
done

echo "Done."
