#Filter a list of barcodes

input
while IFS= read -r line
do
  echo "$line"
done < "$input"
