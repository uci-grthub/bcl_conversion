zcat Undetermined_S0_L005_R1_001.fastq.gz | grep 1:N > lane-5-raw-list.txt
cut -d':' -f10- lane-5-raw-list.txt > lane-5-bc-list.txt
sort lane-5-bc-list.txt |  uniq -c | sort -nr > lane-5-sort.txt
