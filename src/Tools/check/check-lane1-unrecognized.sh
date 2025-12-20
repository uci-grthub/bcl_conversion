zcat Undetermined_S0_L001_R1_001.fastq.gz | grep 1:N > lane-1-raw-list.txt
cut -d':' -f10- lane-1-raw-list.txt > lane-1-bc-list.txt
sort lane-1-bc-list.txt |  uniq -c | sort -nr > lane-1-sort.txt
