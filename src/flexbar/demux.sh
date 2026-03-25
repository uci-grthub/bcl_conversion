#!usr/bin/bash
SAMPLE_INFO=$1
RAW_DATA=$2
DEAL_WITH_BARCODE="./deal_with_barcode.py"
ADAPTER="./adapter.3.fa"

python3 $DEAL_WITH_BARCODE $SAMPLE_INFO $SAMPLE_INFO.fa
flexbar --barcodes $SAMPLE_INFO.fa -r $RAW_DATA --barcode-trim-end LTAIL --barcode-error-rate 0 --adapters $ADAPTER --adapter-error-rate 0.1 --adapter-min-overlap 1 --adapter-trim-end RIGHT --zip-output GZ --barcode-unassigned --min-read-length 15 --umi-tags 
