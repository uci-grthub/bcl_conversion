#!/usr/bin/perl
use strict;

my $fastq="R95-L6-Sequences.txt";
my $outP01="R95-L6-P1-ACGTC-Sequences.txt";
my $outP02="R95-L6-P2-TGCAG-Sequences.txt";
my $outP03="R95-L6-P3-GATCA-Sequences.txt";
my $outP04="R95-L6-P4-CTAGT-Sequences.txt";
my $outPUN="R95-L6-PrNotRecog-Sequences.txt";

my @seq=("ACGTC","TGCAG","GATCA","CTAGT");
my @seq1=(".CGTC",".GCAG",".ATCA",".TAGT");
my @seq2=("A.GTC","T.CAG","G.TCA","C.AGT");
my @seq3=("AC.TC","TG.AG","GA.CA","CT.GT");
my @seq4=("ACG.C","TGC.G","GAT.A","CTA.T");
my @seq5=("ACGT.","TGCA.","GATC.","CTAG.");

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
    my $entS="$h1\n".substr($s1,5)."\n$h2\n".substr($s2,5)."\n";
    $num_seq++; my $s40=substr($s1,0,5); my $f=1;

    if(($s40 eq $seq[0])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 eq $seq[1])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 eq $seq[2])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 eq $seq[3])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP04 "$entS"; }

    if(($s40 =~ $seq1[0])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq1[1])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq1[2])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq1[3])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP04 "$entS"; }

    if(($s40 =~ $seq2[0])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq2[1])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq2[2])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq2[3])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP04 "$entS"; }

    if(($s40 =~ $seq3[0])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq3[1])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq3[2])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq3[3])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP04 "$entS"; }

    if(($s40 =~ $seq4[0])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq4[1])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq4[2])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq4[3])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP04 "$entS"; }

    if(($s40 =~ $seq5[0])&&($f==1)){  $Res[0]++; $Res[6]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq5[1])&&($f==1)){  $Res[0]++; $Res[6]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq5[2])&&($f==1)){  $Res[0]++; $Res[6]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq5[3])&&($f==1)){  $Res[0]++; $Res[6]++; $f=0; print OUTP04 "$entS"; }

    if($f==1){ print OUTPUN "$ent"; }
  }
}

close(OUTP01); close(OUTP02); close(OUTP03); close(OUTP04); close(OUTPUN); close(IN);
print "\n$num_seq sequences found in input\n$Res[0] sequences demultiplexed\n";
print "$Res[1] exact ".($Res[2]+$Res[3]+$Res[4]+$Res[5]+$Res[6])." with one mismatch\n\n";
