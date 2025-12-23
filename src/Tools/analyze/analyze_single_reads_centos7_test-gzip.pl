#!/usr/bin/perl
use strict;
use POSIX qw(strftime);

##########################################################################################
#                                                                                        #
# Script  : analyze_single_reads.pl                                                      #
# Author  : Christophe Magnan                                                            #
# Updated : 2018/02/06                                                                   #
#                                                                                        #
# Update  : 2019/07/10                                                                   #
# changed if(($len>=4)&&($len<=10)&&($cand=~/^[ACGT]+$/)){                               #
# to if(($len>=4)&&($len<=12) to account for long MiSeq barcodes                         #
# by Yuzo Kanomata                                                                       #
#                                                                                        #
##########################################################################################

# Script Behaviour
my $verbose=0;                 # Display messages or not
my $write_raw_stats_pos=0;     # Report raw statistics per position
my $write_raw_stats_bin=0;     # Report raw statistics per bin
my $max_illumina_len=320;      # Max read length for Illumina sequences
my $min_pacbio_len=500;        # Min max read length for PacBio sequences
my $max_number_bins=400;       # Max number of bins to display on plots

##########################################################################################

# Script Inputs
my $script_usage="./analyze_single_reads.pl  fastq  prefix  [sample]";
if(($#ARGV!=1)&&($#ARGV!=2)){ print "\nUsage: $script_usage\n\n"; exit; }
log_msg("Starting analyze_single_reads.pl with args: @ARGV");
my $fastq=$ARGV[0]; my $prefix=$ARGV[1]; my $library="$prefix";
my $multiplex=0; my $barcode=""; if($#ARGV==2){ $library=$ARGV[2]; }
if($prefix=~"-"){ my @d=split("-",$prefix); foreach my $cand (@d){
my $len=length($cand); if(($len>=4)&&($len<=12)&&($cand=~/^[ACGT]+$/)){
$multiplex=1; if($barcode eq ""){ $barcode="$cand"; } else{ $barcode.="-$cand"; } }
if($cand eq "PrNotRecog"){ $multiplex=1; $barcode="Not Recognized"; } } }
if(! -f "$fastq"){ print "Input Fastq File Not Found.\n"; exit; }
my $gdfont_path="/usr/share/fonts/dejavu-sans-fonts:/usr/share/fonts/dejavu-serif-fonts:/usr/share/fonts/dejavu-sans-mono-fonts";
my $gdfont_export="export GDFONTPATH=$gdfont_path";
if($verbose){ print "\n  FASTQ FILE : $fastq\n  PREFIX OUT : $prefix\n  SAMPLE ";
print "ID  : $library\n  MULTIPLEX  : $multiplex\n  BARCODE    : $barcode\n\n"; }

##########################################################################################

# Script Outputs
my $raw_stats_pos_out="$prefix-RawStatsPerPos.tsv";
my $raw_stats_bin_out="$prefix-RawStatsPerBin.tsv";
my $basic_description="$prefix-SampleBasicInfo.txt";

##########################################################################################

# Variables for Statistics
my $num_POS=0; my @POS_ID; my @POS_NUMSQ; my @POS_CUMUL; my @POS_PHRED; my %POS_CALLS;
my $num_BIN=0; my @BIN_ID; my @BIN_NUMSQ; my @BIN_CUMUL; my @BIN_PHRED; my %BIN_CALLS;
my $BIN_len=1; my $num_reads=0; my $num_len=0; my $avg_len=0; my $min_len;
my $max_len; my $offset=33; my $sum_nocall=0; my @NTS=("A","C","G","T","N");
my %VALID; foreach my $nt (@NTS){ $VALID{"$nt"}=1; }

##########################################################################################
#                                                                                        #
#                                   FastQ File Analysis                                  #
#                                                                                        #
##########################################################################################

# Performing Statistics Per Position
if($verbose){ print "  Analyzing fastq file (long process)...\n"; }
log_msg("Analyzing fastq file: $fastq");
open(IN,"gunzip -c $fastq |"); while(my $l=<IN>){ if($l!~/^@/){
print "Input not in FastQ file format.\n"; exit; } $l=<IN>; chomp($l);
my @nts=split("",$l); my $len=$#nts+1; $POS_NUMSQ[$len-1]++;
for(my $i=0;$i<$len;$i++){ $POS_CUMUL[$i]++; $POS_CALLS{"$i-$nts[$i]"}++; }
$avg_len+=$len; $l=<IN>; $l=<IN>; chomp($l); my @phred=split("",$l);
if(($#phred+1)!=$len){ print "Scores length mismatch.\n"; exit; }
for(my $i=0;$i<$len;$i++){ $POS_PHRED[$i]+=(int(ord($phred[$i]))-$offset); }
$num_reads++; } close(IN); if($num_reads==0){ print "Empty FastQ File!\n"; exit; }
if($verbose){ print "  Done! $num_reads reads found in input.\n"; }
log_msg("Done analyzing fastq. Found $num_reads reads.");

##########################################################################################

# Finalizing Statistics Per Position
if($verbose){ print "  Finalizing stats per position...\n\n"; }
log_msg("Finalizing stats per position...");
for(my $i=0;$i<=$#POS_NUMSQ;$i++){ my $pos=$i+1; push(@POS_ID,"$pos");
if($POS_CUMUL[$i] eq ""){ print "Inconsistent cumul. counts.\n"; exit; }
if($POS_PHRED[$i] eq ""){ print "Inconsistent PHRED scores.\n"; exit; }
if($POS_NUMSQ[$i] ne ""){ if($min_len eq ""){ $min_len=$pos; } $max_len=$pos; $num_len++; }
else{ $POS_NUMSQ[$i]="0"; } foreach my $nt (@NTS){ if($POS_CALLS{"$i-$nt"} eq ""){
$POS_CALLS{"$i-$nt"}=0; } } $sum_nocall+=$POS_CALLS{"$i-N"}; } if($num_len==0){
print "Inconsistent number of read lengths.\n"; exit; } $num_POS=$max_len;
$avg_len=sprintf("%.2f",$avg_len/$num_reads); $num_reads=format_int($num_reads);

##########################################################################################
#                                                                                        #
#                                   CASE 1 (Illumina)                                    #
#                                                                                        #
#                Sequences have same length & length <= $max_illumina_len                #
#                           (read length distribution ignored)                           #
#                                                                                        #
##########################################################################################

# Reporting Statistics Per Position
if(($num_len==1)&&($num_POS<=$max_illumina_len)){
if($verbose){ print "  CASE 1 detected (Illumina)\n"; }
log_msg("CASE 1 detected (Illumina)");
if(($verbose)&&($write_raw_stats_pos)){ print "  Writing stats per position...\n"; }
log_msg("Writing stats per position to $raw_stats_pos_out");
open(OUT,">$raw_stats_pos_out"); print OUT "Position\tNum Reads\tCumulated\tPHRED\tA\tC\tG\tT\tN\n";
for(my $i=0;$i<=$#POS_NUMSQ;$i++){ $POS_PHRED[$i]=sprintf("%.2f",$POS_PHRED[$i]/$POS_CUMUL[$i]);
print OUT "$POS_ID[$i]\t$POS_NUMSQ[$i]\t$POS_CUMUL[$i]\t$POS_PHRED[$i]"; foreach my $nt (@NTS){
$POS_CALLS{"$i-$nt"}=sprintf("%.4f",$POS_CALLS{"$i-$nt"}/$POS_CUMUL[$i]);
print OUT "\t".$POS_CALLS{"$i-$nt"}; } print OUT "\n"; } close(OUT);
`chmod 770 $raw_stats_pos_out`; if($write_raw_stats_pos==0){ `rm -rf $raw_stats_pos_out`; }

##########################################################################################

# Reporting Basic Sample Description
if($verbose){ print "  Writing basic sample info...\n"; } open(OUT,">$basic_description");
log_msg("Writing basic sample info to $basic_description");
print OUT "Files   : $prefix-*\n"; if($multiplex){ print OUT "Library : $library\n";
print OUT "Barcode : $barcode\n"; } else{ print OUT "Sample  : $library\n"; }
print OUT "#Reads  : $num_reads\n#Cycles : $num_POS\n"; close(OUT); `chmod 770 $basic_description`;

##########################################################################################
#                                                                                        #
#                                    CASE 2 (PacBio)                                     #
#                                                                                        #
#            Sequences have different length & MAX length >= $min_pacbio_len             #
#                          (read length distribution generated)                          #
#                                                                                        #
##########################################################################################

# Reporting Statistics Per Position
elsif(($num_len>1)&&($num_POS>=$min_pacbio_len)){
if($verbose){ print "  CASE 2 detected (PacBio)\n"; }
log_msg("CASE 2 detected (PacBio)");
if(($verbose)&&($write_raw_stats_pos)){ print "  Writing stats per position...\n"; }
log_msg("Writing stats per position to $raw_stats_pos_out");
open(OUT,">$raw_stats_pos_out"); print OUT "Position\tNum Reads\tCumulated\tPHRED\tA\tC\tG\tT\tN\n";
for(my $i=0;$i<=$#POS_NUMSQ;$i++){ my $pos_phred=sprintf("%.2f",$POS_PHRED[$i]/$POS_CUMUL[$i]);
print OUT "$POS_ID[$i]\t$POS_NUMSQ[$i]\t$POS_CUMUL[$i]\t$pos_phred";
foreach my $nt (@NTS){ my $pos_call=sprintf("%.4f",$POS_CALLS{"$i-$nt"}/$POS_CUMUL[$i]);
print OUT "\t$pos_call"; } print OUT "\n"; } close(OUT); `chmod 770 $raw_stats_pos_out`;
if($write_raw_stats_pos==0){ `rm -rf $raw_stats_pos_out`; }

##########################################################################################

# Reporting Basic Sample Description
if($verbose){ print "  Writing basic sample info...\n"; } open(OUT,">$basic_description");
log_msg("Writing basic sample info to $basic_description");
print OUT "Files   : $prefix-*\nSample  : $library\n#Reads  : $num_reads\nMin Len : $min_len\n";
print OUT "Max Len : $max_len\nAvg Len : $avg_len\n"; close(OUT); `chmod 770 $basic_description`;

##########################################################################################

# Extracting Statistics Per Bin
if($verbose){ print "  Extracting stats per bin...\n"; } $num_BIN=$num_POS;
log_msg("Extracting stats per bin...");
while($num_BIN>$max_number_bins){ $BIN_len++; $num_BIN=$num_POS/$BIN_len; }
$num_BIN=0; for(my $i=0;$i<$num_POS;$i++){ if($i==(($num_BIN+1)*$BIN_len)){
$num_BIN++; } $BIN_ID[$num_BIN]=$POS_ID[$i]; $BIN_NUMSQ[$num_BIN]+=$POS_NUMSQ[$i];
$BIN_CUMUL[$num_BIN]+=$POS_CUMUL[$i]; $BIN_PHRED[$num_BIN]+=$POS_PHRED[$i];
foreach my $nt (@NTS){ $BIN_CALLS{"$num_BIN-$nt"}+=$POS_CALLS{"$i-$nt"}; } } $num_BIN++;

##########################################################################################

# Reporting Statistics Per Bin
if(($verbose)&&($write_raw_stats_bin)){ print "  Writing stats per bin...\n"; } $sum_nocall=0;
log_msg("Writing stats per bin to $raw_stats_bin_out");
open(OUT,">$raw_stats_bin_out"); print OUT "Position\tNum Reads\tCumulated\tPHRED\tA\tC\tG\tT\tN\n";
for(my $i=0;$i<$num_BIN;$i++){ $BIN_PHRED[$i]=sprintf("%.2f",$BIN_PHRED[$i]/$BIN_CUMUL[$i]);
print OUT "$BIN_ID[$i]\t$BIN_NUMSQ[$i]\t$BIN_CUMUL[$i]\t$BIN_PHRED[$i]"; foreach my $nt (@NTS){
$BIN_CALLS{"$i-$nt"}=sprintf("%.4f",$BIN_CALLS{"$i-$nt"}/$BIN_CUMUL[$i]);
print OUT "\t".$BIN_CALLS{"$i-$nt"}; } print OUT "\n"; my $int_len=$BIN_len; if($i>0){
$int_len=$BIN_ID[$i]-$BIN_ID[$i-1]; } $BIN_CUMUL[$i]=int(($BIN_CUMUL[$i]/$int_len)+0.5);
$sum_nocall+=$BIN_CALLS{"$i-N"}; } close(OUT); `chmod 770 $raw_stats_bin_out`;
if($write_raw_stats_bin==0){ `rm -rf $raw_stats_bin_out`; }

##########################################################################################
#                                                                                        #
#                                    CASE 3 (Others)                                     #
#                                                                                        #
#                      Any dataset not covered by CASE 1 and CASE 2                      #
#                      (Plots not generated but statistics reported)                     #
#                                                                                        #
##########################################################################################

# Reporting Statistics Per Position
else{ if($verbose){ print "  CASE 3 detected (Others)\n  Writing stats per position...\n"; }
log_msg("CASE 3 detected (Others)");
log_msg("Writing stats per position to $raw_stats_pos_out");
open(OUT,">$raw_stats_pos_out"); print OUT "Position\tNum Reads\tCumulated\tPHRED\tA\tC\tG\tT\tN\n";
for(my $i=0;$i<=$#POS_NUMSQ;$i++){ $POS_PHRED[$i]=sprintf("%.2f",$POS_PHRED[$i]/$POS_CUMUL[$i]);
print OUT "$POS_ID[$i]\t$POS_NUMSQ[$i]\t$POS_CUMUL[$i]\t$POS_PHRED[$i]"; foreach my $nt (@NTS){
$POS_CALLS{"$i-$nt"}=sprintf("%.4f",$POS_CALLS{"$i-$nt"}/$POS_CUMUL[$i]);
print OUT "\t".$POS_CALLS{"$i-$nt"}; } print OUT "\n"; } close(OUT); `chmod 770 $raw_stats_pos_out`;

##########################################################################################

# Reporting Basic Sample Description
if($verbose){ print "  Writing basic sample info...\n\n"; } open(OUT,">$basic_description");
log_msg("Writing basic sample info to $basic_description");
print OUT "Files   : $prefix-*\n"; if($multiplex){ print OUT "Library : $library\n";
print OUT "Barcode : $barcode\n"; } else{ print OUT "Sample  : $library\n"; }
print OUT "#Reads  : $num_reads\nMin Len : $min_len\nMax Len : $max_len\n";
print OUT "Avg Len : $avg_len\n"; close(OUT); `chmod 770 $basic_description`; }

##########################################################################################
#                                                                                        #
#                                       Functions                                        #
#                                                                                        #
##########################################################################################

# Format long integers for nicer display
sub format_int{ my $number=$_[0]; my @digits=split("",$number); my $form="";
my $count=0; for(my $i=$#digits;$i>=0;$i--){ $form=$digits[$i].$form; $count++;
if(($count==3)&&($i!=0)){ $count=0; $form=",".$form; } } return $form; }

##########################################################################################

sub log_msg {
    my ($msg) = @_;
    my $timestamp = strftime "%Y-%m-%d %H:%M:%S", localtime;
    print "[$timestamp] $msg\n";
}


