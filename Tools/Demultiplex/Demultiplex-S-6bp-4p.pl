#!/usr/bin/perl
use strict;
use DBI;

my $fastq="R42-L7-READ1-Sequences.txt";     my $outPUN="R42-L7-PrNotRecog-Sequences.txt";
my $outP1="R42-L7-P1-ATCACG-Sequences.txt"; my $outP2="R42-L7-P2-CGATGT-Sequences.txt";
my $outP3="R42-L7-P3-TTAGGC-Sequences.txt"; my $outP4="R42-L7-P4-TGACCA-Sequences.txt";

my @s=("ATCACG","CGATGT","TTAGGC","TGACCA");
my @s1=(".TCACG",".GATGT",".TAGGC",".GACCA");
my @s2=("A.CACG","C.ATGT","T.AGGC","T.ACCA");
my @s3=("AT.ACG","CG.TGT","TT.GGC","TG.CCA");
my @s4=("ATC.CG","CGA.GT","TTA.GC","TGA.CA");
my @s5=("ATCA.G","CGAT.T","TTAG.C","TGAC.A");
my @s6=("ATCAC.","CGATG.","TTAGG.","TGACC.");

open(IN,$fastq) || die "Cannot open input file"; open(PUN,">$outPUN") || die "Cannot open output file";
open(P01,">$outP1") || die "Cannot open output file"; open(P02,">$outP2") || die "Cannot open output file";
open(P03,">$outP3") || die "Cannot open output file"; open(P04,">$outP4") || die "Cannot open output file";

my $l; my $num_seq=0; my @R=(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
while($l=<IN>)
{ if($l =~ /^@/)
  {
    my $h1=$l; chomp($h1); $l=<IN>; my $d1=$l; chomp($d1); $l=<IN>; my $h2=$l; chomp($h2); $l=<IN>; my $d2=$l; chomp($d2);
    my $ef="$h1\n$d1\n$h2\n$d2\n"; my $es="$h1\n".substr($d1,7)."\n$h2\n".substr($d2,7)."\n";
    $num_seq++; my $p=substr($d1,0,6); my $q=substr($d1,1,6); my $f=1;

    if(($p eq $s[0]) &&($f==1)){ $R[1]++; $f=0; print P01 $es; } if(($p eq $s[1]) &&($f==1)){ $R[1]++; $f=0; print P02 $es; }
    if(($p eq $s[2]) &&($f==1)){ $R[1]++; $f=0; print P03 $es; } if(($p eq $s[3]) &&($f==1)){ $R[1]++; $f=0; print P04 $es; }
    if(($p =~ $s1[0]) &&($f==1)){ $R[2]++; $f=0; print P01 $es; } if(($p =~ $s1[1]) &&($f==1)){ $R[2]++; $f=0; print P02 $es; }
    if(($p =~ $s1[2]) &&($f==1)){ $R[2]++; $f=0; print P03 $es; } if(($p =~ $s1[3]) &&($f==1)){ $R[2]++; $f=0; print P04 $es; }
    if(($p =~ $s2[0]) &&($f==1)){ $R[3]++; $f=0; print P01 $es; } if(($p =~ $s2[1]) &&($f==1)){ $R[3]++; $f=0; print P02 $es; }
    if(($p =~ $s2[2]) &&($f==1)){ $R[3]++; $f=0; print P03 $es; } if(($p =~ $s2[3]) &&($f==1)){ $R[3]++; $f=0; print P04 $es; }
    if(($p =~ $s3[0]) &&($f==1)){ $R[4]++; $f=0; print P01 $es; } if(($p =~ $s3[1]) &&($f==1)){ $R[4]++; $f=0; print P02 $es; }
    if(($p =~ $s3[2]) &&($f==1)){ $R[4]++; $f=0; print P03 $es; } if(($p =~ $s3[3]) &&($f==1)){ $R[4]++; $f=0; print P04 $es; }
    if(($p =~ $s4[0]) &&($f==1)){ $R[5]++; $f=0; print P01 $es; } if(($p =~ $s4[1]) &&($f==1)){ $R[5]++; $f=0; print P02 $es; }
    if(($p =~ $s4[2]) &&($f==1)){ $R[5]++; $f=0; print P03 $es; } if(($p =~ $s4[3]) &&($f==1)){ $R[5]++; $f=0; print P04 $es; }
    if(($p =~ $s5[0]) &&($f==1)){ $R[6]++; $f=0; print P01 $es; } if(($p =~ $s5[1]) &&($f==1)){ $R[6]++; $f=0; print P02 $es; }
    if(($p =~ $s5[2]) &&($f==1)){ $R[6]++; $f=0; print P03 $es; } if(($p =~ $s5[3]) &&($f==1)){ $R[6]++; $f=0; print P04 $es; }
    if(($p =~ $s6[0]) &&($f==1)){ $R[7]++; $f=0; print P01 $es; } if(($p =~ $s6[1]) &&($f==1)){ $R[7]++; $f=0; print P02 $es; }
    if(($p =~ $s6[2]) &&($f==1)){ $R[7]++; $f=0; print P03 $es; } if(($p =~ $s6[3]) &&($f==1)){ $R[7]++; $f=0; print P04 $es; }
    
    if(($q eq $s[0]) &&($f==1)){ $R[8]++; $f=0; print P01 $es; } if(($q eq $s[1]) &&($f==1)){ $R[8]++; $f=0; print P02 $es; }
    if(($q eq $s[2]) &&($f==1)){ $R[8]++; $f=0; print P03 $es; } if(($q eq $s[3]) &&($f==1)){ $R[8]++; $f=0; print P04 $es; }
    if(($q =~ $s1[0]) &&($f==1)){ $R[9]++; $f=0; print P01 $es; } if(($q =~ $s1[1]) &&($f==1)){ $R[9]++; $f=0; print P02 $es; }
    if(($q =~ $s1[2]) &&($f==1)){ $R[9]++; $f=0; print P03 $es; } if(($q =~ $s1[3]) &&($f==1)){ $R[9]++; $f=0; print P04 $es; }
    if(($q =~ $s2[0]) &&($f==1)){ $R[10]++; $f=0; print P01 $es; } if(($q =~ $s2[1]) &&($f==1)){ $R[10]++; $f=0; print P02 $es; }
    if(($q =~ $s2[2]) &&($f==1)){ $R[10]++; $f=0; print P03 $es; } if(($q =~ $s2[3]) &&($f==1)){ $R[10]++; $f=0; print P04 $es; }
    if(($q =~ $s3[0]) &&($f==1)){ $R[11]++; $f=0; print P01 $es; } if(($q =~ $s3[1]) &&($f==1)){ $R[11]++; $f=0; print P02 $es; }
    if(($q =~ $s3[2]) &&($f==1)){ $R[11]++; $f=0; print P03 $es; } if(($q =~ $s3[3]) &&($f==1)){ $R[11]++; $f=0; print P04 $es; }
    if(($q =~ $s4[0]) &&($f==1)){ $R[12]++; $f=0; print P01 $es; } if(($q =~ $s4[1]) &&($f==1)){ $R[12]++; $f=0; print P02 $es; }
    if(($q =~ $s4[2]) &&($f==1)){ $R[12]++; $f=0; print P03 $es; } if(($q =~ $s4[3]) &&($f==1)){ $R[12]++; $f=0; print P04 $es; }
    if(($q =~ $s5[0]) &&($f==1)){ $R[13]++; $f=0; print P01 $es; } if(($q =~ $s5[1]) &&($f==1)){ $R[13]++; $f=0; print P02 $es; }
    if(($q =~ $s5[2]) &&($f==1)){ $R[13]++; $f=0; print P03 $es; } if(($q =~ $s5[3]) &&($f==1)){ $R[13]++; $f=0; print P04 $es; }
    if(($q =~ $s6[0]) &&($f==1)){ $R[14]++; $f=0; print P01 $es; } if(($q =~ $s6[1]) &&($f==1)){ $R[14]++; $f=0; print P02 $es; }
    if(($q =~ $s6[2]) &&($f==1)){ $R[14]++; $f=0; print P03 $es; } if(($q =~ $s6[3]) &&($f==1)){ $R[14]++; $f=0; print P04 $es; }
    
    if($f==1){ print PUN $ef; } else{ $R[0]++; }
  }
}

close(P01); close(P02); close(P03); close(P04); close(PUN); close(IN);
print "\n$num_seq sequences found in input.\n\nResult Sequences   :\n".join("\t",@R)."\n\n";

