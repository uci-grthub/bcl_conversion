zcat Undetermined_S0_L006_R1_001.fastq.gz | grep 1:N > lane-6-raw-list.txt
cut -d':' -f10- lane-6-raw-list.txt > lane-6-bc-list.txt
sort lane-6-bc-list.txt |  uniq -c | sort -nr > lane-6-sort.txt
