#!/usr/bin/perl
use strict;

##########################################################################################

my $run_id="R342";
my $lane_id="L1";
my $sample_id="Plate 1";
my $input_fastq="R342-L1-Sequences.txt";
my $stats_exe="/home/sequser/Facility/Tools/analyze_single_reads.pl";
my $max_mismatch="1";

##########################################################################################

my @BARCODES= qw( AAGTAAGC AATATACC ACCGCAGC ACGAATCC ACGGTCTC AGACCGCC AGCAAGGC ATAGGCGC
ATTAGTTC CAAGAGGC CAGCTCGC CCTACGCC CTATGATC CTCGATTC GCATTGCC TCAGAACC TCGCCTGC TGATTCTC
AACTAACGC AACTCGGTC AAGAGATTC AAGTTCGGC AATAACTCC AATACTCTC AATTGCATC ACCGTTAGC AGACCAGTC
ATAAGCCTC ATATCTGCC ATGAATAGC ATGATGGCC CAGCTTCGC CCTGAAGGC CCTTCCTCC CGATCATGC CGATTGATC
CGCAGGAGC CTTCTATGC TCGAGCTGC TGCGACGTC TTAGGTACC TTCAGGTTC AACCATGGAC ACCAGGCCGC
ACCATATATC ACGAGCGTAC ACTGCATCTC AGAACTAGTC AGACGGTTCC AGAGAATTGC AGCCGCAGTC AGGCTGGCGC
AGGTAGAGTC ATATAGCAGC ATGGTCCTAC CAGTTGACGC CCAAGCCGGC CCTGGAACGC CGCCAAGGCC CTATATGCTC
CTCGCCGATC GCCGTAGGTC GCGTCCAGGC TCCGTCGAAC TGAACCTTCC TTGGACGAGC AGACGTTAGGC CAACCTTAAGC
CCGCCTATGGC CGCAGAGACGC CGCCTGATAGC CGTTATAACGC CTCCGTTATGC CTTGGCATTGC GATGCTGACGC
GATGGAATAGC GCCTAGTAAGC GCGGTTACTGC GGATAAGAGGC GGTTCCAATGC TGGCTGAACGC AATTGGAATTC
ACTCCTAGGTC ATAAGAAGGTC CATGGCAACTC CTCATAGATTC CTCGCGCAGTC CTTACCATCTC GATCGTAGTTC
GCAGGTCAGTC GCCTGGAAGTC GGATTGCAGTC GGCCGGTATTC GTTCATATATC TCGCCGTAGTC TCTCTTCATTC );
my $num_BARCODES=$#BARCODES+1;

##########################################################################################

if(! -f "$input_fastq"){
  print "Could not find input fastq file\n"; exit 1; }
if(! -f "$stats_exe"){
  print "Could not find stats script\n"; exit 1; }
if(($max_mismatch ne "0")&&($max_mismatch ne "1")){
  print "Max mismatch value can only be 0 or 1\n"; exit 1; }

##########################################################################################

my $num_BC=0;   my $num_CAN=0;    my $num_NT=5;
my %BC_index;   my %CAN_index;    my @NT_seq=("A","C","G","T","N");
my @BC_seq;     my @CAN_seq;      my $min_BC_len=100000;
my @BC_len;     my @CAN_len;      my $max_BC_len=0;
my @BC_out;     my @CAN_BC_id;
my @BC_fhd;     my @CAN_BC_ind;

##########################################################################################

print "\n"; foreach my $bc_seq (@BARCODES){ if($bc_seq!~/^[ACGT]+$/){
    print "Inconsistent barcode sequence: $bc_seq\n"; exit 1; }
  my $bc_index=$num_BC; my $bc_len=length($bc_seq); my $primer=$num_BC+1;
  while(length($primer)!=length($num_BARCODES)){ $primer="0$primer"; }
  my $bc_out="$run_id-$lane_id-P$primer-$bc_seq-Sequences.txt";
  local *FILE; open(FILE,">$bc_out");
  my $num_ALT=0; my %ALT_index; my @ALT; my @SEQ=split("",$bc_seq);
  for(my $pos=0;$pos<$bc_len;$pos++){ foreach my $nt (@NT_seq){
      my $alt_seq=""; for(my $i=0;$i<$bc_len;$i++){ if($i!=$pos){
          $alt_seq.="$SEQ[$i]"; } else{ $alt_seq.="$nt"; } }
      if($ALT_index{"$alt_seq"} eq ""){ $ALT[$num_ALT]="$alt_seq";
        $ALT_index{"$alt_seq"}="$num_ALT"; $num_ALT++; } } }
  if($BC_index{"$bc_seq"} ne ""){ print "Duplicated barcode: $bc_seq\n"; exit 1; }
  $BC_index{"$bc_seq"}="$bc_index"; $BC_seq[$bc_index]="$bc_seq";
  $BC_len[$bc_index]="$bc_len"; $BC_out[$bc_index]="$bc_out";
  $BC_fhd[$bc_index]=*FILE; $num_BC++; my @FINAL;
  if($max_mismatch eq "0"){ push(@FINAL,"$bc_seq"); }
  else{ foreach my $seq (@ALT){ push(@FINAL,"$seq"); } }
  for(my $ind=0;$ind<=$#FINAL;$ind++){ my $can_index=$num_CAN;
    my $BC_id="$bc_seq"; my $BC_ind="$bc_index"; my $seq=$FINAL[$ind];
    my $len=length("$seq"); for(my $i=0;$i<$num_CAN;$i++){ my $can_seq=$CAN_seq[$i];
      if($can_seq eq "$seq"){ print "Conflicting barcodes for $bc_seq/$can_seq/$seq\n"; exit 1; }
      if($can_seq=~/^$seq/){ print "  Possible conflict: $bc_seq/$can_seq\n"; }
      if($seq=~/^$can_seq/){ print "  Possible conflict: $bc_seq/$can_seq\n"; } }
    if($CAN_index{"$seq"} ne ""){ print "Conflicting barcodes for $bc_seq/$seq\n"; exit 1; }
    $CAN_index{"$seq"}="$can_index"; $CAN_seq[$can_index]="$seq";
    $CAN_len[$can_index]="$len"; $CAN_BC_id[$can_index]="$BC_id";
    $CAN_BC_ind[$can_index]="$BC_ind"; $num_CAN++; } }

##########################################################################################

print "\n  BC DATASET:\n\n"; for(my $i=0;$i<$num_BC;$i++){
  if($BC_len[$i]<$min_BC_len){ $min_BC_len="$BC_len[$i]"; }
  if($BC_len[$i]>$max_BC_len){ $max_BC_len="$BC_len[$i]"; }
  print "    $i\t".$BC_index{"$BC_seq[$i]"}."\t$BC_seq[$i]\t$BC_len[$i]\t$BC_out[$i]\n"; }
print "\n  CAN DATASET:\n\n"; for(my $i=0;$i<$num_CAN;$i++){
  if($CAN_len[$i]<$min_BC_len){ $min_BC_len="$CAN_len[$i]"; }
  if($CAN_len[$i]>$max_BC_len){ $max_BC_len="$CAN_len[$i]"; }
  print "    $i\t".$CAN_index{"$CAN_seq[$i]"}."\t$CAN_seq[$i]\t$CAN_len[$i]\t";
  print "$CAN_BC_id[$i]\t$CAN_BC_ind[$i]\n"; }
print "\n  MIN_LEN = $min_BC_len\n  MAX_LEN = $max_BC_len\n\n";
my $trash_file="$run_id-$lane_id-PrNotRecog-Sequences.txt"; open(TRASH,">$trash_file");

##########################################################################################

my $num_input_reads=0;
my $num_demultiplexed=0;
my $num_perfect_match=0;
my $num_1_mismatch=0;
my $num_prnotrecognized=0;

##########################################################################################

open(IN,"$input_fastq"); print "  NOW DEMULTIPLEXING INPUT FASTQ FILE...\n\n";
while(my $header=<IN>){ my $seq=<IN>; my $third=<IN>; my $quals=<IN>;
  chomp($header); chomp($seq); chomp($third); chomp($quals);
  if($seq!~/^[ACGTN]+$/){ print "Inconsistent fastq file format\n"; exit 1; }
  my $detected_can_seq=""; my $detected_can_len=""; my $detected_can_ind="";
  my $detected_bc_seq="";  my $detected_bc_len="";  my $detected_bc_ind="";
  my $has_mismatch=""; for(my $bc_len=$max_BC_len;$bc_len>=$min_BC_len;$bc_len--){
    my $read_bc=substr($seq,0,$bc_len); my $can_index=$CAN_index{"$read_bc"};
    if($can_index ne ""){ if($detected_bc_seq eq ""){ $detected_can_seq="$read_bc";
        $detected_can_len="$bc_len"; $detected_can_ind="$can_index";
        $detected_bc_seq="$CAN_BC_id[$can_index]"; $detected_bc_len="$bc_len";
        $detected_bc_ind="$CAN_BC_ind[$can_index]";
        if($detected_can_seq eq $detected_bc_seq){ $has_mismatch="0"; }
        else{ $has_mismatch="1"; } }
      elsif(($has_mismatch eq "1")&&($BC_index{"$read_bc"} ne "")){
        $detected_can_seq="$read_bc"; $detected_can_len="$bc_len";
        $detected_can_ind="$can_index"; $detected_bc_seq="$CAN_BC_id[$can_index]";
        $detected_bc_len="$bc_len"; $detected_bc_ind="$CAN_BC_ind[$can_index]";
        if($detected_can_seq ne $detected_bc_seq){ print "Code flow mistake\n"; exit 1; }
        $has_mismatch="0"; }
      elsif(($has_mismatch eq "1")&&($BC_index{"$read_bc"} eq "")){
        if(!($detected_can_len>length($read_bc))){ print "Check case 1\n"; exit 1; } }
      elsif(($has_mismatch eq "0")&&($BC_index{"$read_bc"} ne "")){
        print "  ABNORMAL CASE, SHOULD NEVER BE POSSIBLE\n"; exit 1; }
      elsif(($has_mismatch eq "0")&&($BC_index{"$read_bc"} eq "")){}
      else{ print "  ABNORMAL TEST CASE, SHOULD NEVER BE REACHED\n"; exit 1; } } }
  $num_input_reads++; if($detected_can_seq eq ""){
    $num_prnotrecognized++; print TRASH "$header\n$seq\n$third\n$quals\n"; }
  else{ $num_demultiplexed++; if($has_mismatch){ $num_1_mismatch++; }
    else{ $num_perfect_match++; } my $fh=$BC_fhd[$detected_bc_ind];
    if(substr($header,-1) ne "0"){ print "Check header: $header\n"; exit 1; }
    print $fh substr($header,0,-1)."$detected_can_seq\n";
    print $fh substr($seq,$detected_can_len)."\n$third\n";
    print $fh substr($quals,$detected_can_len)."\n"; }
  if(($num_input_reads%1000000)==0){
    print "    Demultiplexed $num_input_reads sequences...\n"; } }
close(IN); print "\n";

##########################################################################################

my $pc_demultiplexed=sprintf("%.2f",($num_demultiplexed/$num_input_reads)*100);
my $pc_perfect_match=sprintf("%.2f",($num_perfect_match/$num_demultiplexed)*100);
my $pc_1_mismatch=sprintf("%.2f",($num_1_mismatch/$num_demultiplexed)*100);
my $pc_prnotrecognized=sprintf("%.2f",($num_prnotrecognized/$num_input_reads)*100);
print "  INPUT READS : $num_input_reads\n\n";
print "    DEMULTIPLEXED  : $num_demultiplexed ($pc_demultiplexed%)\n\n";
print "      PERFECT MATCH   : $num_perfect_match ($pc_perfect_match%)\n";
print "      1 NT MISMATCH   : $num_1_mismatch ($pc_1_mismatch%)\n\n";
print "    NOT RECOGNIZED : $num_prnotrecognized ($pc_prnotrecognized%)\n\n";

##########################################################################################

print "  NOW CHECKING & FINALIZING OUTPUT FILES...\n\n";
my $check_num_reads=0; for(my $bc_index=0;$bc_index<$num_BC;$bc_index++){
  my $bc_seq=$BC_seq[$bc_index]; my $bc_len=$BC_len[$bc_index];
  my $bc_out=$BC_out[$bc_index]; my $bc_fhd=$BC_fhd[$bc_index];
  my $remaining_len=100-$bc_len; close($bc_fhd); `chmod 770 $bc_out`;
  print "    $bc_out [CHECKS]\n"; open(IN,"$bc_out");
  while(my $l1=<IN>){ my $l2=<IN>; my $l3=<IN>; my $l4=<IN>;
    chomp($l1); chomp($l2); chomp($l3); chomp($l4); $check_num_reads++;
    my $head=substr($l1,-($bc_len+1)); my $bc=substr($head,1);
    if($head!~/^:[ACGTN]{$bc_len}$/){ print "Check headers 1\n"; exit 1; }
    my $can_index=$CAN_index{"$bc"}; if($can_index eq ""){ print "Check headers 2\n"; exit 1; }
    if($CAN_BC_id[$can_index] ne "$bc_seq"){ print "Check headers 3\n"; exit 1; }
    if($CAN_BC_ind[$can_index] ne "$bc_index"){ print "Check headers 4\n"; exit 1; }
    if(length($l2)!=$remaining_len){ print "Sequence length\n"; exit 1; }
    if(length($l4)!=$remaining_len){ print "PHRED Scores Length\n"; exit 1; } }
  close(IN); print "    $bc_out  [STATS]\n"; my @FEATS=split("-",$bc_out);
  if($FEATS[$#FEATS] ne "Sequences.txt"){ print "Prefix check failed\n"; exit 1; }
  pop(@FEATS); my $prefix=join("-",@FEATS);
  `$stats_exe $bc_out $prefix \"$sample_id\"; chmod 770 $prefix*`;
  print "    $bc_out   [GZIP]\n"; `gzip $bc_out; chmod 770 $bc_out.gz`; }
close(TRASH); `chmod 770 $trash_file`;
print "    $trash_file [CHECKS]\n"; open(IN,"$trash_file");
while(my $l=<IN>){ $l=<IN>; chomp($l); if(length($l)!=100){
    print "Length Sequence\n"; exit 1; } $l=<IN>; $l=<IN>; chomp($l);
  if(length($l)!=100){ print "Length PHRED Scores\n"; exit 1; } }
close(IN); print "    $trash_file  [STATS]\n";
`$stats_exe $trash_file $run_id-$lane_id-PrNotRecog \"$sample_id\"`;
`chmod 770 $run_id-$lane_id-PrNotRecog*`; print "    $trash_file   [GZIP]\n";
`gzip $trash_file; chmod 770 $trash_file.gz`; print "\n";

##########################################################################################

