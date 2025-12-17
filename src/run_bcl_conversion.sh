#!/bin/bash
dragen --bcl-conversion-only true \
	--bcl-input-directory data \
	--output-directory output \
	--force \
	--bcl-sampleproject-subdirectories true \
	--sample-sheet src/SampleSheet.csv \
	--strict-mode false
