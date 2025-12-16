#!/usr/bin/env perl
use strict;
use POSIX qw(strftime);
use Parallel::ForkManager;
use Storable qw(store retrieve);
use Getopt::Long;

##########################################################################################
#                                                                                        #
# Script  : analyze_paired_reads.pl                                                      #
# Author  : Christophe Magnan                                                            #
# Updated : 2018/02/06                                                                   #
#                                                                                        #
# Update  : 2019/07/10                                                                   #
# changed if(($len>=4)&&($len<=10)&&($cand=~/^[ACGT]+$/)){ $multiplex=1;                 #
# to if(($len>=4)&&($len<=12) to account for long MiSeq barcodes                         #
# by Yuzo Kanomata                                                                       #
#                                                                                        #
##########################################################################################
#
# Usage:
#   ./analyze_paired_reads.pl  fastqR1.fastq.gz  fastqR2.fastq.gz  prefix  [sample]
#
# Example:
#   ./analyze_paired_reads.pl lane1_R1.fastq.gz lane1_R2.fastq.gz SAMPLE1
#
# Notes:
#   - Accepts gzipped FASTQ files (the script uses `gunzip -c`).
#   - If `prefix` contains '-' separated barcodes, multiplex mode is detected.
#   - `prefix` is used to form output filenames (e.g., `<prefix>-PhredQualScores.png`).
#
# Script Behaviour
# Default runtime flags (can be overridden by CLI options)
my $verbose=1;                 # Display messages or not (default on)
my $workers=16;                 # default number of worker processes
my $write_raw_stats_pos=0;     # Report raw statistics per position
# Multi-process batch reader: children compute partial stats and write storable temp files.
my $batch_size = 1000000;   # number of read pairs per child batch
my $batch_id = 0;

##########################################################################################

# Script Inputs
my $script_usage="./analyze_paired_reads.pl [--workers N] [--verbose] fastqR1 fastqR2 prefix [sample]";

# Parse command-line options (Getopt::Long removes options from @ARGV)
my $opt_verbose;
GetOptions(
    'workers|w=i' => \$workers,
    'verbose|v!'  => \$opt_verbose,
) or die "Error parsing options\n";
if(defined $opt_verbose){ $verbose = $opt_verbose ? 1 : 1; }

# Initialize fork manager with chosen worker count
my $pm = Parallel::ForkManager->new($workers);

if(($#ARGV!=2)&&($#ARGV!=3)){ print "\nUsage: $script_usage\n\n"; exit; }
my $fastqR1=$ARGV[0]; my $fastqR2=$ARGV[1]; my $prefix=$ARGV[2]; my $library="$prefix";
my $multiplex=0; my $barcode=""; if($#ARGV==3){ $library=$ARGV[3]; } if($prefix=~"-"){
my @d=split("-",$prefix); foreach my $cand (@d){ my $len=length($cand);
if(($len>=4)&&($len<=12)&&($cand=~/^[ACGT]+$/)){ $multiplex=1;
if($barcode eq ""){ $barcode="$cand"; } else{ $barcode.="-$cand"; } }
if($cand eq "PrNotRecog"){ $multiplex=1; $barcode="Not Recognized"; } } }

# Setup logging
my $log_dir = "logs";
unless(-e $log_dir or mkdir $log_dir) {
    die "Unable to create $log_dir\n";
}
my $timestamp_fn = strftime "%Y%m%d_%H%M%S", localtime;
my $log_file = "$log_dir/${library}_${timestamp_fn}.log";
open(our $LOG_FH, '>', $log_file) or die "Could not open log file $log_file: $!";
log_msg("Log file created: $log_file");

if(! -f "$fastqR1"){ print "Input Fastq File 1 Not Found.\n"; exit; }
if(! -f "$fastqR2"){ print "Input Fastq File 2 Not Found.\n"; exit; }
my $gdfont_path="/usr/share/fonts/dejavu-sans-fonts:/usr/share/fonts/dejavu-serif-fonts:/usr/share/fonts/dejavu-sans-mono-fonts";
my $gdfont_export="export GDFONTPATH=$gdfont_path";
if($verbose){ 
    log_msg("\n  FASTQ IN 1 : $fastqR1\n  FASTQ IN 2 : $fastqR2\n  PREFIX OUT : $prefix\n  SAMPLE ID  : $library\n  MULTIPLEX  : $multiplex\n  BARCODE    : $barcode\n"); 
}

##########################################################################################

# Script Outputs
my $raw_stats_pos_out="$prefix-RawStatsPerPos.tsv";
my $basic_description="$prefix-SampleBasicInfo.txt";
my $gnuplot_phred_out="$prefix-PhredQualScores.png";
my $gnuplot_callsR1_out="$prefix-READ1-BaseComposition.png";
my $gnuplot_callsR2_out="$prefix-READ2-BaseComposition.png";
my $gnuplot_source="$prefix-gnuplot.src";
my $gnuplot_data="$prefix-gnuplot.dat";

##########################################################################################

# Variables for Statistics
my $num_POS_R1=0; my @POS_ID_R1; my @POS_PHRED_R1; my %POS_CALLS_R1;
my $num_POS_R2=0; my @POS_ID_R2; my @POS_PHRED_R2; my %POS_CALLS_R2;
my $num_reads=0; my $offset=33; my $sum_nocall=0; my %VALID;
my @NTS=("A","C","G","T","N"); foreach my $nt (@NTS){ $VALID{"$nt"}=1; }

##########################################################################################

# Variables for Graphs
my $plot_font="font \"DejaVuSerif-Bold,10\"";   my $title_font="font \"DejaVuSerif-Bold,12\"";
my $xtics_font="font \"DejaVuSerif-Bold,10\"";  my $ytics_font="font \"DejaVuSerif-Bold,10\"";
my $xlabel_font="font \"DejaVuSerif-Bold,12\""; my $ylabel_font="font \"DejaVuSerif-Bold,12\"";
my $copyright_font="font \"DejaVuSerif,9\"";    my $copyright_pos="screen 0.01, screen 0.025";
my $phred_ylabel="Mean PHRED Quality Score";       my $calls_ylabel="Base Call Frequency";
my $xlabel="Sequence Position"; my $copyright="Institute for Genomics and Bioinformatics";
my $c_black="lc rgb \"#000000\""; my $c_blue="lc rgb \"#0072B2\""; my $c_red="lc rgb \"#D55E00\""; my $c_orange="lc rgb \"#E69F00\"";
my $c_lgreen="lc rgb \"#009E73\""; my $plot_width=820; my $plot_height=540; my $tmargin="5";
my $title_lane1=""; my $title_lane2=""; my $title_lane3=""; my $bmargin="4"; my $pos_min=1;
my $pos_max; my $pos_xtics=5; my $phred_min=60; my $phred_max=0; my $phred_ytics=1;
my $phred_lmargin="8"; my $phred_rmargin="3"; my $phred_offset="0"; my $callsR1_min=1;
my $callsR1_max=0; my $callsR1_ytics=0.1; my $callsR2_min=1; my $callsR2_max=0;
my $callsR2_ytics=0.1; my $calls_lmargin="8"; my $calls_rmargin="3"; my $calls_offset=0.5;

##########################################################################################
#                                                                                        #
#                                  FastQ Files Analysis                                  #
#                                                                                        #
##########################################################################################

# Performing Statistics Per Position
if($verbose){ log_msg("  Analyzing fastq files (long process)..."); }

# Ensure temporary directory for child stats exists
my $tmp_dir = "tmp";
unless(-e $tmp_dir or mkdir $tmp_dir) {
    die "Unable to create temporary directory $tmp_dir\n";
}
open(IN1,"gunzip -c $fastqR1 |"); open(IN2,"gunzip -c $fastqR2 |");

while(1){
    my @batch_seq1; my @batch_qual1;
    my @batch_seq2; my @batch_qual2;

    for(my $r=0;$r<$batch_size;$r++){
        my $h1 = <IN1>;
        last unless defined $h1;
        chomp($h1);
        unless($h1 =~ /^\@/){ print "1 not in FastQ file format.\n"; exit; }

        my $h2 = <IN2>;
        unless(defined $h2){ print "Inputs are not paired-reads.\n"; exit; }
        chomp($h2);
        unless($h2 =~ /^\@/){ print "Input 2 not in FastQ file format.\n"; exit; }

        my $seq1 = <IN1>;
        last unless defined $seq1;
        chomp($seq1);
        my $plus1 = <IN1>;
        my $qual1 = <IN1>;
        last unless defined $qual1;
        chomp($qual1);

        my $seq2 = <IN2>;
        last unless defined $seq2;
        chomp($seq2);
        my $plus2 = <IN2>;
        my $qual2 = <IN2>;
        last unless defined $qual2;
        chomp($qual2);

        push @batch_seq1, $seq1; push @batch_qual1, $qual1;
        push @batch_seq2, $seq2; push @batch_qual2, $qual2;
    }

    last if scalar(@batch_seq1) == 0;

    my $this_id = $batch_id++;
    $pm->start and next;

    # child: compute local stats
    my %local_calls_r1; my %local_calls_r2;
    my @local_phred_r1; my @local_phred_r2;
    my $local_reads = 0;
    for(my $i=0;$i<@batch_seq1;$i++){
        my @nts1 = split("", $batch_seq1[$i]); my $len1 = scalar @nts1;
        $num_POS_R1 = $len1 if ($num_POS_R1 == 0);
        for(my $k=0;$k<$len1;$k++){ $local_calls_r1{"$k-$nts1[$k]"}++; }

        my @q1 = split("", $batch_qual1[$i]);
        for(my $k=0;$k<$len1;$k++){ $local_phred_r1[$k] += (ord($q1[$k]) - $offset); }

        my @nts2 = split("", $batch_seq2[$i]); my $len2 = scalar @nts2;
        $num_POS_R2 = $len2 if ($num_POS_R2 == 0);
        for(my $k=0;$k<$len2;$k++){ $local_calls_r2{"$k-$nts2[$k]"}++; }

        my @q2 = split("", $batch_qual2[$i]);
        for(my $k=0;$k<$len2;$k++){ $local_phred_r2[$k] += (ord($q2[$k]) - $offset); }

        $local_reads++;
    }

    my $tmp = "$tmp_dir/tmp_stats_${this_id}_$$.storable";
    store { pr1=>\@local_phred_r1, cr1=>\%local_calls_r1, pr2=>\@local_phred_r2, cr2=>\%local_calls_r2, nr=>$local_reads }, $tmp;
    $pm->finish;
}
close(IN1); close(IN2);
$pm->wait_all_children();

# Parent: merge temporary storable files produced by children
foreach my $f (glob "$tmp_dir/tmp_stats_*.storable"){
    my $h = retrieve($f);
    my $nr = $h->{nr} || 0;
    $num_reads += $nr;

    my $pr1 = $h->{pr1} || [];
    for(my $i=0;$i<@$pr1;$i++){ $POS_PHRED_R1[$i] += ($pr1->[$i]||0); }
    my $pr2 = $h->{pr2} || [];
    for(my $i=0;$i<@$pr2;$i++){ $POS_PHRED_R2[$i] += ($pr2->[$i]||0); }

    while(my ($k,$v) = each %{ $h->{cr1} || {} }){ $POS_CALLS_R1{$k} += $v; }
    while(my ($k,$v) = each %{ $h->{cr2} || {} }){ $POS_CALLS_R2{$k} += $v; }

    unlink $f;
}

if($num_reads==0){ print "Empty FastQ Files!\n"; exit; }
if($verbose){ log_msg("  Done! $num_reads paired-reads found in input."); }

##########################################################################################

# Finalizing Statistics Per Position
if($verbose){ log_msg("  Finalizing stats per position...\n"); } for(my $i=0;$i<$num_POS_R1;$i++){
my $pos=$i+1; push(@POS_ID_R1,"$pos"); if($POS_PHRED_R1[$i] eq ""){ print "Inconsistent PHRED.\n";
exit; } foreach my $nt (@NTS){ if($POS_CALLS_R1{"$i-$nt"} eq ""){ $POS_CALLS_R1{"$i-$nt"}=0; } }
$sum_nocall+=$POS_CALLS_R1{"$i-N"}; } for(my $i=0;$i<$num_POS_R2;$i++){ my $pos=$i+1;
push(@POS_ID_R2,"$pos"); if($POS_PHRED_R2[$i] eq ""){ print "Inconsistent PHRED scores.\n";
exit; } foreach my $nt (@NTS){ if($POS_CALLS_R2{"$i-$nt"} eq ""){
$POS_CALLS_R2{"$i-$nt"}=0; } } $sum_nocall+=$POS_CALLS_R2{"$i-N"}; }

##########################################################################################
#                                                                                        #
#                                  Statistics Reporting                                  #
#                                                                                        #
##########################################################################################

# Reporting Statistics Per Position
if(($verbose)&&($write_raw_stats_pos)){ log_msg("  Writing stats per position..."); }
open(OUT,">$raw_stats_pos_out"); print OUT "Position\tPHRED (1)\tA (1)\tC (1)\tG (1)\t";
print OUT "T (1)\tN (1)\tPHRED (2)\tA (2)\tC (2)\tG (2)\tT (2)\tN (2)\n"; my $max_pos=$num_POS_R1;
if($num_POS_R2>$max_pos){ $max_pos=$num_POS_R2; } for(my $i=0;$i<$max_pos;$i++){
if($POS_ID_R1[$i] ne ""){ if($POS_ID_R2[$i] ne ""){ if($POS_ID_R1[$i] ne $POS_ID_R2[$i]){
print "Inconsistent position ID.\n"; exit; } } print OUT "$POS_ID_R1[$i]"; } else{
if($POS_ID_R2[$i] ne ""){ print OUT "$POS_ID_R2[$i]"; } else{ print "Inconsistent position ID.\n";
exit; } } if($i<$num_POS_R1){ $POS_PHRED_R1[$i]=sprintf("%.2f",$POS_PHRED_R1[$i]/$num_reads);
print OUT "\t$POS_PHRED_R1[$i]"; } else{ print OUT "\t"; } foreach my $nt (@NTS){
if($i<$num_POS_R1){ $POS_CALLS_R1{"$i-$nt"}=sprintf("%.4f",$POS_CALLS_R1{"$i-$nt"}/$num_reads);
print OUT "\t".$POS_CALLS_R1{"$i-$nt"}; } else{ print OUT "\t"; } } if($i<$num_POS_R2){
$POS_PHRED_R2[$i]=sprintf("%.2f",$POS_PHRED_R2[$i]/$num_reads); print OUT "\t$POS_PHRED_R2[$i]"; }
else{ print OUT "\t"; } foreach my $nt (@NTS){ if($i<$num_POS_R2){
$POS_CALLS_R2{"$i-$nt"}=sprintf("%.4f",$POS_CALLS_R2{"$i-$nt"}/$num_reads);
print OUT "\t".$POS_CALLS_R2{"$i-$nt"}; } else{ print OUT "\t"; } } print OUT "\n"; } close(OUT);
`chmod 770 $raw_stats_pos_out`; if($write_raw_stats_pos==0){ `rm -rf $raw_stats_pos_out`; }

##########################################################################################

# Reporting Basic Sample Description
if($verbose){ log_msg("  Writing basic sample info..."); }
open(OUT,">$basic_description"); $num_reads=format_int($num_reads);
print OUT "Files   : $prefix-*\n"; if($multiplex){ print OUT "Library : $library\n";
print OUT "Barcode : $barcode\n"; } else{ print OUT "Sample  : $library\n"; }
print OUT "#Reads  : $num_reads\nCycles1 : $num_POS_R1\nCycles2 : $num_POS_R2\n";
close(OUT); `chmod 770 $basic_description`;

##########################################################################################

# Extracting Graph Features
if($verbose){ log_msg("  Extracting graph features...\n"); } if($multiplex){
$title_lane1="Library '$library' - Barcode"; if($barcode=~/^[ACGT]+$/){
$title_lane1.=" '$barcode'"; } elsif($barcode eq "Not Recognized"){
$title_lane1.=" $barcode"; } else{ $title_lane1.="s '$barcode'"; } } else{
$title_lane1="Sample '$library'"; } my $max_pos=$num_POS_R1; if($num_POS_R2>$max_pos){
$max_pos=$num_POS_R2; } $pos_max=$max_pos; while(($pos_max/$pos_xtics)>21){ $pos_xtics+=5; }
for(my $i=0;$i<$num_POS_R1;$i++){ if($POS_PHRED_R1[$i]<$phred_min){ $phred_min=$POS_PHRED_R1[$i]; }
if($POS_PHRED_R1[$i]>$phred_max){ $phred_max=$POS_PHRED_R1[$i]; } foreach my $nt (@NTS){
if($POS_CALLS_R1{"$i-$nt"}<$callsR1_min){ $callsR1_min=$POS_CALLS_R1{"$i-$nt"}; }
if($POS_CALLS_R1{"$i-$nt"}>$callsR1_max){ $callsR1_max=$POS_CALLS_R1{"$i-$nt"}; } } }
for(my $i=0;$i<$num_POS_R2;$i++){ if($POS_PHRED_R2[$i]<$phred_min){ $phred_min=$POS_PHRED_R2[$i]; }
if($POS_PHRED_R2[$i]>$phred_max){ $phred_max=$POS_PHRED_R2[$i]; } foreach my $nt (@NTS){
if($POS_CALLS_R2{"$i-$nt"}<$callsR2_min){ $callsR2_min=$POS_CALLS_R2{"$i-$nt"}; }
if($POS_CALLS_R2{"$i-$nt"}>$callsR2_max){ $callsR2_max=$POS_CALLS_R2{"$i-$nt"}; } } }
$phred_min-=1; $phred_max+=1; while((($phred_max-$phred_min+1)/$phred_ytics)>16){
$phred_ytics++; } $callsR1_min-=0.1; if($callsR1_min<0){ $callsR1_min=0; }
$callsR1_max+=0.1; if($callsR1_max>1){ $callsR1_max=1; } $callsR2_min-=0.1;
if($callsR2_min<0){ $callsR2_min=0; } $callsR2_max+=0.1; if($callsR2_max>1){ $callsR2_max=1; }
if($callsR1_max<0.5){ $callsR1_max=0.5; } if($callsR2_max<0.5){ $callsR2_max=0.5; }

##########################################################################################
#                                                                                        #
#                                    Generating Plots                                    #
#                                                                                        #
##########################################################################################

# Generating Gnuplot Figure - PHRED Scores
if($verbose){ log_msg("  Generating plot for quality scores..."); } open(OUT,">$gnuplot_data");
for(my $i=0;$i<$max_pos;$i++){ if($POS_ID_R1[$i] ne ""){ if($POS_ID_R2[$i] ne ""){
if($POS_ID_R1[$i] ne $POS_ID_R2[$i]){ print "Inconsistent position ID.\n"; exit; } }
print OUT "$POS_ID_R1[$i]"; } else{ if($POS_ID_R2[$i] ne ""){ print OUT "$POS_ID_R2[$i]"; }
else{ print "Inconsistent position ID.\n"; exit; } } if($i<$num_POS_R1){
print OUT " $POS_PHRED_R1[$i]"; } else{ print OUT " ?"; } if($i<$num_POS_R2){
print OUT " $POS_PHRED_R2[$i]\n"; } else{ print OUT " ?\n"; } } close(OUT);
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
print OUT "plot \"$gnuplot_data\" using 1:2 with lines $c_blue lw 2 title \"READ 1\", ";
print OUT "\"$gnuplot_data\" using 1:3 with lines $c_red lw 2 title \"READ 2\"\n"; close(OUT);
`chmod 770 $gnuplot_data $gnuplot_source; $gdfont_export; gnuplot $gnuplot_source`;
`rm -rf $gnuplot_data $gnuplot_source; chmod 770 $gnuplot_phred_out`;

##########################################################################################

# Generating Gnuplot Figure - Base Composition READ 1
if($verbose){ log_msg("  Generating plot for base composition R1..."); }
open(OUT,">$gnuplot_data"); for(my $i=0;$i<$num_POS_R1;$i++){ print OUT "$POS_ID_R1[$i]";
foreach my $nt (@NTS){ print OUT " ".$POS_CALLS_R1{"$i-$nt"}; } print OUT "\n"; }
close(OUT); $title_lane3="Base Composition (READ 1)"; open(OUT,">$gnuplot_source");
print OUT "set term png size $plot_width,$plot_height $plot_font\n";
print OUT "set output \"$gnuplot_callsR1_out\"\n";
print OUT "set tmargin $tmargin\nset bmargin $bmargin\n";
print OUT "set title \"$title_lane1\\n$title_lane2\\n$title_lane3\" $title_font\n";
print OUT "set xrange [$pos_min:$pos_max]\n";
print OUT "set xtics $pos_xtics $xtics_font\n";
print OUT "set xtics nomirror\nset grid xtics\n";
print OUT "set xlabel \"$xlabel\" $xlabel_font\n";
print OUT "set label \"$copyright\" at $copyright_pos $copyright_font\n";
print OUT "set lmargin $calls_lmargin\nset rmargin $calls_rmargin\n";
print OUT "set yrange [$callsR1_min:$callsR1_max]\n";
print OUT "set ytics $callsR1_ytics $ytics_font\n";
print OUT "set ytics nomirror\nset grid ytics\n";
print OUT "set ylabel \"$calls_ylabel\" offset $calls_offset,0 $ylabel_font\n";
print OUT "plot \"$gnuplot_data\" using 1:2 with lines $c_blue lw 2 title \"A\", ";
print OUT "\"$gnuplot_data\" using 1:3 with lines $c_red lw 2 title \"C\", ";
print OUT "\"$gnuplot_data\" using 1:4 with lines $c_orange lw 2 title \"G\", ";
print OUT "\"$gnuplot_data\" using 1:5 with lines $c_lgreen lw 2 title \"T\", ";
print OUT "\"$gnuplot_data\" using 1:6 with lines $c_black lw 2 title \"N\"\n"; close(OUT);
`chmod 770 $gnuplot_data $gnuplot_source; $gdfont_export; gnuplot $gnuplot_source`;
`rm -rf $gnuplot_data $gnuplot_source; chmod 770 $gnuplot_callsR1_out`;

##########################################################################################

# Generating Gnuplot Figure - Base Composition READ 2
if($verbose){ log_msg("  Generating plot for base composition R2...\n"); }
open(OUT,">$gnuplot_data"); for(my $i=0;$i<$num_POS_R2;$i++){ print OUT "$POS_ID_R2[$i]";
foreach my $nt (@NTS){ print OUT " ".$POS_CALLS_R2{"$i-$nt"}; } print OUT "\n"; }
close(OUT); $title_lane3="Base Composition (READ 2)"; open(OUT,">$gnuplot_source");
print OUT "set term png size $plot_width,$plot_height $plot_font\n";
print OUT "set output \"$gnuplot_callsR2_out\"\n";
print OUT "set tmargin $tmargin\nset bmargin $bmargin\n";
print OUT "set title \"$title_lane1\\n$title_lane2\\n$title_lane3\" $title_font\n";
print OUT "set xrange [$pos_min:$pos_max]\n";
print OUT "set xtics $pos_xtics $xtics_font\n";
print OUT "set xtics nomirror\nset grid xtics\n";
print OUT "set xlabel \"$xlabel\" $xlabel_font\n";
print OUT "set label \"$copyright\" at $copyright_pos $copyright_font\n";
print OUT "set lmargin $calls_lmargin\nset rmargin $calls_rmargin\n";
print OUT "set yrange [$callsR2_min:$callsR2_max]\n";
print OUT "set ytics $callsR2_ytics $ytics_font\n";
print OUT "set ytics nomirror\nset grid ytics\n";
print OUT "set ylabel \"$calls_ylabel\" offset $calls_offset,0 $ylabel_font\n";
print OUT "plot \"$gnuplot_data\" using 1:2 with lines $c_blue lw 2 title \"A\", ";
print OUT "\"$gnuplot_data\" using 1:3 with lines $c_red lw 2 title \"C\", ";
print OUT "\"$gnuplot_data\" using 1:4 with lines $c_orange lw 2 title \"G\", ";
print OUT "\"$gnuplot_data\" using 1:5 with lines $c_lgreen lw 2 title \"T\", ";
print OUT "\"$gnuplot_data\" using 1:6 with lines $c_black lw 2 title \"N\"\n"; close(OUT);
`chmod 770 $gnuplot_data $gnuplot_source; $gdfont_export; gnuplot $gnuplot_source`;
`rm -rf $gnuplot_data $gnuplot_source; chmod 770 $gnuplot_callsR2_out`;

close($LOG_FH) if defined $LOG_FH;

##########################################################################################
#                                                                                        #
#                                       Functions                                        #
#                                                                                        #
##########################################################################################

# Format long integers for nicer display
sub format_int{ my $number=$_[0]; my @digits=split("",$number); my $form="";
my $count=0; for(my $i=$#digits;$i>=0;$i--){ $form=$digits[$i].$form; $count++;
if(($count==3)&&($i!=0)){ $count=0; $form=",".$form; } } return $form; }

sub log_msg {
    my ($msg) = @_;
    my $timestamp = strftime "%Y-%m-%d %H:%M:%S", localtime;
    print "[$timestamp] $msg\n";
    if (defined $LOG_FH) {
        print $LOG_FH "[$timestamp] $msg\n";
    }
}

