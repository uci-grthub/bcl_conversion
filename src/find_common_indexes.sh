#!/bin/bash

# Usage: ./find_common_indexes.sh Undetermined_S0_L001_R1_001.fastq.gz

FASTQ="$1"

if [[ ! -f "$FASTQ" ]]; then
    echo "File not found: $FASTQ"
    exit 1
fi

# Extract index from header lines, count, and sort
zcat "$FASTQ" | awk 'NR%4==1 {split($0, a, ":"); print a[length(a)]}' | sort | uniq -c | sort -nr | head

# Output: count index
