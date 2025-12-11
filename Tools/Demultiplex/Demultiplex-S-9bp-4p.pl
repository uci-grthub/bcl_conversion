#!/usr/bin/perl
use strict;

my $fastq="R98-L1-Sequences.txt";
my $outP01="R98-L1-P1-ACGTCCTAT-Sequences.txt";
my $outP02="R98-L1-P2-TGCAGCTAT-Sequences.txt";
my $outP03="R98-L1-P3-GATCACTAT-Sequences.txt";
my $outP04="R98-L1-P4-CTAGTCTAT-Sequences.txt";
my $outPUN="R98-L1-PrNotRecog-Sequences.txt";

my @seq=("ACGTCCTAT","TGCAGCTAT","GATCACTAT","CTAGTCTAT");

open(OUTP01,">$outP01") || die "Cannot open output file";
open(OUTP02,">$outP02") || die "Cannot open output file";
open(OUTP03,">$outP03") || die "Cannot open output file";
open(OUTP04,">$outP04") || die "Cannot open output file";
open(OUTPUN,">$outPUN") || die "Cannot open output file";
open(IN,$fastq) || die "Cannot open input file";
my $l; my $num_seq=0; my @Res=(0,0,0,0,0,0,0);

while($l=<IN>)
{
  if($l =~ /^@/)
  {
    my $h1=$l; $l=<IN>; my $s1=$l; $l=<IN>; my $h2=$l; $l=<IN>; my $s2=$l;
    chomp($h1); chomp($h2); chomp($s1); chomp($s2); my $ent="$h1\n$s1\n$h2\n$s2\n";
    my $entS="$h1\n".substr($s1,9)."\n$h2\n".substr($s2,9)."\n";
    $num_seq++; my $s40=substr($s1,0,9); my $f=1;
    
    if(($s40 eq $seq[0])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 eq $seq[1])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 eq $seq[2])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 eq $seq[3])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP04 "$entS"; }

    if($f==1){ print OUTPUN "$ent"; }
  }
}

close(OUTP01); close(OUTP02); close(OUTP03); close(OUTP04); close(OUTPUN); close(IN);
print "\n$num_seq sequences found in input\n$Res[0] sequences demultiplexed\n";
print "$Res[1] exact ".($Res[2]+$Res[3]+$Res[4]+$Res[5]+$Res[6])." with one mismatch\n\n";
