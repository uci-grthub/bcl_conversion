USAGE : ./postprocess_hiseq_lane.pl sample_sheet num_reads lane_number library_name [optional start S number, blank is S1] [optional fastq directory, default output]

perl postprocess/postprocess_hiseq_lane_centos7_test_MiSeq.pl data/code/SampleSheet.csv 1 1 test data/output

perl postprocess/postprocess_hiseq_lane_centos7_test_gzip.pl data/code_novaseq_lane1/SamplesheetxR069-lane1-10x-v3-dual-bc-processed.csv 2 1 test data/output_novaseq_lane1

perl postprocess/postprocess_hiseq_lane_centos7_test_gzip.pl data/code_novaseq_lane1/SamplesheetxR069-lane1-10x-v3-dual-bc-processed.csv 2 1 test data/output_novaseq_lane1 --dryrun