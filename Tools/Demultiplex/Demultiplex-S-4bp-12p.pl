#!/usr/bin/perl
use strict;

my $outP01="R45-L8-P01-AGGG-Sequences.txt"; my $outP02="R45-L8-P02-CCAT-Sequences.txt";
my $outP03="R45-L8-P03-GTCA-Sequences.txt"; my $outP04="R45-L8-P04-TATC-Sequences.txt";
my $outP05="R45-L8-P05-AAAA-Sequences.txt"; my $outP06="R45-L8-P06-CTGC-Sequences.txt";
my $outP07="R45-L8-P07-GCTG-Sequences.txt"; my $outP08="R45-L8-P08-TGCT-Sequences.txt";
my $outP09="R45-L8-P09-ATTT-Sequences.txt"; my $outP10="R45-L8-P10-CACG-Sequences.txt";
my $outP11="R45-L8-P11-GGAC-Sequences.txt"; my $outP12="R45-L8-P12-TCGA-Sequences.txt";
my $outPUN="R45-L8-PNotReco-Sequences.txt"; my $fastq="R45-L8-Sequences.txt";

my @seq=("AGGG","CCAT","GTCA","TATC","AAAA","CTGC","GCTG","TGCT","ATTT","CACG","GGAC","TCGA");
my @seq1=(".GGG",".CAT",".TCA",".ATC",".AAA",".TGC",".CTG",".GCT",".TTT",".ACG",".GAC",".CGA");
my @seq2=("A.GG","C.AT","G.CA","T.TC","A.AA","C.GC","G.TG","T.CT","A.TT","C.CG","G.AC","T.GA");
my @seq3=("AG.G","CC.T","GT.A","TA.C","AA.A","CT.C","GC.G","TG.T","AT.T","CA.G","GG.C","TC.A");
my @seq4=("AGG.","CCA.","GTC.","TAT.","AAA.","CTG.","GCT.","TGC.","ATT.","CAC.","GGA.","TCG.");

open(OUTP01,">$outP01") || die "Cannot open output file"; open(OUTP02,">$outP02") || die "Cannot open output file";
open(OUTP03,">$outP03") || die "Cannot open output file"; open(OUTP04,">$outP04") || die "Cannot open output file";
open(OUTP05,">$outP05") || die "Cannot open output file"; open(OUTP06,">$outP06") || die "Cannot open output file";
open(OUTP07,">$outP07") || die "Cannot open output file"; open(OUTP08,">$outP08") || die "Cannot open output file";
open(OUTP09,">$outP09") || die "Cannot open output file"; open(OUTP10,">$outP10") || die "Cannot open output file";
open(OUTP11,">$outP11") || die "Cannot open output file"; open(OUTP12,">$outP12") || die "Cannot open output file";
open(OUTPUN,">$outPUN") || die "Cannot open output file"; open(IN,$fastq) || die "Cannot open input file";

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
    if(($s40 eq $seq[9])&&($f==1)){  $Res[0]++; $Res[1]++; $f=0; print OUTP10 "$entS"; }
    if(($s40 eq $seq[10])&&($f==1)){ $Res[0]++; $Res[1]++; $f=0; print OUTP11 "$entS"; }
    if(($s40 eq $seq[11])&&($f==1)){ $Res[0]++; $Res[1]++; $f=0; print OUTP12 "$entS"; }

    if(($s40 =~ $seq1[0])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq1[1])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq1[2])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq1[3])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP04 "$entS"; }
    if(($s40 =~ $seq1[4])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP05 "$entS"; }
    if(($s40 =~ $seq1[5])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP06 "$entS"; }
    if(($s40 =~ $seq1[6])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP07 "$entS"; }
    if(($s40 =~ $seq1[7])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP08 "$entS"; }
    if(($s40 =~ $seq1[8])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP09 "$entS"; }
    if(($s40 =~ $seq1[9])&&($f==1)){  $Res[0]++; $Res[2]++; $f=0; print OUTP10 "$entS"; }
    if(($s40 =~ $seq1[10])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP11 "$entS"; }
    if(($s40 =~ $seq1[11])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP12 "$entS"; }

    if(($s40 =~ $seq2[0])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq2[1])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq2[2])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq2[3])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP04 "$entS"; }
    if(($s40 =~ $seq2[4])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP05 "$entS"; }
    if(($s40 =~ $seq2[5])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP06 "$entS"; }
    if(($s40 =~ $seq2[6])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP07 "$entS"; }
    if(($s40 =~ $seq2[7])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP08 "$entS"; }
    if(($s40 =~ $seq2[8])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP09 "$entS"; }
    if(($s40 =~ $seq2[9])&&($f==1)){  $Res[0]++; $Res[3]++; $f=0; print OUTP10 "$entS"; }
    if(($s40 =~ $seq2[10])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP11 "$entS"; }
    if(($s40 =~ $seq2[11])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP12 "$entS"; }

    if(($s40 =~ $seq3[0])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq3[1])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq3[2])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq3[3])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP04 "$entS"; }
    if(($s40 =~ $seq3[4])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP05 "$entS"; }
    if(($s40 =~ $seq3[5])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP06 "$entS"; }
    if(($s40 =~ $seq3[6])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP07 "$entS"; }
    if(($s40 =~ $seq3[7])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP08 "$entS"; }
    if(($s40 =~ $seq3[8])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP09 "$entS"; }
    if(($s40 =~ $seq3[9])&&($f==1)){  $Res[0]++; $Res[4]++; $f=0; print OUTP10 "$entS"; }
    if(($s40 =~ $seq3[10])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP11 "$entS"; }
    if(($s40 =~ $seq3[11])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP12 "$entS"; }

    if(($s40 =~ $seq4[0])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP01 "$entS"; }
    if(($s40 =~ $seq4[1])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP02 "$entS"; }
    if(($s40 =~ $seq4[2])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP03 "$entS"; }
    if(($s40 =~ $seq4[3])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP04 "$entS"; }
    if(($s40 =~ $seq4[4])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP05 "$entS"; }
    if(($s40 =~ $seq4[5])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP06 "$entS"; }
    if(($s40 =~ $seq4[6])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP07 "$entS"; }
    if(($s40 =~ $seq4[7])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP08 "$entS"; }
    if(($s40 =~ $seq4[8])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP09 "$entS"; }
    if(($s40 =~ $seq4[9])&&($f==1)){  $Res[0]++; $Res[5]++; $f=0; print OUTP10 "$entS"; }
    if(($s40 =~ $seq4[10])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP11 "$entS"; }
    if(($s40 =~ $seq4[11])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP12 "$entS"; }

    if($f==1){ print OUTPUN "$ent"; }
  }
}

close(OUTP01); close(OUTP02); close(OUTP03); close(OUTP04); close(OUTP05);
close(OUTP06); close(OUTP07); close(OUTP08); close(OUTP09); close(OUTP10);
close(OUTP11); close(OUTP12); close(OUTPUN); close(IN);

print "\n$num_seq sequences found in input\n$Res[0] sequences demultiplexed\n";
print "$Res[1] exact ".($Res[2]+$Res[3]+$Res[4]+$Res[5])." with one mismatch\n\n";
