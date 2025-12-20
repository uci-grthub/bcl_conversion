#!/usr/bin/perl
use strict;

##########################################################################################
#                                                                                        #
#  Project     :  GHTFseq & HTSpro                                                       #
#  File        :  split_fastq_file.pl                                                    #
#  Description :  Split entries in a fastq file for CASAVA.                              #
#                                                                                        #
#  Author(s)   :  Christophe Magnan (cmagnan@ics.uci.edu)                                #
#  Copyright   :  Institute for Genomics and Bioinformatics                              #
#                 University of California, Irvine                                       #
#                                                                                        #
#  Created     :  2012/06/17                                                             #
#  Modified    :  2012/06/17                                                             #
#                                                                                        #
##########################################################################################

# Script Inputs
if($#ARGV!=2){ print "Wrong parameter. Exit.\n"; exit(1); }
my $fastq_file=$ARGV[0]; my $output_lane=$ARGV[1]; my $output_read=$ARGV[2];
if(! -f "$fastq_file"){ print "Fastq file not found. Exit.\n"; exit(1); }
if(($output_lane<1)||($output_lane>8)){ print "Invalid lane number.\n"; exit(1); }
if(($output_read!=1)&&($output_read!=2)){ print "Invalid read number.\n"; exit(1); }

# Parsing Fastq file
my $prefix="L${output_lane}_NoIndex_L00${output_lane}_R$output_read";
my $output_file="${prefix}_001.fastq"; my $batch=1; my $num_entries=0;
open(IN,"$fastq_file") || exit(1); open(OUT,">$output_file") || exit(1);
while(my $l=<IN>){ chomp($l); if($l =~ /^@/){ print OUT "$l\n";
$l=<IN>; print OUT "$l"; $l=<IN>; print OUT "$l"; $l=<IN>; print OUT "$l";
$num_entries++; if(($num_entries%10000000)==0){ close(OUT); $batch++;
if($batch<10){ $output_file="${prefix}_00${batch}.fastq"; } else{
$output_file="${prefix}_0${batch}.fastq"; } open(OUT,">$output_file"); } }
else{ print "Invalid Fastq file format.\n"; exit(1); } }
close(IN); close(OUT); print "Done! $num_entries sequences found.\n";

