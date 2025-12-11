zcat Undetermined_S0_L007_R1_001.fastq.gz | grep 1:N > lane-7-raw-list.txt
cut -d':' -f10- lane-7-raw-list.txt > lane-7-bc-list.txt
sort lane-7-bc-list.txt |  uniq -c | sort -nr > lane-7-sort.txt
