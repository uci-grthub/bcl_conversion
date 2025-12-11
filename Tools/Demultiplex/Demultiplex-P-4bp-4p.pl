#!/usr/bin/perl
use strict;

my $fastqR1="R75-L7-READ1-Sequences.txt";         my $fastqR2="R75-L7-READ2-Sequences.txt";
my $outP1R1="R75-L7-P1-ACCC-READ1-Sequences.txt"; my $outP1R2="R75-L7-P1-ACCC-READ2-Sequences.txt";
my $outP2R1="R75-L7-P2-CGTA-READ1-Sequences.txt"; my $outP2R2="R75-L7-P2-CGTA-READ2-Sequences.txt";
my $outP3R1="R75-L7-P3-GAGT-READ1-Sequences.txt"; my $outP3R2="R75-L7-P3-GAGT-READ2-Sequences.txt";
my $outP4R1="R75-L7-P4-TTAG-READ1-Sequences.txt"; my $outP4R2="R75-L7-P4-TTAG-READ2-Sequences.txt";
my $outPUR1="R75-L7-PrNotRecog-READ1-Sequences.txt";
my $outPUR2="R75-L7-PrNotRecog-READ2-Sequences.txt";

my @seq =("ACCC","CGTA","GAGT","TTAG");
my @seq1=(".CCC",".GTA",".AGT",".TAG");
my @seq2=("A.CC","C.TA","G.GT","T.AG");
my @seq3=("AC.C","CG.A","GA.T","TT.G");
my @seq4=("ACC.","CGT.","GAG.","TTA.");

open(IN1,$fastqR1) || die "Cannot open input file";         open(IN2,$fastqR2) || die "Cannot open input file";
open(OUTP1R1,">$outP1R1") || die "Cannot open output file"; open(OUTP1R2,">$outP1R2") || die "Cannot open output file";
open(OUTP2R1,">$outP2R1") || die "Cannot open output file"; open(OUTP2R2,">$outP2R2") || die "Cannot open output file";
open(OUTP3R1,">$outP3R1") || die "Cannot open output file"; open(OUTP3R2,">$outP3R2") || die "Cannot open output file";
open(OUTP4R1,">$outP4R1") || die "Cannot open output file"; open(OUTP4R2,">$outP4R2") || die "Cannot open output file";
open(OUTPUR1,">$outPUR1") || die "Cannot open output file"; open(OUTPUR2,">$outPUR2") || die "Cannot open output file";

my $l1; my $l2; my $num_seq=0; my @Res=(0,0,0,0,0,0);
while(($l1=<IN1>)&&($l2=<IN2>))
{
  if(($l1 =~ /^@/)&&($l2 =~ /^@/))
  {
    my $h1R1=$l1; $l1=<IN1>; my $s1R1=$l1; $l1=<IN1>; my $h2R1=$l1; $l1=<IN1>; my $s2R1=$l1;
    my $h1R2=$l2; $l2=<IN2>; my $s1R2=$l2; $l2=<IN2>; my $h2R2=$l2; $l2=<IN2>; my $s2R2=$l2;
    chomp($h1R1); chomp($h1R2); chomp($h2R1); chomp($h2R2); chomp($s1R1); chomp($s1R2); chomp($s2R1); chomp($s2R2);
    my $entR1="$h1R1\n$s1R1\n$h2R1\n$s2R1\n"; my $entR2="$h1R2\n$s1R2\n$h2R2\n$s2R2\n";
    my $entSR1="$h1R1\n".substr($s1R1,4)."\n$h2R1\n".substr($s2R1,4)."\n";
    $num_seq++; my $s40=substr($s1R1,0,4); my $f=1;
    
    if(($s40 eq $seq[0])&&($f==1)){ $Res[0]++; $Res[1]++; $f=0; print OUTP1R1 "$entSR1"; print OUTP1R2 "$entR2"; }
    if(($s40 eq $seq[1])&&($f==1)){ $Res[0]++; $Res[1]++; $f=0; print OUTP2R1 "$entSR1"; print OUTP2R2 "$entR2"; }
    if(($s40 eq $seq[2])&&($f==1)){ $Res[0]++; $Res[1]++; $f=0; print OUTP3R1 "$entSR1"; print OUTP3R2 "$entR2"; }
    if(($s40 eq $seq[3])&&($f==1)){ $Res[0]++; $Res[1]++; $f=0; print OUTP4R1 "$entSR1"; print OUTP4R2 "$entR2"; }
    
    if(($s40 =~ $seq1[0])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP1R1 "$entSR1"; print OUTP1R2 "$entR2"; }
    if(($s40 =~ $seq1[1])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP2R1 "$entSR1"; print OUTP2R2 "$entR2"; }
    if(($s40 =~ $seq1[2])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP3R1 "$entSR1"; print OUTP3R2 "$entR2"; }
    if(($s40 =~ $seq1[3])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP4R1 "$entSR1"; print OUTP4R2 "$entR2"; }
    
    if(($s40 =~ $seq2[0])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP1R1 "$entSR1"; print OUTP1R2 "$entR2"; }
    if(($s40 =~ $seq2[1])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP2R1 "$entSR1"; print OUTP2R2 "$entR2"; }
    if(($s40 =~ $seq2[2])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP3R1 "$entSR1"; print OUTP3R2 "$entR2"; }
    if(($s40 =~ $seq2[3])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP4R1 "$entSR1"; print OUTP4R2 "$entR2"; }
    
    if(($s40 =~ $seq3[0])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP1R1 "$entSR1"; print OUTP1R2 "$entR2"; }
    if(($s40 =~ $seq3[1])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP2R1 "$entSR1"; print OUTP2R2 "$entR2"; }
    if(($s40 =~ $seq3[2])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP3R1 "$entSR1"; print OUTP3R2 "$entR2"; }
    if(($s40 =~ $seq3[3])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP4R1 "$entSR1"; print OUTP4R2 "$entR2"; }
    
    if(($s40 =~ $seq4[0])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP1R1 "$entSR1"; print OUTP1R2 "$entR2"; }
    if(($s40 =~ $seq4[1])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP2R1 "$entSR1"; print OUTP2R2 "$entR2"; }
    if(($s40 =~ $seq4[2])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP3R1 "$entSR1"; print OUTP3R2 "$entR2"; }
    if(($s40 =~ $seq4[3])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP4R1 "$entSR1"; print OUTP4R2 "$entR2"; }
    
    if($f==1){ print OUTPUR1 "$entR1"; print OUTPUR2 "$entR2"; }
  }
}

close(OUTP1R1); close(OUTP1R2); close(OUTP2R1); close(OUTP2R2); close(OUTP3R1); close(OUTP3R2); close(OUTP4R1); close(OUTP4R2);
close(OUTPUR1); close(OUTPUR2); close(IN1); close(IN2);
print "\n$num_seq sequences found in input.\n\nResult Sequences   :\n".join("\t",@Res)."\n\n";

