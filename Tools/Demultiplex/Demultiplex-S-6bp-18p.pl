#!/usr/bin/perl
use strict;
use DBI;

my $fastq="lane1_Undetermined_L001_R1_001.fastq"; my $outPUN="R154-L1-PrNotRecog-Sequences.txt";
my $outP01="R154-L1-P03-AGCAAT-Sequences.txt";    my $outP02="R154-L1-P04-CCTGTT-Sequences.txt";
my $outP03="R154-L1-P05-GGGTTT-Sequences.txt";    my $outP04="R154-L1-P06-GAAGGC-Sequences.txt";
my $outP05="R154-L1-P07-ATCTCA-Sequences.txt";    my $outP06="R154-L1-P08-ATGGAT-Sequences.txt";
my $outP07="R154-L1-P09-ATGTCT-Sequences.txt";    my $outP08="R154-L1-P10-CGTGAC-Sequences.txt";
my $outP09="R154-L1-P11-TTAGGT-Sequences.txt";    my $outP10="R154-L1-P12-GTGCAT-Sequences.txt";
my $outP11="R154-L1-P13-AACTTT-Sequences.txt";    my $outP12="R154-L1-P14-GGATCG-Sequences.txt";
my $outP13="R154-L1-P15-ATAAGG-Sequences.txt";    my $outP14="R154-L1-P16-ATTGGT-Sequences.txt";
my $outP15="R154-L1-P17-AGTGAG-Sequences.txt";    my $outP16="R154-L1-P18-CCCACC-Sequences.txt";
my $outP17="R154-L1-P19-CGATGC-Sequences.txt";    my $outP18="R154-L1-P20-GATAGC-Sequences.txt";

my @s =("AGCAAT","CCTGTT","GGGTTT","GAAGGC","ATCTCA","ATGGAT","ATGTCT","CGTGAC","TTAGGT","GTGCAT","AACTTT","GGATCG","ATAAGG","ATTGGT","AGTGAG","CCCACC","CGATGC","GATAGC");
my @s1=(".GCAAT",".CTGTT",".GGTTT",".AAGGC",".TCTCA",".TGGAT",".TGTCT",".GTGAC",".TAGGT",".TGCAT",".ACTTT",".GATCG",".TAAGG",".TTGGT",".GTGAG",".CCACC",".GATGC",".ATAGC");
my @s2=("A.CAAT","C.TGTT","G.GTTT","G.AGGC","A.CTCA","A.GGAT","A.GTCT","C.TGAC","T.AGGT","G.GCAT","A.CTTT","G.ATCG","A.AAGG","A.TGGT","A.TGAG","C.CACC","C.ATGC","G.TAGC");
my @s3=("AG.AAT","CC.GTT","GG.TTT","GA.GGC","AT.TCA","AT.GAT","AT.TCT","CG.GAC","TT.GGT","GT.CAT","AA.TTT","GG.TCG","AT.AGG","AT.GGT","AG.GAG","CC.ACC","CG.TGC","GA.AGC");
my @s4=("AGC.AT","CCT.TT","GGG.TT","GAA.GC","ATC.CA","ATG.AT","ATG.CT","CGT.AC","TTA.GT","GTG.AT","AAC.TT","GGA.CG","ATA.GG","ATT.GT","AGT.AG","CCC.CC","CGA.GC","GAT.GC");
my @s5=("AGCA.T","CCTG.T","GGGT.T","GAAG.C","ATCT.A","ATGG.T","ATGT.T","CGTG.C","TTAG.T","GTGC.T","AACT.T","GGAT.G","ATAA.G","ATTG.T","AGTG.G","CCCA.C","CGAT.C","GATA.C");
my @s6=("AGCAA.","CCTGT.","GGGTT.","GAAGG.","ATCTC.","ATGGA.","ATGTC.","CGTGA.","TTAGG.","GTGCA.","AACTT.","GGATC.","ATAAG.","ATTGG.","AGTGA.","CCCAC.","CGATG.","GATAG.");

open(IN,$fastq) || die "Cannot open input file"; open(PUN,">$outPUN") || die "Cannot open output file";
open(P01,">$outP01") || die "Cannot open output file"; open(P02,">$outP02") || die "Cannot open output file";
open(P03,">$outP03") || die "Cannot open output file"; open(P04,">$outP04") || die "Cannot open output file";
open(P05,">$outP05") || die "Cannot open output file"; open(P06,">$outP06") || die "Cannot open output file";
open(P07,">$outP07") || die "Cannot open output file"; open(P08,">$outP08") || die "Cannot open output file";
open(P09,">$outP09") || die "Cannot open output file"; open(P10,">$outP10") || die "Cannot open output file";
open(P11,">$outP11") || die "Cannot open output file"; open(P12,">$outP12") || die "Cannot open output file";
open(P13,">$outP13") || die "Cannot open output file"; open(P14,">$outP14") || die "Cannot open output file";
open(P15,">$outP15") || die "Cannot open output file"; open(P16,">$outP16") || die "Cannot open output file";
open(P17,">$outP17") || die "Cannot open output file"; open(P18,">$outP18") || die "Cannot open output file";

my $l; my $num_seq=0; my @R=(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
while($l=<IN>)
{ if($l =~ /^@/)
  {
    my $h1=$l; chomp($h1); $l=<IN>; my $d1=$l; chomp($d1); $l=<IN>; my $h2=$l; chomp($h2); $l=<IN>; my $d2=$l; chomp($d2);
    my $ef="$h1\n$d1\n$h2\n$d2\n"; my $es="$h1\n".substr($d1,6)."\n$h2\n".substr($d2,6)."\n";
    $num_seq++; my $p=substr($d1,0,6); my $f=1;
    
    if(($p eq $s[0]) &&($f==1)){ $R[1]++; $f=0; print P01 $es; } if(($p eq $s[1]) &&($f==1)){ $R[1]++; $f=0; print P02 $es; }
    if(($p eq $s[2]) &&($f==1)){ $R[1]++; $f=0; print P03 $es; } if(($p eq $s[3]) &&($f==1)){ $R[1]++; $f=0; print P04 $es; }
    if(($p eq $s[4]) &&($f==1)){ $R[1]++; $f=0; print P05 $es; } if(($p eq $s[5]) &&($f==1)){ $R[1]++; $f=0; print P06 $es; }
    if(($p eq $s[6]) &&($f==1)){ $R[1]++; $f=0; print P07 $es; } if(($p eq $s[7]) &&($f==1)){ $R[1]++; $f=0; print P08 $es; }
    if(($p eq $s[8]) &&($f==1)){ $R[1]++; $f=0; print P09 $es; } if(($p eq $s[9]) &&($f==1)){ $R[1]++; $f=0; print P10 $es; }
    if(($p eq $s[10])&&($f==1)){ $R[1]++; $f=0; print P11 $es; } if(($p eq $s[11])&&($f==1)){ $R[1]++; $f=0; print P12 $es; }
    if(($p eq $s[12])&&($f==1)){ $R[1]++; $f=0; print P13 $es; } if(($p eq $s[13])&&($f==1)){ $R[1]++; $f=0; print P14 $es; }
    if(($p eq $s[14])&&($f==1)){ $R[1]++; $f=0; print P15 $es; } if(($p eq $s[15])&&($f==1)){ $R[1]++; $f=0; print P16 $es; }
    if(($p eq $s[16])&&($f==1)){ $R[1]++; $f=0; print P17 $es; } if(($p eq $s[17])&&($f==1)){ $R[1]++; $f=0; print P18 $es; }
    
    if(($p =~ $s1[0]) &&($f==1)){ $R[2]++; $f=0; print P01 $es; } if(($p =~ $s1[1]) &&($f==1)){ $R[2]++; $f=0; print P02 $es; }
    if(($p =~ $s1[2]) &&($f==1)){ $R[2]++; $f=0; print P03 $es; } if(($p =~ $s1[3]) &&($f==1)){ $R[2]++; $f=0; print P04 $es; }
    if(($p =~ $s1[4]) &&($f==1)){ $R[2]++; $f=0; print P05 $es; } if(($p =~ $s1[5]) &&($f==1)){ $R[2]++; $f=0; print P06 $es; }
    if(($p =~ $s1[6]) &&($f==1)){ $R[2]++; $f=0; print P07 $es; } if(($p =~ $s1[7]) &&($f==1)){ $R[2]++; $f=0; print P08 $es; }
    if(($p =~ $s1[8]) &&($f==1)){ $R[2]++; $f=0; print P09 $es; } if(($p =~ $s1[9]) &&($f==1)){ $R[2]++; $f=0; print P10 $es; }
    if(($p =~ $s1[10])&&($f==1)){ $R[2]++; $f=0; print P11 $es; } if(($p =~ $s1[11])&&($f==1)){ $R[2]++; $f=0; print P12 $es; }
    if(($p =~ $s1[12])&&($f==1)){ $R[2]++; $f=0; print P13 $es; } if(($p =~ $s1[13])&&($f==1)){ $R[2]++; $f=0; print P14 $es; }
    if(($p =~ $s1[14])&&($f==1)){ $R[2]++; $f=0; print P15 $es; } if(($p =~ $s1[15])&&($f==1)){ $R[2]++; $f=0; print P16 $es; }
    if(($p =~ $s1[16])&&($f==1)){ $R[2]++; $f=0; print P17 $es; } if(($p =~ $s1[17])&&($f==1)){ $R[2]++; $f=0; print P18 $es; }
    
    if(($p =~ $s2[0]) &&($f==1)){ $R[3]++; $f=0; print P01 $es; } if(($p =~ $s2[1]) &&($f==1)){ $R[3]++; $f=0; print P02 $es; }
    if(($p =~ $s2[2]) &&($f==1)){ $R[3]++; $f=0; print P03 $es; } if(($p =~ $s2[3]) &&($f==1)){ $R[3]++; $f=0; print P04 $es; }
    if(($p =~ $s2[4]) &&($f==1)){ $R[3]++; $f=0; print P05 $es; } if(($p =~ $s2[5]) &&($f==1)){ $R[3]++; $f=0; print P06 $es; }
    if(($p =~ $s2[6]) &&($f==1)){ $R[3]++; $f=0; print P07 $es; } if(($p =~ $s2[7]) &&($f==1)){ $R[3]++; $f=0; print P08 $es; }
    if(($p =~ $s2[8]) &&($f==1)){ $R[3]++; $f=0; print P09 $es; } if(($p =~ $s2[9]) &&($f==1)){ $R[3]++; $f=0; print P10 $es; }
    if(($p =~ $s2[10])&&($f==1)){ $R[3]++; $f=0; print P11 $es; } if(($p =~ $s2[11])&&($f==1)){ $R[3]++; $f=0; print P12 $es; }
    if(($p =~ $s2[12])&&($f==1)){ $R[3]++; $f=0; print P13 $es; } if(($p =~ $s2[13])&&($f==1)){ $R[3]++; $f=0; print P14 $es; }
    if(($p =~ $s2[14])&&($f==1)){ $R[3]++; $f=0; print P15 $es; } if(($p =~ $s2[15])&&($f==1)){ $R[3]++; $f=0; print P16 $es; }
    if(($p =~ $s2[16])&&($f==1)){ $R[3]++; $f=0; print P17 $es; } if(($p =~ $s2[17])&&($f==1)){ $R[3]++; $f=0; print P18 $es; }
    
    if(($p =~ $s3[0]) &&($f==1)){ $R[4]++; $f=0; print P01 $es; } if(($p =~ $s3[1]) &&($f==1)){ $R[4]++; $f=0; print P02 $es; }
    if(($p =~ $s3[2]) &&($f==1)){ $R[4]++; $f=0; print P03 $es; } if(($p =~ $s3[3]) &&($f==1)){ $R[4]++; $f=0; print P04 $es; }
    if(($p =~ $s3[4]) &&($f==1)){ $R[4]++; $f=0; print P05 $es; } if(($p =~ $s3[5]) &&($f==1)){ $R[4]++; $f=0; print P06 $es; }
    if(($p =~ $s3[6]) &&($f==1)){ $R[4]++; $f=0; print P07 $es; } if(($p =~ $s3[7]) &&($f==1)){ $R[4]++; $f=0; print P08 $es; }
    if(($p =~ $s3[8]) &&($f==1)){ $R[4]++; $f=0; print P09 $es; } if(($p =~ $s3[9]) &&($f==1)){ $R[4]++; $f=0; print P10 $es; }
    if(($p =~ $s3[10])&&($f==1)){ $R[4]++; $f=0; print P11 $es; } if(($p =~ $s3[11])&&($f==1)){ $R[4]++; $f=0; print P12 $es; }
    if(($p =~ $s3[12])&&($f==1)){ $R[4]++; $f=0; print P13 $es; } if(($p =~ $s3[13])&&($f==1)){ $R[4]++; $f=0; print P14 $es; }
    if(($p =~ $s3[14])&&($f==1)){ $R[4]++; $f=0; print P15 $es; } if(($p =~ $s3[15])&&($f==1)){ $R[4]++; $f=0; print P16 $es; }
    if(($p =~ $s3[16])&&($f==1)){ $R[4]++; $f=0; print P17 $es; } if(($p =~ $s3[17])&&($f==1)){ $R[4]++; $f=0; print P18 $es; }
    
    if(($p =~ $s4[0]) &&($f==1)){ $R[5]++; $f=0; print P01 $es; } if(($p =~ $s4[1]) &&($f==1)){ $R[5]++; $f=0; print P02 $es; }
    if(($p =~ $s4[2]) &&($f==1)){ $R[5]++; $f=0; print P03 $es; } if(($p =~ $s4[3]) &&($f==1)){ $R[5]++; $f=0; print P04 $es; }
    if(($p =~ $s4[4]) &&($f==1)){ $R[5]++; $f=0; print P05 $es; } if(($p =~ $s4[5]) &&($f==1)){ $R[5]++; $f=0; print P06 $es; }
    if(($p =~ $s4[6]) &&($f==1)){ $R[5]++; $f=0; print P07 $es; } if(($p =~ $s4[7]) &&($f==1)){ $R[5]++; $f=0; print P08 $es; }
    if(($p =~ $s4[8]) &&($f==1)){ $R[5]++; $f=0; print P09 $es; } if(($p =~ $s4[9]) &&($f==1)){ $R[5]++; $f=0; print P10 $es; }
    if(($p =~ $s4[10])&&($f==1)){ $R[5]++; $f=0; print P11 $es; } if(($p =~ $s4[11])&&($f==1)){ $R[5]++; $f=0; print P12 $es; }
    if(($p =~ $s4[12])&&($f==1)){ $R[5]++; $f=0; print P13 $es; } if(($p =~ $s4[13])&&($f==1)){ $R[5]++; $f=0; print P14 $es; }
    if(($p =~ $s4[14])&&($f==1)){ $R[5]++; $f=0; print P15 $es; } if(($p =~ $s4[15])&&($f==1)){ $R[5]++; $f=0; print P16 $es; }
    if(($p =~ $s4[16])&&($f==1)){ $R[5]++; $f=0; print P17 $es; } if(($p =~ $s4[17])&&($f==1)){ $R[5]++; $f=0; print P18 $es; }
    
    if(($p =~ $s5[0]) &&($f==1)){ $R[6]++; $f=0; print P01 $es; } if(($p =~ $s5[1]) &&($f==1)){ $R[6]++; $f=0; print P02 $es; }
    if(($p =~ $s5[2]) &&($f==1)){ $R[6]++; $f=0; print P03 $es; } if(($p =~ $s5[3]) &&($f==1)){ $R[6]++; $f=0; print P04 $es; }
    if(($p =~ $s5[4]) &&($f==1)){ $R[6]++; $f=0; print P05 $es; } if(($p =~ $s5[5]) &&($f==1)){ $R[6]++; $f=0; print P06 $es; }
    if(($p =~ $s5[6]) &&($f==1)){ $R[6]++; $f=0; print P07 $es; } if(($p =~ $s5[7]) &&($f==1)){ $R[6]++; $f=0; print P08 $es; }
    if(($p =~ $s5[8]) &&($f==1)){ $R[6]++; $f=0; print P09 $es; } if(($p =~ $s5[9]) &&($f==1)){ $R[6]++; $f=0; print P10 $es; }
    if(($p =~ $s5[10])&&($f==1)){ $R[6]++; $f=0; print P11 $es; } if(($p =~ $s5[11])&&($f==1)){ $R[6]++; $f=0; print P12 $es; }
    if(($p =~ $s5[12])&&($f==1)){ $R[6]++; $f=0; print P13 $es; } if(($p =~ $s5[13])&&($f==1)){ $R[6]++; $f=0; print P14 $es; }
    if(($p =~ $s5[14])&&($f==1)){ $R[6]++; $f=0; print P15 $es; } if(($p =~ $s5[15])&&($f==1)){ $R[6]++; $f=0; print P16 $es; }
    if(($p =~ $s5[16])&&($f==1)){ $R[6]++; $f=0; print P17 $es; } if(($p =~ $s5[17])&&($f==1)){ $R[6]++; $f=0; print P18 $es; }
    
    if(($p =~ $s6[0]) &&($f==1)){ $R[7]++; $f=0; print P01 $es; } if(($p =~ $s6[1]) &&($f==1)){ $R[7]++; $f=0; print P02 $es; }
    if(($p =~ $s6[2]) &&($f==1)){ $R[7]++; $f=0; print P03 $es; } if(($p =~ $s6[3]) &&($f==1)){ $R[7]++; $f=0; print P04 $es; }
    if(($p =~ $s6[4]) &&($f==1)){ $R[7]++; $f=0; print P05 $es; } if(($p =~ $s6[5]) &&($f==1)){ $R[7]++; $f=0; print P06 $es; }
    if(($p =~ $s6[6]) &&($f==1)){ $R[7]++; $f=0; print P07 $es; } if(($p =~ $s6[7]) &&($f==1)){ $R[7]++; $f=0; print P08 $es; }
    if(($p =~ $s6[8]) &&($f==1)){ $R[7]++; $f=0; print P09 $es; } if(($p =~ $s6[9]) &&($f==1)){ $R[7]++; $f=0; print P10 $es; }
    if(($p =~ $s6[10])&&($f==1)){ $R[7]++; $f=0; print P11 $es; } if(($p =~ $s6[11])&&($f==1)){ $R[7]++; $f=0; print P12 $es; }
    if(($p =~ $s6[12])&&($f==1)){ $R[7]++; $f=0; print P13 $es; } if(($p =~ $s6[13])&&($f==1)){ $R[7]++; $f=0; print P14 $es; }
    if(($p =~ $s6[14])&&($f==1)){ $R[7]++; $f=0; print P15 $es; } if(($p =~ $s6[15])&&($f==1)){ $R[7]++; $f=0; print P16 $es; }
    if(($p =~ $s6[16])&&($f==1)){ $R[7]++; $f=0; print P17 $es; } if(($p =~ $s6[17])&&($f==1)){ $R[7]++; $f=0; print P18 $es; }
    
    if($f==1){ print PUN $ef; } else{ $R[0]++; }
  }
}

close(P01); close(P02); close(P03); close(P04); close(P05); close(P06); close(P07); close(P08);
close(P09); close(P10); close(P11); close(P12); close(P13); close(P14); close(P15); close(P16);
close(P17); close(P18); close(PUN); close(IN);

print "\n$num_seq sequences found in input.\n\nResult Sequences   :\n".join("\t",@R)."\n\n";

