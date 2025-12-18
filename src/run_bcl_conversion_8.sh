#!/bin/bash
dragen --bcl-conversion-only true \
    --bcl-sampleproject-subdirectories true \
    --bcl-input-directory input \
    --output-directory output_8 \
    --force \
    --sample-sheet code/SampleSheetxR074-lane2-8-bc.csv \
    --strict-mode false
