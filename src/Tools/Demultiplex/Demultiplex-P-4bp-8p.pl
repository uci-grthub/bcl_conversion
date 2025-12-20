#!/usr/bin/perl
use strict;

my $fastqR1="R69-L6-READ1-Sequences.txt";         my $fastqR2="R69-L6-READ2-Sequences.txt";
my $outP1R1="R69-L6-P1-ACCC-READ1-Sequences.txt"; my $outP1R2="R69-L6-P1-ACCC-READ2-Sequences.txt";
my $outP2R1="R69-L6-P2-CGTA-READ1-Sequences.txt"; my $outP2R2="R69-L6-P2-CGTA-READ2-Sequences.txt";
my $outP3R1="R69-L6-P3-GAGT-READ1-Sequences.txt"; my $outP3R2="R69-L6-P3-GAGT-READ2-Sequences.txt";
my $outP4R1="R69-L6-P4-TTAG-READ1-Sequences.txt"; my $outP4R2="R69-L6-P4-TTAG-READ2-Sequences.txt";
my $outP5R1="R69-L6-P5-AGGG-READ1-Sequences.txt"; my $outP5R2="R69-L6-P5-AGGG-READ2-Sequences.txt";
my $outP6R1="R69-L6-P6-CCAT-READ1-Sequences.txt"; my $outP6R2="R69-L6-P6-CCAT-READ2-Sequences.txt";
my $outP7R1="R69-L6-P7-GTCA-READ1-Sequences.txt"; my $outP7R2="R69-L6-P7-GTCA-READ2-Sequences.txt";
my $outP8R1="R69-L6-P8-TATC-READ1-Sequences.txt"; my $outP8R2="R69-L6-P8-TATC-READ2-Sequences.txt";
my $outPUR1="R69-L6-POthers-READ1-Sequences.txt"; my $outPUR2="R69-L6-POthers-READ2-Sequences.txt";

my @seq=("ACCC","CGTA","GAGT","TTAG","AGGG","CCAT","GTCA","TATC");
my @seq1=(".CCC",".GTA",".AGT",".TAG",".GGG",".CAT",".TCA",".ATC");
my @seq2=("A.CC","C.TA","G.GT","T.AG","A.GG","C.AT","G.CA","T.TC");
my @seq3=("AC.C","CG.A","GA.T","TT.G","AG.G","CC.T","GT.A","TA.C");
my @seq4=("ACC.","CGT.","GAG.","TTA.","AGG.","CCA.","GTC.","TAT.");

open(IN1,$fastqR1) || die "Cannot open input file";         open(IN2,$fastqR2) || die "Cannot open input file";
open(OUTP1R1,">$outP1R1") || die "Cannot open output file"; open(OUTP1R2,">$outP1R2") || die "Cannot open output file";
open(OUTP2R1,">$outP2R1") || die "Cannot open output file"; open(OUTP2R2,">$outP2R2") || die "Cannot open output file";
open(OUTP3R1,">$outP3R1") || die "Cannot open output file"; open(OUTP3R2,">$outP3R2") || die "Cannot open output file";
open(OUTP4R1,">$outP4R1") || die "Cannot open output file"; open(OUTP4R2,">$outP4R2") || die "Cannot open output file";
open(OUTP5R1,">$outP5R1") || die "Cannot open output file"; open(OUTP5R2,">$outP5R2") || die "Cannot open output file";
open(OUTP6R1,">$outP6R1") || die "Cannot open output file"; open(OUTP6R2,">$outP6R2") || die "Cannot open output file";
open(OUTP7R1,">$outP7R1") || die "Cannot open output file"; open(OUTP7R2,">$outP7R2") || die "Cannot open output file";
open(OUTP8R1,">$outP8R1") || die "Cannot open output file"; open(OUTP8R2,">$outP8R2") || die "Cannot open output file";
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
    if(($s40 eq $seq[4])&&($f==1)){ $Res[0]++; $Res[1]++; $f=0; print OUTP5R1 "$entSR1"; print OUTP5R2 "$entR2"; }
    if(($s40 eq $seq[5])&&($f==1)){ $Res[0]++; $Res[1]++; $f=0; print OUTP6R1 "$entSR1"; print OUTP6R2 "$entR2"; }
    if(($s40 eq $seq[6])&&($f==1)){ $Res[0]++; $Res[1]++; $f=0; print OUTP7R1 "$entSR1"; print OUTP7R2 "$entR2"; }
    if(($s40 eq $seq[7])&&($f==1)){ $Res[0]++; $Res[1]++; $f=0; print OUTP8R1 "$entSR1"; print OUTP8R2 "$entR2"; }
    
    if(($s40 =~ $seq1[0])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP1R1 "$entSR1"; print OUTP1R2 "$entR2"; }
    if(($s40 =~ $seq1[1])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP2R1 "$entSR1"; print OUTP2R2 "$entR2"; }
    if(($s40 =~ $seq1[2])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP3R1 "$entSR1"; print OUTP3R2 "$entR2"; }
    if(($s40 =~ $seq1[3])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP4R1 "$entSR1"; print OUTP4R2 "$entR2"; }
    if(($s40 =~ $seq1[4])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP5R1 "$entSR1"; print OUTP5R2 "$entR2"; }
    if(($s40 =~ $seq1[5])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP6R1 "$entSR1"; print OUTP6R2 "$entR2"; }
    if(($s40 =~ $seq1[6])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP7R1 "$entSR1"; print OUTP7R2 "$entR2"; }
    if(($s40 =~ $seq1[7])&&($f==1)){ $Res[0]++; $Res[2]++; $f=0; print OUTP8R1 "$entSR1"; print OUTP8R2 "$entR2"; }
    
    if(($s40 =~ $seq2[0])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP1R1 "$entSR1"; print OUTP1R2 "$entR2"; }
    if(($s40 =~ $seq2[1])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP2R1 "$entSR1"; print OUTP2R2 "$entR2"; }
    if(($s40 =~ $seq2[2])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP3R1 "$entSR1"; print OUTP3R2 "$entR2"; }
    if(($s40 =~ $seq2[3])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP4R1 "$entSR1"; print OUTP4R2 "$entR2"; }
    if(($s40 =~ $seq2[4])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP5R1 "$entSR1"; print OUTP5R2 "$entR2"; }
    if(($s40 =~ $seq2[5])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP6R1 "$entSR1"; print OUTP6R2 "$entR2"; }
    if(($s40 =~ $seq2[6])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP7R1 "$entSR1"; print OUTP7R2 "$entR2"; }
    if(($s40 =~ $seq2[7])&&($f==1)){ $Res[0]++; $Res[3]++; $f=0; print OUTP8R1 "$entSR1"; print OUTP8R2 "$entR2"; }
    
    if(($s40 =~ $seq3[0])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP1R1 "$entSR1"; print OUTP1R2 "$entR2"; }
    if(($s40 =~ $seq3[1])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP2R1 "$entSR1"; print OUTP2R2 "$entR2"; }
    if(($s40 =~ $seq3[2])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP3R1 "$entSR1"; print OUTP3R2 "$entR2"; }
    if(($s40 =~ $seq3[3])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP4R1 "$entSR1"; print OUTP4R2 "$entR2"; }
    if(($s40 =~ $seq3[4])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP5R1 "$entSR1"; print OUTP5R2 "$entR2"; }
    if(($s40 =~ $seq3[5])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP6R1 "$entSR1"; print OUTP6R2 "$entR2"; }
    if(($s40 =~ $seq3[6])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP7R1 "$entSR1"; print OUTP7R2 "$entR2"; }
    if(($s40 =~ $seq3[7])&&($f==1)){ $Res[0]++; $Res[4]++; $f=0; print OUTP8R1 "$entSR1"; print OUTP8R2 "$entR2"; }
    
    if(($s40 =~ $seq4[0])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP1R1 "$entSR1"; print OUTP1R2 "$entR2"; }
    if(($s40 =~ $seq4[1])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP2R1 "$entSR1"; print OUTP2R2 "$entR2"; }
    if(($s40 =~ $seq4[2])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP3R1 "$entSR1"; print OUTP3R2 "$entR2"; }
    if(($s40 =~ $seq4[3])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP4R1 "$entSR1"; print OUTP4R2 "$entR2"; }
    if(($s40 =~ $seq4[4])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP5R1 "$entSR1"; print OUTP5R2 "$entR2"; }
    if(($s40 =~ $seq4[5])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP6R1 "$entSR1"; print OUTP6R2 "$entR2"; }
    if(($s40 =~ $seq4[6])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP7R1 "$entSR1"; print OUTP7R2 "$entR2"; }
    if(($s40 =~ $seq4[7])&&($f==1)){ $Res[0]++; $Res[5]++; $f=0; print OUTP8R1 "$entSR1"; print OUTP8R2 "$entR2"; }
    
    if($f==1){ print OUTPUR1 "$entR1"; print OUTPUR2 "$entR2"; }
  }
}

close(OUTP1R1); close(OUTP1R2); close(OUTP2R1); close(OUTP2R2); close(OUTP3R1); close(OUTP3R2); close(OUTP4R1); close(OUTP4R2);
close(OUTP5R1); close(OUTP5R2); close(OUTP6R1); close(OUTP6R2); close(OUTP7R1); close(OUTP7R2); close(OUTP8R1); close(OUTP8R2);
close(OUTPUR1); close(OUTPUR2); close(IN1); close(IN2);
print "\n$num_seq sequences found in input.\n\nResult Sequences   :\n".join("\t",@Res)."\n\n";

