#!/bin/bash

# Navigate to your FASTQ output directory
# Usage: ./rename_rhapsody.sh /path/to/fastqs

TARGET_DIR=${1:-.}

echo "Starting renaming process in: $TARGET_DIR"

# 1. Rename the 72bp Genomic Read from R2 to R3
# Do this recursively so files inside per-sample subdirectories are handled
find "$TARGET_DIR" -type f -name '*_R2_001.fastq.gz' -print0 | while IFS= read -r -d '' f; do
    new="${f%_R2_001.fastq.gz}_R3_001.fastq.gz"
    mv "$f" "$new"
    echo "Renamed Genomic Read: $f -> $new"
done

# 2. Rename the 60bp Barcode/UMI Read from I2 to R2 (recursively)
find "$TARGET_DIR" -type f -name '*_I2_001.fastq.gz' -print0 | while IFS= read -r -d '' f; do
    new="${f%_I2_001.fastq.gz}_R2_001.fastq.gz"
    mv "$f" "$new"
    echo "Renamed Barcode Read: $f -> $new"
done

# 3. Optional: Remove the 8bp Sample Index file (I1) 
# Uncomment the line below if you want to clean up the I1 files
# rm "$TARGET_DIR"/*_I1_001.fastq.gz

echo "Renaming complete. Files are now in R1, R2, R3 format for BD Rhapsody."