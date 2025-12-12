#!/usr/bin/perl
use strict;

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
my $gnuplot_phred_out="$prefix-PhredQualScores.png";
my $gnuplot_calls_out="$prefix-BaseComposition.png";
my $gnuplot_reads_out="$prefix-LenDistribution.png";
my $gnuplot_source="$prefix-gnuplot.src";
my $gnuplot_data="$prefix-gnuplot.dat";

##########################################################################################

# Variables for Statistics
my $num_POS=0; my @POS_ID; my @POS_NUMSQ; my @POS_CUMUL; my @POS_PHRED; my %POS_CALLS;
my $num_BIN=0; my @BIN_ID; my @BIN_NUMSQ; my @BIN_CUMUL; my @BIN_PHRED; my %BIN_CALLS;
my $BIN_len=1; my $num_reads=0; my $num_len=0; my $avg_len=0; my $min_len;
my $max_len; my $offset=33; my $sum_nocall=0; my @NTS=("A","C","G","T","N");
my %VALID; foreach my $nt (@NTS){ $VALID{"$nt"}=1; }

##########################################################################################

# Variables for Graphs
my $plot_font="font \"DejaVuSerif-Bold,10\"";   my $title_font="font \"DejaVuSerif-Bold,12\"";
my $xtics_font="font \"DejaVuSerif-Bold,10\"";  my $ytics_font="font \"DejaVuSerif-Bold,10\"";
my $xlabel_font="font \"DejaVuSerif-Bold,12\""; my $ylabel_font="font \"DejaVuSerif-Bold,12\"";
my $copyright_font="font \"DejaVuSerif,9\"";    my $copyright_pos="screen 0.01, screen 0.025";
my $phred_ylabel="Mean PHRED Quality Score";       my $calls_ylabel="Base Call Frequency";
my $stats_font="font \"DejaVuSansMono-Bold,12\""; my $stats_pos="screen 0.62, screen 0.82";
my $xlabel="Sequence Position"; my $copyright="Institute for Genomics and Bioinformatics";
my $plot_width=820; my $plot_height=540; my $c_black="lc rgb \"#000000\""; my $c_blue="lc rgb \"#0072B2\""; my $c_red="lc rgb \"#D55E00\"";
my $c_orange="lc rgb \"#E69F00\""; my $c_lgreen="lc rgb \"#009E73\""; my $c_dgreen="lc rgb \"#009E73\""; my $tmargin="5"; my $bmargin="4";
my $title_lane1=""; my $title_lane2=""; my $title_lane3=""; my $pos_min=1; my $pos_xtics=5;
my $pos_max; my $bin_min=1; my $bin_max; my $bin_xtics=10; my $phred_min=60; my $phred_max=0;
my $phred_ytics=1;my $phred_lmargin="8";my $phred_rmargin="3";my $phred_offset="0";my $stats_label;
my $calls_min=1; my $calls_max=0; my $calls_ytics=0.1; my $calls_lmargin="8"; my $calls_rmargin="3";
my $calls_offset=0.5; my $numsq_min=0; my $numsq_max=0; my $numsq_ytics; my $numsq_step;
my $numsq_lmargin; my $numsq_offset=0.5; my $numsq_ylabel=""; my $cumul_min=0; my $cumul_max=0;
my $cumul_ytics; my $cumul_step; my $cumul_rmargin; my $cumul_offset=-0.5; my $cumul_ylabel="";

##########################################################################################
#                                                                                        #
#                                   FastQ File Analysis                                  #
#                                                                                        #
##########################################################################################

# Performing Statistics Per Position
if($verbose){ print "  Analyzing fastq file (long process)...\n"; }
open(IN,"gunzip -c $fastq |"); while(my $l=<IN>){ if($l!~/^@/){
print "Input not in FastQ file format.\n"; exit; } $l=<IN>; chomp($l);
my @nts=split("",$l); my $len=$#nts+1; $POS_NUMSQ[$len-1]++;
for(my $i=0;$i<$len;$i++){ $POS_CUMUL[$i]++; $POS_CALLS{"$i-$nts[$i]"}++; }
$avg_len+=$len; $l=<IN>; $l=<IN>; chomp($l); my @phred=split("",$l);
if(($#phred+1)!=$len){ print "Scores length mismatch.\n"; exit; }
for(my $i=0;$i<$len;$i++){ $POS_PHRED[$i]+=(int(ord($phred[$i]))-$offset); }
$num_reads++; } close(IN); if($num_reads==0){ print "Empty FastQ File!\n"; exit; }
if($verbose){ print "  Done! $num_reads reads found in input.\n"; }

##########################################################################################

# Finalizing Statistics Per Position
if($verbose){ print "  Finalizing stats per position...\n\n"; }
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
if(($verbose)&&($write_raw_stats_pos)){ print "  Writing stats per position...\n"; }
open(OUT,">$raw_stats_pos_out"); print OUT "Position\tNum Reads\tCumulated\tPHRED\tA\tC\tG\tT\tN\n";
for(my $i=0;$i<=$#POS_NUMSQ;$i++){ $POS_PHRED[$i]=sprintf("%.2f",$POS_PHRED[$i]/$POS_CUMUL[$i]);
print OUT "$POS_ID[$i]\t$POS_NUMSQ[$i]\t$POS_CUMUL[$i]\t$POS_PHRED[$i]"; foreach my $nt (@NTS){
$POS_CALLS{"$i-$nt"}=sprintf("%.4f",$POS_CALLS{"$i-$nt"}/$POS_CUMUL[$i]);
print OUT "\t".$POS_CALLS{"$i-$nt"}; } print OUT "\n"; } close(OUT);
`chmod 770 $raw_stats_pos_out`; if($write_raw_stats_pos==0){ `rm -rf $raw_stats_pos_out`; }

##########################################################################################

# Reporting Basic Sample Description
if($verbose){ print "  Writing basic sample info...\n"; } open(OUT,">$basic_description");
print OUT "Files   : $prefix-*\n"; if($multiplex){ print OUT "Library : $library\n";
print OUT "Barcode : $barcode\n"; } else{ print OUT "Sample  : $library\n"; }
print OUT "#Reads  : $num_reads\n#Cycles : $num_POS\n"; close(OUT); `chmod 770 $basic_description`;

##########################################################################################

# Extracting Graph Features
if($verbose){ print "  Extracting graph features...\n\n"; } if($multiplex){
$title_lane1="Library '$library' - Barcode"; if($barcode=~/^[ACGT]+$/){
$title_lane1.=" '$barcode'"; } elsif($barcode eq "Not Recognized"){
$title_lane1.=" $barcode"; } else{ $title_lane1.="s '$barcode'"; } } else{
$title_lane1="Sample '$library'"; } $pos_max=$num_POS; while(($pos_max/$pos_xtics)>21){
$pos_xtics+=5; } for(my $i=0;$i<$num_POS;$i++){ if($POS_PHRED[$i]<$phred_min){
$phred_min=$POS_PHRED[$i]; } if($POS_PHRED[$i]>$phred_max){ $phred_max=$POS_PHRED[$i]; }
foreach my $nt (@NTS){ if($POS_CALLS{"$i-$nt"}<$calls_min){ $calls_min=$POS_CALLS{"$i-$nt"}; }
if($POS_CALLS{"$i-$nt"}>$calls_max){ $calls_max=$POS_CALLS{"$i-$nt"}; } } }
$phred_min-=1; $phred_max+=1; while((($phred_max-$phred_min+1)/$phred_ytics)>16){
$phred_ytics++; } $calls_min-=0.1; if($calls_min<0){ $calls_min=0; } $calls_max+=0.1;
if($calls_max>1){ $calls_max=1; } if($calls_max<0.5){ $calls_max=0.5; }

##########################################################################################

# Generating Gnuplot Figure - PHRED Scores
if($verbose){ print "  Generating plot for quality scores...\n"; } open(OUT,">$gnuplot_data");
for(my $i=0;$i<$num_POS;$i++){ print OUT "$POS_ID[$i] $POS_PHRED[$i]\n"; } close(OUT);
$title_lane3="Sequencing Data Quality"; open(OUT,">$gnuplot_source");
print OUT "set term png size $plot_width,$plot_height $plot_font\n";
print OUT "set output \"$gnuplot_phred_out\"\n";
print OUT "set tmargin $tmargin\nset bmargin $bmargin\n";
print OUT "set title \"$title_lane1\\n$title_lane2\\n$title_lane3\" $title_font\n";
print OUT "set xrange [$pos_min:$pos_max]\n";
print OUT "set xtics $pos_xtics $xtics_font\n";
print OUT "set xtics nomirror\nset grid xtics\n";
print OUT "set xlabel \"$xlabel\" $xlabel_font\n";
print OUT "set label \"$copyright\" at $copyright_pos $copyright_font\n";
print OUT "set lmargin $phred_lmargin\nset rmargin $phred_rmargin\n";
print OUT "set yrange [$phred_min:$phred_max]\n";
print OUT "set ytics $phred_ytics $ytics_font\n";
print OUT "set ytics nomirror\nset grid ytics\n";
print OUT "set ylabel \"$phred_ylabel\" offset $phred_offset,0 $ylabel_font\n";
print OUT "plot \"$gnuplot_data\" using 1:2 with lines $c_blue lw 2 notitle\n"; close(OUT);
`chmod 770 $gnuplot_data $gnuplot_source; $gdfont_export; gnuplot $gnuplot_source`;
`rm -rf $gnuplot_data $gnuplot_source; chmod 770 $gnuplot_phred_out`;

##########################################################################################

# Generating Gnuplot Figure - Base Composition
if($verbose){ print "  Generating plot for base composition...\n\n"; }
open(OUT,">$gnuplot_data"); for(my $i=0;$i<$num_POS;$i++){ print OUT "$POS_ID[$i]";
foreach my $nt (@NTS){ print OUT " ".$POS_CALLS{"$i-$nt"}; } print OUT "\n"; }
close(OUT); $title_lane3="Base Composition"; open(OUT,">$gnuplot_source");
print OUT "set term png size $plot_width,$plot_height $plot_font\n";
print OUT "set output \"$gnuplot_calls_out\"\n";
print OUT "set tmargin $tmargin\nset bmargin $bmargin\n";
print OUT "set title \"$title_lane1\\n$title_lane2\\n$title_lane3\" $title_font\n";
print OUT "set xrange [$pos_min:$pos_max]\n";
print OUT "set xtics $pos_xtics $xtics_font\n";
print OUT "set xtics nomirror\nset grid xtics\n";
print OUT "set xlabel \"$xlabel\" $xlabel_font\n";
print OUT "set label \"$copyright\" at $copyright_pos $copyright_font\n";
print OUT "set lmargin $calls_lmargin\nset rmargin $calls_rmargin\n";
print OUT "set yrange [$calls_min:$calls_max]\n";
print OUT "set ytics $calls_ytics $ytics_font\n";
print OUT "set ytics nomirror\nset grid ytics\n";
print OUT "set ylabel \"$calls_ylabel\" offset $calls_offset,0 $ylabel_font\n";
print OUT "plot \"$gnuplot_data\" using 1:2 with lines $c_blue lw 2 title \"A\", ";
print OUT "\"$gnuplot_data\" using 1:3 with lines $c_red lw 2 title \"C\", ";
print OUT "\"$gnuplot_data\" using 1:4 with lines $c_orange lw 2 title \"G\", ";
print OUT "\"$gnuplot_data\" using 1:5 with lines $c_lgreen lw 2 title \"T\", ";
print OUT "\"$gnuplot_data\" using 1:6 with lines $c_black lw 2 title \"N\"\n"; close(OUT);
`chmod 770 $gnuplot_data $gnuplot_source; $gdfont_export; gnuplot $gnuplot_source`;
`rm -rf $gnuplot_data $gnuplot_source; chmod 770 $gnuplot_calls_out`; }

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
if(($verbose)&&($write_raw_stats_pos)){ print "  Writing stats per position...\n"; }
open(OUT,">$raw_stats_pos_out"); print OUT "Position\tNum Reads\tCumulated\tPHRED\tA\tC\tG\tT\tN\n";
for(my $i=0;$i<=$#POS_NUMSQ;$i++){ my $pos_phred=sprintf("%.2f",$POS_PHRED[$i]/$POS_CUMUL[$i]);
print OUT "$POS_ID[$i]\t$POS_NUMSQ[$i]\t$POS_CUMUL[$i]\t$pos_phred";
foreach my $nt (@NTS){ my $pos_call=sprintf("%.4f",$POS_CALLS{"$i-$nt"}/$POS_CUMUL[$i]);
print OUT "\t$pos_call"; } print OUT "\n"; } close(OUT); `chmod 770 $raw_stats_pos_out`;
if($write_raw_stats_pos==0){ `rm -rf $raw_stats_pos_out`; }

##########################################################################################

# Reporting Basic Sample Description
if($verbose){ print "  Writing basic sample info...\n"; } open(OUT,">$basic_description");
print OUT "Files   : $prefix-*\nSample  : $library\n#Reads  : $num_reads\nMin Len : $min_len\n";
print OUT "Max Len : $max_len\nAvg Len : $avg_len\n"; close(OUT); `chmod 770 $basic_description`;

##########################################################################################

# Extracting Statistics Per Bin
if($verbose){ print "  Extracting stats per bin...\n"; } $num_BIN=$num_POS;
while($num_BIN>$max_number_bins){ $BIN_len++; $num_BIN=$num_POS/$BIN_len; }
$num_BIN=0; for(my $i=0;$i<$num_POS;$i++){ if($i==(($num_BIN+1)*$BIN_len)){
$num_BIN++; } $BIN_ID[$num_BIN]=$POS_ID[$i]; $BIN_NUMSQ[$num_BIN]+=$POS_NUMSQ[$i];
$BIN_CUMUL[$num_BIN]+=$POS_CUMUL[$i]; $BIN_PHRED[$num_BIN]+=$POS_PHRED[$i];
foreach my $nt (@NTS){ $BIN_CALLS{"$num_BIN-$nt"}+=$POS_CALLS{"$i-$nt"}; } } $num_BIN++;

##########################################################################################

# Reporting Statistics Per Bin
if(($verbose)&&($write_raw_stats_bin)){ print "  Writing stats per bin...\n"; } $sum_nocall=0;
open(OUT,">$raw_stats_bin_out"); print OUT "Position\tNum Reads\tCumulated\tPHRED\tA\tC\tG\tT\tN\n";
for(my $i=0;$i<$num_BIN;$i++){ $BIN_PHRED[$i]=sprintf("%.2f",$BIN_PHRED[$i]/$BIN_CUMUL[$i]);
print OUT "$BIN_ID[$i]\t$BIN_NUMSQ[$i]\t$BIN_CUMUL[$i]\t$BIN_PHRED[$i]"; foreach my $nt (@NTS){
$BIN_CALLS{"$i-$nt"}=sprintf("%.4f",$BIN_CALLS{"$i-$nt"}/$BIN_CUMUL[$i]);
print OUT "\t".$BIN_CALLS{"$i-$nt"}; } print OUT "\n"; my $int_len=$BIN_len; if($i>0){
$int_len=$BIN_ID[$i]-$BIN_ID[$i-1]; } $BIN_CUMUL[$i]=int(($BIN_CUMUL[$i]/$int_len)+0.5);
$sum_nocall+=$BIN_CALLS{"$i-N"}; } close(OUT); `chmod 770 $raw_stats_bin_out`;
if($write_raw_stats_bin==0){ `rm -rf $raw_stats_bin_out`; }

##########################################################################################

# Extracting Graph Features
if($verbose){ print "  Extracting graph features...\n\n"; }
$title_lane1="Sample '$library' - $num_reads Sequences"; $bin_min=$BIN_ID[0];
$bin_max=$num_POS; $bin_xtics=best_interval_len($bin_max); $bin_max+=int($bin_xtics/5);
while(($bin_max/$bin_xtics)>17){ $bin_xtics+=best_interval_len($bin_max); }
for(my $i=0;$i<$num_BIN;$i++){ if($BIN_PHRED[$i]<$phred_min){ $phred_min=$BIN_PHRED[$i]; }
if($BIN_PHRED[$i]>$phred_max){ $phred_max=$BIN_PHRED[$i]; } foreach my $nt (@NTS){
if(!(($sum_nocall==0)&&($nt eq "N"))){ if($BIN_CALLS{"$i-$nt"}<$calls_min){
$calls_min=$BIN_CALLS{"$i-$nt"}; } if($BIN_CALLS{"$i-$nt"}>$calls_max){
$calls_max=$BIN_CALLS{"$i-$nt"}; } } } if($BIN_NUMSQ[$i]>$numsq_max){
$numsq_max=$BIN_NUMSQ[$i]; } if($BIN_CUMUL[$i]>$cumul_max){
$cumul_max=$BIN_CUMUL[$i]; } } $phred_min-=1; $phred_max+=1; $phred_rmargin="4";
while((($phred_max-$phred_min+1)/$phred_ytics)>16){ $phred_ytics++; } $calls_rmargin="4";
$calls_min-=0.1; if($calls_min<0){ $calls_min=0; } $calls_max+=0.1; if($calls_max>1){
$calls_max=1; } if($calls_max<0.5){ $calls_max=0.5; } $numsq_step=best_interval_len($numsq_max);
$cumul_step=best_interval_len($cumul_max); $numsq_ytics=$numsq_step; $cumul_ytics=$cumul_step;
$numsq_max+=$numsq_step; $cumul_max+=$cumul_step; while(($numsq_max/$numsq_ytics)>17){
$numsq_ytics+=$numsq_step; } while(($cumul_max/$cumul_ytics)>17){ $cumul_ytics+=$cumul_step; }
$numsq_lmargin=best_label_margin($numsq_max); $cumul_rmargin=best_label_margin($cumul_max);
$numsq_ylabel="# Sequences per $BIN_len bp bin"; $cumul_ylabel="# Sequences of length > n";
$stats_label="Min length = ".format_int($min_len)."\\nMax length = ";
$stats_label.=format_int($max_len)."\\nAvg length = ".format_int(int($avg_len+0.5));

##########################################################################################

# Generating Gnuplot Figure - PHRED Scores
if($verbose){ print "  Generating plot for quality scores...\n"; } open(OUT,">$gnuplot_data");
for(my $i=0;$i<$num_BIN;$i++){ print OUT "$BIN_ID[$i] $BIN_PHRED[$i]\n"; } close(OUT);
$title_lane3="Sequencing Data Quality"; open(OUT,">$gnuplot_source");
print OUT "set term png size $plot_width,$plot_height $plot_font\n";
print OUT "set output \"$gnuplot_phred_out\"\n";
print OUT "set tmargin $tmargin\nset bmargin $bmargin\n";
print OUT "set title \"$title_lane1\\n$title_lane2\\n$title_lane3\" $title_font\n";
print OUT "set xrange [$bin_min:$bin_max]\n";
print OUT "set xtics $bin_xtics $xtics_font\n";
print OUT "set xtics nomirror\nset grid xtics\n";
print OUT "set xlabel \"$xlabel\" $xlabel_font\n";
print OUT "set label \"$copyright\" at $copyright_pos $copyright_font\n";
print OUT "set lmargin $phred_lmargin\nset rmargin $phred_rmargin\n";
print OUT "set yrange [$phred_min:$phred_max]\n";
print OUT "set ytics $phred_ytics $ytics_font\n";
print OUT "set ytics nomirror\nset grid ytics\n";
print OUT "set ylabel \"$phred_ylabel\" offset $phred_offset,0 $ylabel_font\n";
print OUT "plot \"$gnuplot_data\" using 1:2 with lines $c_blue lw 2 notitle\n"; close(OUT);
`chmod 770 $gnuplot_data $gnuplot_source; $gdfont_export; gnuplot $gnuplot_source`;
`rm -rf $gnuplot_data $gnuplot_source; chmod 770 $gnuplot_phred_out`;

##########################################################################################

# Generating Gnuplot Figure - Base Composition
if($verbose){ print "  Generating plot for base composition...\n"; } open(OUT,">$gnuplot_data");
for(my $i=0;$i<$num_BIN;$i++){ print OUT "$BIN_ID[$i]"; foreach my $nt (@NTS){
if(!(($sum_nocall==0)&&($nt eq "N"))){ print OUT " ".$BIN_CALLS{"$i-$nt"}; } }
print OUT "\n"; } close(OUT); $title_lane3="Base Composition"; open(OUT,">$gnuplot_source");
print OUT "set term png size $plot_width,$plot_height $plot_font\n";
print OUT "set output \"$gnuplot_calls_out\"\n";
print OUT "set tmargin $tmargin\nset bmargin $bmargin\n";
print OUT "set title \"$title_lane1\\n$title_lane2\\n$title_lane3\" $title_font\n";
print OUT "set xrange [$bin_min:$bin_max]\n";
print OUT "set xtics $bin_xtics $xtics_font\n";
print OUT "set xtics nomirror\nset grid xtics\n";
print OUT "set xlabel \"$xlabel\" $xlabel_font\n";
print OUT "set label \"$copyright\" at $copyright_pos $copyright_font\n";
print OUT "set lmargin $calls_lmargin\nset rmargin $calls_rmargin\n";
print OUT "set yrange [$calls_min:$calls_max]\n";
print OUT "set ytics $calls_ytics $ytics_font\n";
print OUT "set ytics nomirror\nset grid ytics\n";
print OUT "set ylabel \"$calls_ylabel\" offset $calls_offset,0 $ylabel_font\n";
print OUT "plot \"$gnuplot_data\" using 1:2 with lines $c_blue lw 2 title \"A\", ";
print OUT "\"$gnuplot_data\" using 1:3 with lines $c_red lw 2 title \"C\", ";
print OUT "\"$gnuplot_data\" using 1:4 with lines $c_orange lw 2 title \"G\", ";
print OUT "\"$gnuplot_data\" using 1:5 with lines $c_lgreen lw 2 title \"T\""; if($sum_nocall!=0){
print OUT "\"$gnuplot_data\" using 1:6 with lines $c_black lw 2 title \"N\"\n"; }
else{ print OUT "\n"; } close(OUT);
`chmod 770 $gnuplot_data $gnuplot_source; $gdfont_export; gnuplot $gnuplot_source`;
`rm -rf $gnuplot_data $gnuplot_source; chmod 770 $gnuplot_calls_out`;

##########################################################################################

# Generating Gnuplot Figure - Read Length Distribution
if($verbose){ print "  Generating plot for length distribution...\n\n"; }
open(OUT,">$gnuplot_data"); for(my $i=0;$i<$num_BIN;$i++){
print OUT "$BIN_ID[$i] $BIN_NUMSQ[$i] $BIN_CUMUL[$i]\n"; }
close(OUT); $title_lane3="Sequence Length Distribution";
$xlabel="Sequence Length (n)"; open(OUT,">$gnuplot_source");
print OUT "set term png size $plot_width,$plot_height $plot_font\n";
print OUT "set output \"$gnuplot_reads_out\"\n";
print OUT "set tmargin $tmargin\nset bmargin $bmargin\n";
print OUT "set title \"$title_lane1\\n$title_lane2\\n$title_lane3\" $title_font\n";
print OUT "set xrange [$bin_min:$bin_max]\n";
print OUT "set xtics $bin_xtics $xtics_font\n";
print OUT "set xtics nomirror\nset grid xtics\n";
print OUT "set xlabel \"$xlabel\" $xlabel_font\n";
print OUT "set label \"$copyright\" at $copyright_pos $copyright_font\n";
print OUT "set lmargin $numsq_lmargin\nset rmargin $cumul_rmargin\n";
print OUT "set yrange [$numsq_min:$numsq_max]\n";
print OUT "set y2range [$cumul_min:$cumul_max]\n";
print OUT "set ytics $numsq_ytics $ytics_font\n";
print OUT "set y2tics $cumul_ytics $ytics_font\n";
print OUT "set ytics nomirror\nset grid ytics\n";
print OUT "set y2tics nomirror\nset grid y2tics\n";
print OUT "set ylabel \"$numsq_ylabel\" offset $numsq_offset,0 $ylabel_font textcolor $c_dgreen\n";
print OUT "set y2label '$cumul_ylabel' offset $cumul_offset,0 $ylabel_font textcolor $c_red\n";
print OUT "set label \"$stats_label\" at $stats_pos $stats_font textcolor lt 12\n";
print OUT "plot \"$gnuplot_data\" using 1:2 with boxes $c_dgreen lw 2 notitle axis x1y1, ";
print OUT "\"$gnuplot_data\" using 1:3 with lines $c_red lw 2 notitle axis x1y2\n"; close(OUT);
`chmod 770 $gnuplot_data $gnuplot_source; $gdfont_export; gnuplot $gnuplot_source`;
`rm -rf $gnuplot_data $gnuplot_source; chmod 770 $gnuplot_reads_out`; }

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
open(OUT,">$raw_stats_pos_out"); print OUT "Position\tNum Reads\tCumulated\tPHRED\tA\tC\tG\tT\tN\n";
for(my $i=0;$i<=$#POS_NUMSQ;$i++){ $POS_PHRED[$i]=sprintf("%.2f",$POS_PHRED[$i]/$POS_CUMUL[$i]);
print OUT "$POS_ID[$i]\t$POS_NUMSQ[$i]\t$POS_CUMUL[$i]\t$POS_PHRED[$i]"; foreach my $nt (@NTS){
$POS_CALLS{"$i-$nt"}=sprintf("%.4f",$POS_CALLS{"$i-$nt"}/$POS_CUMUL[$i]);
print OUT "\t".$POS_CALLS{"$i-$nt"}; } print OUT "\n"; } close(OUT); `chmod 770 $raw_stats_pos_out`;

##########################################################################################

# Reporting Basic Sample Description
if($verbose){ print "  Writing basic sample info...\n\n"; } open(OUT,">$basic_description");
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

# Returns appropriate xtics/ytics for a given number of sequences
sub best_interval_len{my $n=$_[0];if($n<=160){return 10;} if($n<=320){ return 20; } if($n<=400){
return 25; } if($n<=800){ return 50; } if($n<=1600){ return 100; } if($n<=3200){ return 200; }
if($n<=4000){ return 250; } if($n<=8000){ return 500; } if($n<=16000){ return 1000; }
if($n<=32000){ return 2000; } if($n<=40000){ return 2500; } if($n<=80000){ return 5000; }
if($n<=160000){ return 10000; } if($n<=320000){ return 20000; } if($n<=400000){ return 25000; }
if($n<=800000){ return 50000; } if($n<=1600000){ return 100000; } if($n<=3200000){ return 200000; }
if($n<=4000000){ return 250000; } if($n<=8000000){ return 500000; } return 1000000; }

##########################################################################################

# Returns appropriate label margin for a given number of sequences
sub best_label_margin{ my $n=$_[0]; if($n<100){ return 7; } if($n<1000){ return 8; }
if($n<10000){ return 9; } if($n<100000){ return 10; } return 11; }

