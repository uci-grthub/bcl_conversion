#!/usr/bin/perl
use strict;

my $outPUN="mR125-L1-PrNotRecog-Sequences.txt"; my $outP01="mR125-L1-P01-CGATGT-Sequences.txt";
my $outP02="mR125-L1-P02-TGACCA-Sequences.txt"; my $outP03="mR125-L1-P03-ACAGTG-Sequences.txt";
my $outP04="mR125-L1-P04-GCCAAT-Sequences.txt"; my $outP05="mR125-L1-P05-CAGATC-Sequences.txt";
my $outP06="mR125-L1-P06-CTTGTA-Sequences.txt"; my $outP07="mR125-L1-P07-ATCACG-Sequences.txt";
my $outP08="mR125-L1-P08-TTAGGC-Sequences.txt"; my $outP09="mR125-L1-P09-ACTTGA-Sequences.txt";
my $outP10="mR125-L1-P10-GATCAG-Sequences.txt"; my $outP11="mR125-L1-P11-GTTTCG-Sequences.txt";

my @s =("CGATGT","TGACCA","ACAGTG","GCCAAT","CAGATC","CTTGTA","ATCACG","TTAGGC","ACTTGA","GATCAG","GTTTCG");
my @s1=(".GATGT",".GACCA",".CAGTG",".CCAAT",".AGATC",".TTGTA",".TCACG",".TAGGC",".CTTGA",".ATCAG",".TTTCG");
my @s2=("C.ATGT","T.ACCA","A.AGTG","G.CAAT","C.GATC","C.TGTA","A.CACG","T.AGGC","A.TTGA","G.TCAG","G.TTCG");
my @s3=("CG.TGT","TG.CCA","AC.GTG","GC.AAT","CA.ATC","CT.GTA","AT.ACG","TT.GGC","AC.TGA","GA.CAG","GT.TCG");
my @s4=("CGA.GT","TGA.CA","ACA.TG","GCC.AT","CAG.TC","CTT.TA","ATC.CG","TTA.GC","ACT.GA","GAT.AG","GTT.CG");
my @s5=("CGAT.T","TGAC.A","ACAG.G","GCCA.T","CAGA.C","CTTG.A","ATCA.G","TTAG.C","ACTT.A","GATC.G","GTTT.G");
my @s6=("CGATG.","TGACC.","ACAGT.","GCCAA.","CAGAT.","CTTGT.","ATCAC.","TTAGG.","ACTTG.","GATCA.","GTTTC.");

my $fastq="mR125-L1-Sequences.txt";                    open(IN,$fastq) || die "Cannot open input file";
open(PUN,">$outPUN") || die "Cannot open output file"; open(P01,">$outP01") || die "Cannot open output file";
open(P02,">$outP02") || die "Cannot open output file"; open(P03,">$outP03") || die "Cannot open output file";
open(P04,">$outP04") || die "Cannot open output file"; open(P05,">$outP05") || die "Cannot open output file";
open(P06,">$outP06") || die "Cannot open output file"; open(P07,">$outP07") || die "Cannot open output file";
open(P08,">$outP08") || die "Cannot open output file"; open(P09,">$outP09") || die "Cannot open output file";
open(P10,">$outP10") || die "Cannot open output file"; open(P11,">$outP11") || die "Cannot open output file";

my $l; my $num_seq=0; my @R=(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
while($l=<IN>){ if($l =~ /^@/){ my $h1=$l; chomp($h1); $l=<IN>; my $d1=$l; chomp($d1); $l=<IN>;
    my $h2=$l; chomp($h2); $l=<IN>; my $d2=$l; chomp($d2); my $ef="$h1\n$d1\n$h2\n$d2\n";
    my $es="$h1\n$d1\n$h2\n$d2\n"; $num_seq++; my $p=substr($d1,0,6); my $f=1;
    
    if(($p eq $s[0]) &&($f==1)){ $R[1]++; $f=0; print P01 $es; }
    if(($p eq $s[1]) &&($f==1)){ $R[1]++; $f=0; print P02 $es; }
    if(($p eq $s[2]) &&($f==1)){ $R[1]++; $f=0; print P03 $es; }
    if(($p eq $s[3]) &&($f==1)){ $R[1]++; $f=0; print P04 $es; }
    if(($p eq $s[4]) &&($f==1)){ $R[1]++; $f=0; print P05 $es; }
    if(($p eq $s[5]) &&($f==1)){ $R[1]++; $f=0; print P06 $es; }
    if(($p eq $s[6]) &&($f==1)){ $R[1]++; $f=0; print P07 $es; }
    if(($p eq $s[7]) &&($f==1)){ $R[1]++; $f=0; print P08 $es; }
    if(($p eq $s[8]) &&($f==1)){ $R[1]++; $f=0; print P09 $es; }
    if(($p eq $s[9]) &&($f==1)){ $R[1]++; $f=0; print P10 $es; }
    if(($p eq $s[10])&&($f==1)){ $R[1]++; $f=0; print P11 $es; }
    
    if(($p =~ $s1[0]) &&($f==1)){ $R[2]++; $f=0; print P01 $es; }
    if(($p =~ $s1[1]) &&($f==1)){ $R[2]++; $f=0; print P02 $es; }
    if(($p =~ $s1[2]) &&($f==1)){ $R[2]++; $f=0; print P03 $es; }
    if(($p =~ $s1[3]) &&($f==1)){ $R[2]++; $f=0; print P04 $es; }
    if(($p =~ $s1[4]) &&($f==1)){ $R[2]++; $f=0; print P05 $es; }
    if(($p =~ $s1[5]) &&($f==1)){ $R[2]++; $f=0; print P06 $es; }
    if(($p =~ $s1[6]) &&($f==1)){ $R[2]++; $f=0; print P07 $es; }
    if(($p =~ $s1[7]) &&($f==1)){ $R[2]++; $f=0; print P08 $es; }
    if(($p =~ $s1[8]) &&($f==1)){ $R[2]++; $f=0; print P09 $es; }
    if(($p =~ $s1[9]) &&($f==1)){ $R[2]++; $f=0; print P10 $es; }
    if(($p =~ $s1[10])&&($f==1)){ $R[2]++; $f=0; print P11 $es; }
    
    if(($p =~ $s2[0]) &&($f==1)){ $R[3]++; $f=0; print P01 $es; }
    if(($p =~ $s2[1]) &&($f==1)){ $R[3]++; $f=0; print P02 $es; }
    if(($p =~ $s2[2]) &&($f==1)){ $R[3]++; $f=0; print P03 $es; }
    if(($p =~ $s2[3]) &&($f==1)){ $R[3]++; $f=0; print P04 $es; }
    if(($p =~ $s2[4]) &&($f==1)){ $R[3]++; $f=0; print P05 $es; }
    if(($p =~ $s2[5]) &&($f==1)){ $R[3]++; $f=0; print P06 $es; }
    if(($p =~ $s2[6]) &&($f==1)){ $R[3]++; $f=0; print P07 $es; }
    if(($p =~ $s2[7]) &&($f==1)){ $R[3]++; $f=0; print P08 $es; }
    if(($p =~ $s2[8]) &&($f==1)){ $R[3]++; $f=0; print P09 $es; }
    if(($p =~ $s2[9]) &&($f==1)){ $R[3]++; $f=0; print P10 $es; }
    if(($p =~ $s2[10])&&($f==1)){ $R[3]++; $f=0; print P11 $es; }
    
    if(($p =~ $s3[0]) &&($f==1)){ $R[4]++; $f=0; print P01 $es; }
    if(($p =~ $s3[1]) &&($f==1)){ $R[4]++; $f=0; print P02 $es; }
    if(($p =~ $s3[2]) &&($f==1)){ $R[4]++; $f=0; print P03 $es; }
    if(($p =~ $s3[3]) &&($f==1)){ $R[4]++; $f=0; print P04 $es; }
    if(($p =~ $s3[4]) &&($f==1)){ $R[4]++; $f=0; print P05 $es; }
    if(($p =~ $s3[5]) &&($f==1)){ $R[4]++; $f=0; print P06 $es; }
    if(($p =~ $s3[6]) &&($f==1)){ $R[4]++; $f=0; print P07 $es; }
    if(($p =~ $s3[7]) &&($f==1)){ $R[4]++; $f=0; print P08 $es; }
    if(($p =~ $s3[8]) &&($f==1)){ $R[4]++; $f=0; print P09 $es; }
    if(($p =~ $s3[9]) &&($f==1)){ $R[4]++; $f=0; print P10 $es; }
    if(($p =~ $s3[10])&&($f==1)){ $R[4]++; $f=0; print P11 $es; }
    
    if(($p =~ $s4[0]) &&($f==1)){ $R[5]++; $f=0; print P01 $es; }
    if(($p =~ $s4[1]) &&($f==1)){ $R[5]++; $f=0; print P02 $es; }
    if(($p =~ $s4[2]) &&($f==1)){ $R[5]++; $f=0; print P03 $es; }
    if(($p =~ $s4[3]) &&($f==1)){ $R[5]++; $f=0; print P04 $es; }
    if(($p =~ $s4[4]) &&($f==1)){ $R[5]++; $f=0; print P05 $es; }
    if(($p =~ $s4[5]) &&($f==1)){ $R[5]++; $f=0; print P06 $es; }
    if(($p =~ $s4[6]) &&($f==1)){ $R[5]++; $f=0; print P07 $es; }
    if(($p =~ $s4[7]) &&($f==1)){ $R[5]++; $f=0; print P08 $es; }
    if(($p =~ $s4[8]) &&($f==1)){ $R[5]++; $f=0; print P09 $es; }
    if(($p =~ $s4[9]) &&($f==1)){ $R[5]++; $f=0; print P10 $es; }
    if(($p =~ $s4[10])&&($f==1)){ $R[5]++; $f=0; print P11 $es; }
    
    if(($p =~ $s5[0]) &&($f==1)){ $R[6]++; $f=0; print P01 $es; }
    if(($p =~ $s5[1]) &&($f==1)){ $R[6]++; $f=0; print P02 $es; }
    if(($p =~ $s5[2]) &&($f==1)){ $R[6]++; $f=0; print P03 $es; }
    if(($p =~ $s5[3]) &&($f==1)){ $R[6]++; $f=0; print P04 $es; }
    if(($p =~ $s5[4]) &&($f==1)){ $R[6]++; $f=0; print P05 $es; }
    if(($p =~ $s5[5]) &&($f==1)){ $R[6]++; $f=0; print P06 $es; }
    if(($p =~ $s5[6]) &&($f==1)){ $R[6]++; $f=0; print P07 $es; }
    if(($p =~ $s5[7]) &&($f==1)){ $R[6]++; $f=0; print P08 $es; }
    if(($p =~ $s5[8]) &&($f==1)){ $R[6]++; $f=0; print P09 $es; }
    if(($p =~ $s5[9]) &&($f==1)){ $R[6]++; $f=0; print P10 $es; }
    if(($p =~ $s5[10])&&($f==1)){ $R[6]++; $f=0; print P11 $es; }
    
    if(($p =~ $s6[0]) &&($f==1)){ $R[7]++; $f=0; print P01 $es; }
    if(($p =~ $s6[1]) &&($f==1)){ $R[7]++; $f=0; print P02 $es; }
    if(($p =~ $s6[2]) &&($f==1)){ $R[7]++; $f=0; print P03 $es; }
    if(($p =~ $s6[3]) &&($f==1)){ $R[7]++; $f=0; print P04 $es; }
    if(($p =~ $s6[4]) &&($f==1)){ $R[7]++; $f=0; print P05 $es; }
    if(($p =~ $s6[5]) &&($f==1)){ $R[7]++; $f=0; print P06 $es; }
    if(($p =~ $s6[6]) &&($f==1)){ $R[7]++; $f=0; print P07 $es; }
    if(($p =~ $s6[7]) &&($f==1)){ $R[7]++; $f=0; print P08 $es; }
    if(($p =~ $s6[8]) &&($f==1)){ $R[7]++; $f=0; print P09 $es; }
    if(($p =~ $s6[9]) &&($f==1)){ $R[7]++; $f=0; print P10 $es; }
    if(($p =~ $s6[10])&&($f==1)){ $R[7]++; $f=0; print P11 $es; }
    
    if($f==1){ print PUN $ef; } else{ $R[0]++; } } }

close(P01); close(P02); close(P03); close(P04); close(P05); close(P06); close(P07); close(P08);
close(P09); close(P10); close(P11); close(PUN); close(IN);
print "\n$num_seq sequences found in input.\n\nResult Sequences   :\n".join("\t",@R)."\n\n";

