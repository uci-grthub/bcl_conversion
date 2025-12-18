#!/bin/bash
dragen --bcl-conversion-only true \
    --bcl-sampleproject-subdirectories true \
    --bcl-input-directory input \
    --output-directory output \
    --force \
    --sample-sheet code/SampleSheetxR074-lane2-dual-bc.csv \
    --strict-mode false
