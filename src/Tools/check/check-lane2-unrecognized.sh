zcat Undetermined_S0_L002_R1_001.fastq.gz | grep 1:N > lane-2-raw-list.txt
cut -d':' -f10- lane-2-raw-list.txt > lane-2-bc-list.txt
sort lane-2-bc-list.txt |  uniq -c | sort -nr > lane-2-sort.txt
