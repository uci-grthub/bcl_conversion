#!/usr/bin/perl
use strict;

####################################################################################################

if(($#ARGV < 3) || ($#ARGV > 4) ){ print "\n  USAGE : ./postprocess_hiseq_lane.pl ";
  print "sample_sheet num_reads lane_number library_name [optional start S number, blank is S1]\n\n"; exit 1; }
my $start_s_id=1;
if($#ARGV==4){ print "Using Start S number of $ARGV[4] \n"; $start_s_id=$ARGV[4]}
my $sample_sheet=$ARGV[0]; my $num_reads=$ARGV[1]; my $lane=$ARGV[2]; my $name=$ARGV[3]; 
if(! -f "$sample_sheet"){ print "Cannot find sample sheet\n"; exit 1; }
if(($num_reads!=1)&&($num_reads!=2)){ print "Num reads must be 1 or 2\n"; exit 1; }
if(!(($lane>=1)&&($lane<=8))){ print "Lane must between 1 and 8\n"; exit 1; }
my $process_single="/home/sequser/Facility/Tools/analyze_single_reads_centos7_test-gzip.pl";
my $process_paired="/home/sequser/Facility/Tools/analyze_paired_reads_centos7_test-gzip.pl";
print "Start id S number =$start_s_id\n";

####################################################################################################

# Load Sample Information
my $is_barcoded=0; my $num_barcodes=0; my @barcodes; my @prefixes; open(IN,"$sample_sheet");
if((my $l=<IN>)!~"Data"){ print "Incorrect file header"; exit 1; }
if((my $l=<IN>)!~"Project,Lane,SampleID"){ print "Incorrect file header"; exit 1; }
my $generic_sample_id="1"; my @generic;
while(my $l=<IN>){
  chomp($l); my @d=split(",",$l);
  if($d[1]==$lane){
    if($d[4] eq ""){ my $prefix=$d[2];
      if(($is_barcoded!=0)||($num_barcodes!=0)){
        print "Inconsistent sample sheet\n"; exit 1; }
      if($prefix!~/^R[0-9]{3}-L$lane$/){
        print "Inconsistent sample prefix.\n"; exit 1; }
      push(@prefixes,"$prefix"); }
    else{ $is_barcoded=1; $num_barcodes++;
      if($d[5] eq ""){ push(@barcodes,"$d[4]"); }
      else{ push(@barcodes,"$d[4]-$d[5]"); }
      push(@prefixes,"$d[2]");
      push(@generic,"$generic_sample_id"); } }
      print "in check $d[2] \n";
  $generic_sample_id++; } close(IN);

####################################################################################################

# Process Lane (Case Not Multiplexed)
if($is_barcoded==0)
{
  print "Samples not barcoded : write corresponding code\n"; exit 1;
}

####################################################################################################

# Process Lane (Case Multiplexed)
else{
  print "\n  Found $num_barcodes Barcodes For Lane $lane ($name)\n\n";
  for(my $i=0;$i<$num_barcodes;$i++){
    my $barcode=$barcodes[$i]; my $prefix=$prefixes[$i]; my $genid=$generic[$i] +  $start_s_id - 1;
    print "  Processing Library \"$name\" - Barcode $barcode ($prefix)... genid=${genid} \n";
    my $file_in_R1="${prefix}_S${genid}_L00${lane}_R1_001.fastq.gz";
    my $file_in_R2="${prefix}_S${genid}_L00${lane}_R2_001.fastq.gz";
    if(! -f "$file_in_R1"){ print "Cannot find fastq file 1 $file_in_R1 \n"; exit 1; }
    if(($num_reads==2)&&(! -f "$file_in_R2")){ print "Cannot find fastq file\n"; exit 1; }
    
    ################################################################################################
    
    if($num_reads==1){
      my $file_out="${prefix}-${barcode}-Sequences.txt.gz";
      `mv $file_in_R1 $file_out`;
      `$process_single $file_out ${prefix}-${barcode} \"$name\"`;
      `chmod 770 $prefix*`; `chmod 770 $file_out`;
      print "case A $file_out ";
      `md5sum $file_out >> md5sum_lane$lane.txt`; }
    
    ################################################################################################
    
    elsif($num_reads==2){
      my $file_out_R1="${prefix}-${barcode}-READ1-Sequences.txt.gz";
      my $file_out_R2="${prefix}-${barcode}-READ2-Sequences.txt.gz";
      `mv $file_in_R1 $file_out_R1`;
      `mv $file_in_R2 $file_out_R2`;
      `$process_paired $file_out_R1 $file_out_R2 ${prefix}-${barcode} \"$name\"`;
      `chmod 770 $prefix*`; `chmod 770 $file_out_R1`;
      `chmod 770 $file_out_R2`;
      `md5sum $file_out_R1 >> md5sum_lane$lane.txt`;
      `md5sum $file_out_R2 >> md5sum_lane$lane.txt`; } }
  
  ##################################################################################################
  
  my @d=split("-",$prefixes[0]); my $prefix="$d[0]-$d[1]";
  if($prefix!~/^(4R|mR|nR|xR|R)[0-9]{3}-L$lane$/){ print "Cannot process trash\n"; exit 1; }
  $prefix="$prefix-PrNotRecog";
  print "  Processing Library \"$name\" - Barcode Not Recognized ($prefix)...\n";
  my $file_in_R1="Undetermined_S0_L00${lane}_R1_001.fastq.gz";
  my $file_in_R2="Undetermined_S0_L00${lane}_R2_001.fastq.gz";
  if(! -f "$file_in_R1"){ print "Cannot find fastq file\n"; exit 1; }
  if(($num_reads==2)&&(! -f "$file_in_R2")){ print "Cannot find fastq file\n"; exit 1; }
  
  ##################################################################################################
  
  if($num_reads==1){
    my $file_out="${prefix}-Sequences.txt.gz";
    `mv $file_in_R1 $file_out`;
    `$process_single $file_out ${prefix} \"$name\"`;
    `chmod 770 $prefix*`; `chmod 770 $file_out`;
    print "case B $file_out ";
    `md5sum $file_out >> md5sum_lane$lane.txt`; }
  
  ##################################################################################################
  
  elsif($num_reads==2){
    my $file_out_R1="${prefix}-READ1-Sequences.txt.gz";
    my $file_out_R2="${prefix}-READ2-Sequences.txt.gz";
    `mv $file_in_R1 $file_out_R1`;
    `mv $file_in_R2 $file_out_R2`;
    `$process_paired $file_out_R1 $file_out_R2 ${prefix} \"$name\"`;
    `chmod 770 $prefix*`; 
	`chmod 770 $file_out_R1`;
    `chmod 770 $file_out_R2`;
    `md5sum $file_out_R1 >> md5sum_lane$lane.txt`;
    `md5sum $file_out_R2 >> md5sum_lane$lane.txt`; }
}

####################################################################################################

