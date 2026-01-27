#!/bin/bash

# Navigate to your FASTQ output directory
# Usage: ./rename_rhapsody.sh /path/to/fastqs

TARGET_DIR=${1:-.}

echo "Starting renaming process in: $TARGET_DIR"

# 1. Rename the 72bp Genomic Read from R2 to R3 
# (We do this first so we don't overwrite it)
for f in "$TARGET_DIR"/*_R2_001.fastq.gz; do
    if [ -f "$f" ]; then
        mv "$f" "${f//_R2_001.fastq.gz/_R3_001.fastq.gz}"
        echo "Renamed Genomic Read: $f -> ..._R3_001.fastq.gz"
    fi
done

# 2. Rename the 60bp Barcode/UMI Read from I2 to R2
for f in "$TARGET_DIR"/*_I2_001.fastq.gz; do
    if [ -f "$f" ]; then
        mv "$f" "${f//_I2_001.fastq.gz/_R2_001.fastq.gz}"
        echo "Renamed Barcode Read: $f -> ..._R2_001.fastq.gz"
    fi
done

# 3. Optional: Remove the 8bp Sample Index file (I1) 
# Uncomment the line below if you want to clean up the I1 files
# rm "$TARGET_DIR"/*_I1_001.fastq.gz

echo "Renaming complete. Files are now in R1, R2, R3 format for BD Rhapsody."