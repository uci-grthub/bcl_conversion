#!/usr/bin/perl
use strict;

my $outP01="nR013-L2-P1-GGCG-Sequences.txt";
my $outP02="nR013-L2-P2-GGTC-Sequences.txt";
my $outP03="nR013-L2-P3-CGGA-Sequences.txt";
my $outP04="nR013-L2-P4-TTAG-Sequences.txt";
my $outP05="nR013-L2-P5-CCGG-Sequences.txt";
my $outP06="nR013-L2-P6-CAAT-Sequences.txt";
my $outP07="nR013-L2-P7-TGGC-Sequences.txt";
my $outPUN="nR013-L2-PrNotRecog-Sequences.txt";
my $fastq="nR013-L2-Sequences.txt";
my @seq=("GGCG","GGTC","CGGA","TTAG","CCGG","CAAT","TGGC");

open(OUTP01,">$outP01") || die "Cannot open output file";
open(OUTP02,">$outP02") || die "Cannot open output file";
open(OUTP03,">$outP03") || die "Cannot open output file";
open(OUTP04,">$outP04") || die "Cannot open output file";
open(OUTP05,">$outP05") || die "Cannot open output file";
open(OUTP06,">$outP06") || die "Cannot open output file";
open(OUTP07,">$outP07") || die "Cannot open output file";
open(OUTPUN,">$outPUN") || die "Cannot open output file";
open(IN,$fastq) || die "Cannot open input file";

my $l; my $num_seq=0; my @Res=(0,0,0,0,0,0);
while($l=<IN>){ if($l =~ /^@/){
    
    my $h1=$l; $l=<IN>; my $s1=$l; $l=<IN>; my $h2=$l; $l=<IN>; my $s2=$l;
    chomp($h1); chomp($h2); chomp($s1); chomp($s2); my $ent="$h1\n$s1\n$h2\n$s2\n";
    my $entS="$h1\n".substr($s1,7)."\n$h2\n".substr($s2,7)."\n";
    $num_seq++; my $s40=substr($s1,3,4); my $f=1;
    
    if(($s40 eq $seq[0])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 eq $seq[1])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 eq $seq[2])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 eq $seq[3])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP04 "$entS"; }
    if(($s40 eq $seq[4])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP05 "$entS"; }
    if(($s40 eq $seq[5])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP06 "$entS"; }
    if(($s40 eq $seq[6])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP07 "$entS"; }
    
    if($f==1){ print OUTPUN "$ent"; } } } close(OUTP01); close(OUTP02); close(OUTP03);
close(OUTP04); close(OUTP05); close(OUTP06); close(OUTP07); close(OUTPUN); close(IN);
print "\n$num_seq sequences found in input\n$Res[0] sequences demultiplexed\n\n";

