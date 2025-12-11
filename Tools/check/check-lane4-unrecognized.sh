zcat Undetermined_S0_L004_R1_001.fastq.gz | grep 1:N > lane-4-raw-list.txt
cut -d':' -f10- lane-4-raw-list.txt > lane-4-bc-list.txt
sort lane-4-bc-list.txt |  uniq -c | sort -nr > lane-4-sort.txt
