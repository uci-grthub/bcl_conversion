zcat Undetermined_S0_L008_R1_001.fastq.gz | grep 1:N > lane-8-raw-list.txt
cut -d':' -f10- lane-8-raw-list.txt > lane-8-bc-list.txt
sort lane-8-bc-list.txt |  uniq -c | sort -nr > lane-8-sort.txt
