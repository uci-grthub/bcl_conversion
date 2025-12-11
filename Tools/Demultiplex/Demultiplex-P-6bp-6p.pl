#!/usr/bin/perl
use strict;
use DBI;

my $fastqR1 ="R43-L8-READ1-Sequences.txt";            my $fastqR2 ="R43-L8-READ2-Sequences.txt";
my $outP01R1="R43-L8-P01-CACAGT-READ1-Sequences.txt"; my $outP01R2="R43-L8-P01-CACAGT-READ2-Sequences.txt";
my $outP02R1="R43-L8-P02-ATGGCT-READ1-Sequences.txt"; my $outP02R2="R43-L8-P02-ATGGCT-READ2-Sequences.txt";
my $outP03R1="R43-L8-P03-CGAGAT-READ1-Sequences.txt"; my $outP03R2="R43-L8-P03-CGAGAT-READ2-Sequences.txt";
my $outP04R1="R43-L8-P04-ACACTG-READ1-Sequences.txt"; my $outP04R2="R43-L8-P04-ACACTG-READ2-Sequences.txt";
my $outP05R1="R43-L8-P05-CATTCG-READ1-Sequences.txt"; my $outP05R2="R43-L8-P05-CATTCG-READ2-Sequences.txt";
my $outP06R1="R43-L8-P06-GCATAG-READ1-Sequences.txt"; my $outP06R2="R43-L8-P06-GCATAG-READ2-Sequences.txt";
my $outPUNR1="R43-L8-PrNotRecog-READ1-Sequences.txt"; my $outPUNR2="R43-L8-PrNotRecog-READ2-Sequences.txt";

my @s =("CACAGT","ATGGCT","CGAGAT","ACACTG","CATTCG","GCATAG");
my @s1=(".ACAGT",".TGGCT",".GAGAT",".CACTG",".ATTCG",".CATAG");
my @s2=("C.CAGT","A.GGCT","C.AGAT","A.ACTG","C.TTCG","G.ATAG");
my @s3=("CA.AGT","AT.GCT","CG.GAT","AC.CTG","CA.TCG","GC.TAG");
my @s4=("CAC.GT","ATG.CT","CGA.AT","ACA.TG","CAT.CG","GCA.AG");
my @s5=("CACA.T","ATGG.T","CGAG.T","ACAC.G","CATT.G","GCAT.G");
my @s6=("CACAG.","ATGGC.","CGAGA.","ACACT.","CATTC.","GCATA.");

open(IN1,$fastqR1) || die "Cannot open input file";           open(IN2,$fastqR2) || die "Cannot open input file";
open(OUTP01R1,">$outP01R1") || die "Cannot open output file"; open(OUTP01R2,">$outP01R2") || die "Cannot open output file";
open(OUTP02R1,">$outP02R1") || die "Cannot open output file"; open(OUTP02R2,">$outP02R2") || die "Cannot open output file";
open(OUTP03R1,">$outP03R1") || die "Cannot open output file"; open(OUTP03R2,">$outP03R2") || die "Cannot open output file";
open(OUTP04R1,">$outP04R1") || die "Cannot open output file"; open(OUTP04R2,">$outP04R2") || die "Cannot open output file";
open(OUTP05R1,">$outP05R1") || die "Cannot open output file"; open(OUTP05R2,">$outP05R2") || die "Cannot open output file";
open(OUTP06R1,">$outP06R1") || die "Cannot open output file"; open(OUTP06R2,">$outP06R2") || die "Cannot open output file";
open(OUTPUNR1,">$outPUNR1") || die "Cannot open output file"; open(OUTPUNR2,">$outPUNR2") || die "Cannot open output file";

my $l1; my $l2; my $num_seq=0; my @R=(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);

while(($l1=<IN1>)&&($l2=<IN2>))
{
  if(($l1 =~ /^@/)&&($l2 =~ /^@/))
  {
    my $h1R1=$l1; $l1=<IN1>; my $s1R1=$l1; $l1=<IN1>; my $h2R1=$l1; $l1=<IN1>; my $s2R1=$l1;
    my $h1R2=$l2; $l2=<IN2>; my $s1R2=$l2; $l2=<IN2>; my $h2R2=$l2; $l2=<IN2>; my $s2R2=$l2;
    chomp($h1R1); chomp($h1R2); chomp($h2R1); chomp($h2R2); chomp($s1R1); chomp($s1R2); chomp($s2R1); chomp($s2R2);
    my $entR1="$h1R1\n$s1R1\n$h2R1\n$s2R1\n"; my $entR2="$h1R2\n$s1R2\n$h2R2\n$s2R2\n";
    my $entSR1="$h1R1\n".substr($s1R1,7)."\n$h2R1\n".substr($s2R1,7)."\n";
    $num_seq++; my $s60=substr($s1R1,0,6); my $s61=substr($s1R1,1,6);  my $f=1;
    
    if(($s60 eq $s[0]) &&($f==1)){ $R[0]++; $R[1]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s60 eq $s[1]) &&($f==1)){ $R[0]++; $R[1]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s60 eq $s[2]) &&($f==1)){ $R[0]++; $R[1]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s60 eq $s[3]) &&($f==1)){ $R[0]++; $R[1]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s60 eq $s[4]) &&($f==1)){ $R[0]++; $R[1]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s60 eq $s[5]) &&($f==1)){ $R[0]++; $R[1]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s60 =~ $s1[0]) &&($f==1)){ $R[0]++; $R[2]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s60 =~ $s1[1]) &&($f==1)){ $R[0]++; $R[2]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s60 =~ $s1[2]) &&($f==1)){ $R[0]++; $R[2]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s60 =~ $s1[3]) &&($f==1)){ $R[0]++; $R[2]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s60 =~ $s1[4]) &&($f==1)){ $R[0]++; $R[2]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s60 =~ $s1[5]) &&($f==1)){ $R[0]++; $R[2]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s60 =~ $s2[0]) &&($f==1)){ $R[0]++; $R[3]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s60 =~ $s2[1]) &&($f==1)){ $R[0]++; $R[3]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s60 =~ $s2[2]) &&($f==1)){ $R[0]++; $R[3]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s60 =~ $s2[3]) &&($f==1)){ $R[0]++; $R[3]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s60 =~ $s2[4]) &&($f==1)){ $R[0]++; $R[3]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s60 =~ $s2[5]) &&($f==1)){ $R[0]++; $R[3]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s60 =~ $s3[0]) &&($f==1)){ $R[0]++; $R[4]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s60 =~ $s3[1]) &&($f==1)){ $R[0]++; $R[4]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s60 =~ $s3[2]) &&($f==1)){ $R[0]++; $R[4]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s60 =~ $s3[3]) &&($f==1)){ $R[0]++; $R[4]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s60 =~ $s3[4]) &&($f==1)){ $R[0]++; $R[4]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s60 =~ $s3[5]) &&($f==1)){ $R[0]++; $R[4]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s60 =~ $s4[0]) &&($f==1)){ $R[0]++; $R[5]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s60 =~ $s4[1]) &&($f==1)){ $R[0]++; $R[5]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s60 =~ $s4[2]) &&($f==1)){ $R[0]++; $R[5]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s60 =~ $s4[3]) &&($f==1)){ $R[0]++; $R[5]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s60 =~ $s4[4]) &&($f==1)){ $R[0]++; $R[5]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s60 =~ $s4[5]) &&($f==1)){ $R[0]++; $R[5]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s60 =~ $s5[0]) &&($f==1)){ $R[0]++; $R[6]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s60 =~ $s5[1]) &&($f==1)){ $R[0]++; $R[6]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s60 =~ $s5[2]) &&($f==1)){ $R[0]++; $R[6]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s60 =~ $s5[3]) &&($f==1)){ $R[0]++; $R[6]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s60 =~ $s5[4]) &&($f==1)){ $R[0]++; $R[6]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s60 =~ $s5[5]) &&($f==1)){ $R[0]++; $R[6]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s60 =~ $s6[0]) &&($f==1)){ $R[0]++; $R[7]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s60 =~ $s6[1]) &&($f==1)){ $R[0]++; $R[7]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s60 =~ $s6[2]) &&($f==1)){ $R[0]++; $R[7]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s60 =~ $s6[3]) &&($f==1)){ $R[0]++; $R[7]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s60 =~ $s6[4]) &&($f==1)){ $R[0]++; $R[7]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s60 =~ $s6[5]) &&($f==1)){ $R[0]++; $R[7]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s61 eq $s[0]) &&($f==1)){ $R[0]++; $R[8]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s61 eq $s[1]) &&($f==1)){ $R[0]++; $R[8]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s61 eq $s[2]) &&($f==1)){ $R[0]++; $R[8]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s61 eq $s[3]) &&($f==1)){ $R[0]++; $R[8]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s61 eq $s[4]) &&($f==1)){ $R[0]++; $R[8]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s61 eq $s[5]) &&($f==1)){ $R[0]++; $R[8]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s61 =~ $s1[0]) &&($f==1)){ $R[0]++; $R[9]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s61 =~ $s1[1]) &&($f==1)){ $R[0]++; $R[9]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s61 =~ $s1[2]) &&($f==1)){ $R[0]++; $R[9]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s61 =~ $s1[3]) &&($f==1)){ $R[0]++; $R[9]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s61 =~ $s1[4]) &&($f==1)){ $R[0]++; $R[9]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s61 =~ $s1[5]) &&($f==1)){ $R[0]++; $R[9]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s61 =~ $s2[0]) &&($f==1)){ $R[0]++; $R[10]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s61 =~ $s2[1]) &&($f==1)){ $R[0]++; $R[10]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s61 =~ $s2[2]) &&($f==1)){ $R[0]++; $R[10]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s61 =~ $s2[3]) &&($f==1)){ $R[0]++; $R[10]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s61 =~ $s2[4]) &&($f==1)){ $R[0]++; $R[10]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s61 =~ $s2[5]) &&($f==1)){ $R[0]++; $R[10]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s61 =~ $s3[0]) &&($f==1)){ $R[0]++; $R[11]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s61 =~ $s3[1]) &&($f==1)){ $R[0]++; $R[11]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s61 =~ $s3[2]) &&($f==1)){ $R[0]++; $R[11]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s61 =~ $s3[3]) &&($f==1)){ $R[0]++; $R[11]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s61 =~ $s3[4]) &&($f==1)){ $R[0]++; $R[11]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s61 =~ $s3[5]) &&($f==1)){ $R[0]++; $R[11]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s61 =~ $s4[0]) &&($f==1)){ $R[0]++; $R[12]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s61 =~ $s4[1]) &&($f==1)){ $R[0]++; $R[12]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s61 =~ $s4[2]) &&($f==1)){ $R[0]++; $R[12]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s61 =~ $s4[3]) &&($f==1)){ $R[0]++; $R[12]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s61 =~ $s4[4]) &&($f==1)){ $R[0]++; $R[12]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s61 =~ $s4[5]) &&($f==1)){ $R[0]++; $R[12]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s61 =~ $s5[0]) &&($f==1)){ $R[0]++; $R[13]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s61 =~ $s5[1]) &&($f==1)){ $R[0]++; $R[13]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s61 =~ $s5[2]) &&($f==1)){ $R[0]++; $R[13]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s61 =~ $s5[3]) &&($f==1)){ $R[0]++; $R[13]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s61 =~ $s5[4]) &&($f==1)){ $R[0]++; $R[13]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s61 =~ $s5[5]) &&($f==1)){ $R[0]++; $R[13]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if(($s61 =~ $s6[0]) &&($f==1)){ $R[0]++; $R[14]++; $f=0; print OUTP01R1 "$entSR1"; print OUTP01R2 "$entR2"; }
    if(($s61 =~ $s6[1]) &&($f==1)){ $R[0]++; $R[14]++; $f=0; print OUTP02R1 "$entSR1"; print OUTP02R2 "$entR2"; }
    if(($s61 =~ $s6[2]) &&($f==1)){ $R[0]++; $R[14]++; $f=0; print OUTP03R1 "$entSR1"; print OUTP03R2 "$entR2"; }
    if(($s61 =~ $s6[3]) &&($f==1)){ $R[0]++; $R[14]++; $f=0; print OUTP04R1 "$entSR1"; print OUTP04R2 "$entR2"; }
    if(($s61 =~ $s6[4]) &&($f==1)){ $R[0]++; $R[14]++; $f=0; print OUTP05R1 "$entSR1"; print OUTP05R2 "$entR2"; }
    if(($s61 =~ $s6[5]) &&($f==1)){ $R[0]++; $R[14]++; $f=0; print OUTP06R1 "$entSR1"; print OUTP06R2 "$entR2"; }

    if($f==1){ print OUTPUNR1 "$entR1"; print OUTPUNR2 "$entR2"; }
  }
}

close(OUTP01R1); close(OUTP01R2); close(OUTP02R1); close(OUTP02R2);
close(OUTP03R1); close(OUTP03R2); close(OUTP04R1); close(OUTP04R2);
close(OUTP05R1); close(OUTP05R2); close(OUTP06R1); close(OUTP06R2);
close(OUTPUNR1); close(OUTPUNR2); close(IN1);      close(IN2);

print "\n$num_seq sequences found in input.\n\nResult Sequences   :\n".join("\t",@R)."\n\n";

