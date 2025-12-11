zcat Undetermined_S0_L003_R1_001.fastq.gz | grep 1:N > lane-3-raw-list.txt
cut -d':' -f10- lane-3-raw-list.txt > lane-3-bc-list.txt
sort lane-3-bc-list.txt |  uniq -c | sort -nr > lane-3-sort.txt
