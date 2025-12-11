#!/usr/bin/perl
use strict;

my $fastq="R106-L1-Sequences.txt";
my $outP01="R106-L1-P1-TGCA-Sequences.txt";
my $outP02="R106-L1-P2-GTAC-Sequences.txt";
my $outP03="R106-L1-P3-CATG-Sequences.txt";
my $outP04="R106-L1-P4-ACTG-Sequences.txt";
my $outP05="R106-L1-P5-TGCT-Sequences.txt";
my $outP06="R106-L1-P6-CAGA-Sequences.txt";
my $outP07="R106-L1-P7-ACGT-Sequences.txt";
my $outP08="R106-L1-P8-AGTC-Sequences.txt";
my $outP09="R106-L1-P9-GACT-Sequences.txt";
my $outPUN="R106-L1-PrNotRecog-Sequences.txt";

my @seq =("TGCA","GTAC","CATG","ACTG","TGCT","CAGA","ACGT","AGTC","GACT");
my @seq1=(".GCA",".TAC",".ATG",".CTG",".GCT",".AGA",".CGT",".GTC",".ACT");
my @seq2=("T.CA","G.AC","C.TG","A.TG","T.CT","C.GA","A.GT","A.TC","G.CT");
my @seq3=("TG.A","GT.C","CA.G","AC.G","TG.T","CA.A","AC.T","AG.C","GA.T");
my @seq4=("TGC.","GTA.","CAT.","ACT.","TGC.","CAG.","ACG.","AGT.","GAC.");

open(OUTP01,">$outP01") || die "Cannot open output file";
open(OUTP02,">$outP02") || die "Cannot open output file";
open(OUTP03,">$outP03") || die "Cannot open output file";
open(OUTP04,">$outP04") || die "Cannot open output file";
open(OUTP05,">$outP05") || die "Cannot open output file";
open(OUTP06,">$outP06") || die "Cannot open output file";
open(OUTP07,">$outP07") || die "Cannot open output file";
open(OUTP08,">$outP08") || die "Cannot open output file";
open(OUTP09,">$outP09") || die "Cannot open output file";
open(OUTPUN,">$outPUN") || die "Cannot open output file";
open(IN,$fastq) || die "Cannot open input file";

my $l; my $num_seq=0; my @Res=(0,0,0,0,0,0);

while($l=<IN>)
{
  if($l =~ /^@/)
  {
    my $h1=$l; $l=<IN>; my $s1=$l; $l=<IN>; my $h2=$l; $l=<IN>; my $s2=$l;
    chomp($h1); chomp($h2); chomp($s1); chomp($s2); my $ent="$h1\n$s1\n$h2\n$s2\n";
    my $entS="$h1\n".substr($s1,4)."\n$h2\n".substr($s2,4)."\n";
    $num_seq++; my $s40=substr($s1,0,4); my $f=1;
    
    if(($s40 eq $seq[0])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 eq $seq[1])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 eq $seq[2])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 eq $seq[3])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP04 "$entS"; }
    if(($s40 eq $seq[4])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP05 "$entS"; }
    if(($s40 eq $seq[5])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP06 "$entS"; }
    if(($s40 eq $seq[6])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP07 "$entS"; }
    if(($s40 eq $seq[7])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP08 "$entS"; }
    if(($s40 eq $seq[8])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP09 "$entS"; }

    if(($s40 =~ $seq1[0])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq1[1])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq1[2])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq1[3])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP04 "$entS"; }
    if(($s40 =~ $seq1[4])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP05 "$entS"; }
    if(($s40 =~ $seq1[5])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP06 "$entS"; }
    if(($s40 =~ $seq1[6])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP07 "$entS"; }
    if(($s40 =~ $seq1[7])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP08 "$entS"; }
    if(($s40 =~ $seq1[8])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP09 "$entS"; }

    if(($s40 =~ $seq2[0])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq2[1])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq2[2])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq2[3])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP04 "$entS"; }
    if(($s40 =~ $seq2[4])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP05 "$entS"; }
    if(($s40 =~ $seq2[5])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP06 "$entS"; }
    if(($s40 =~ $seq2[6])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP07 "$entS"; }
    if(($s40 =~ $seq2[7])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP08 "$entS"; }
    if(($s40 =~ $seq2[8])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP09 "$entS"; }

    if(($s40 =~ $seq3[0])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq3[1])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq3[2])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq3[3])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP04 "$entS"; }
    if(($s40 =~ $seq3[4])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP05 "$entS"; }
    if(($s40 =~ $seq3[5])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP06 "$entS"; }
    if(($s40 =~ $seq3[6])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP07 "$entS"; }
    if(($s40 =~ $seq3[7])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP08 "$entS"; }
    if(($s40 =~ $seq3[8])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP09 "$entS"; }

    if(($s40 =~ $seq4[0])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq4[1])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq4[2])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq4[3])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP04 "$entS"; }
    if(($s40 =~ $seq4[4])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP05 "$entS"; }
    if(($s40 =~ $seq4[5])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP06 "$entS"; }
    if(($s40 =~ $seq4[6])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP07 "$entS"; }
    if(($s40 =~ $seq4[7])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP08 "$entS"; }
    if(($s40 =~ $seq4[8])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP09 "$entS"; }

    if($f==1){ print OUTPUN "$ent"; }
  }
}

close(OUTP01); close(OUTP02); close(OUTP03); close(OUTP04); close(OUTP05);
close(OUTP06); close(OUTP07); close(OUTP08); close(OUTP09); close(OUTPUN); close(IN);

print "\n$num_seq sequences found in input\n$Res[0] sequences demultiplexed\n";
print "$Res[1] exact ".($Res[2]+$Res[3]+$Res[4]+$Res[5])." with one mismatch\n\n";
