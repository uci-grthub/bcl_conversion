#!/usr/bin/perl
use strict;
use DBI;

my $fastq="R42-L6-READ1-Sequences.txt";       my $outPUN="R42-L6-PrNotRecog-Sequences.txt";
my $outP01="R42-L6-P01-CGATGT-Sequences.txt"; my $outP02="R42-L6-P02-TGACCA-Sequences.txt";
my $outP03="R42-L6-P03-ACAGTG-Sequences.txt"; my $outP04="R42-L6-P04-GCCAAT-Sequences.txt";
my $outP05="R42-L6-P05-CAGATC-Sequences.txt"; my $outP06="R42-L6-P06-CTTGTA-Sequences.txt";
my $outP07="R42-L6-P07-ATCACG-Sequences.txt"; my $outP08="R42-L6-P08-TTAGGC-Sequences.txt";
my $outP09="R42-L6-P09-ACTTGA-Sequences.txt"; my $outP10="R42-L6-P10-GATCAG-Sequences.txt";
my $outP11="R42-L6-P11-TAGCTT-Sequences.txt"; my $outP12="R42-L6-P12-GGCTAC-Sequences.txt";
my $outP13="R42-L6-P13-AGTCAA-Sequences.txt"; my $outP14="R42-L6-P14-AGTTCC-Sequences.txt";
my $outP15="R42-L6-P15-ATGTCA-Sequences.txt"; my $outP16="R42-L6-P16-CCGTCC-Sequences.txt";
my $outP17="R42-L6-P17-GTAGAG-Sequences.txt"; my $outP18="R42-L6-P18-GTCCGC-Sequences.txt";
my $outP19="R42-L6-P19-GTGAAA-Sequences.txt"; my $outP20="R42-L6-P20-GTGGCC-Sequences.txt";
my $outP21="R42-L6-P21-GTTTCG-Sequences.txt"; my $outP22="R42-L6-P22-CGTACG-Sequences.txt";
my $outP23="R42-L6-P23-GAGTGG-Sequences.txt"; my $outP24="R42-L6-P24-GGTAGC-Sequences.txt";

my @s=("CGATGT","TGACCA","ACAGTG","GCCAAT","CAGATC","CTTGTA","ATCACG","TTAGGC","ACTTGA","GATCAG","TAGCTT","GGCTAC","AGTCAA","AGTTCC","ATGTCA","CCGTCC","GTAGAG","GTCCGC","GTGAAA","GTGGCC","GTTTCG","CGTACG","GAGTGG","GGTAGC");
my @s1=(".GATGT",".GACCA",".CAGTG",".CCAAT",".AGATC",".TTGTA",".TCACG",".TAGGC",".CTTGA",".ATCAG",".AGCTT",".GCTAC",".GTCAA",".GTTCC",".TGTCA",".CGTCC",".TAGAG",".TCCGC",".TGAAA",".TGGCC",".TTTCG",".GTACG",".AGTGG",".GTAGC");
my @s2=("C.ATGT","T.ACCA","A.AGTG","G.CAAT","C.GATC","C.TGTA","A.CACG","T.AGGC","A.TTGA","G.TCAG","T.GCTT","G.CTAC","A.TCAA","A.TTCC","A.GTCA","C.GTCC","G.AGAG","G.CCGC","G.GAAA","G.GGCC","G.TTCG","C.TACG","G.GTGG","G.TAGC");
my @s3=("CG.TGT","TG.CCA","AC.GTG","GC.AAT","CA.ATC","CT.GTA","AT.ACG","TT.GGC","AC.TGA","GA.CAG","TA.CTT","GG.TAC","AG.CAA","AG.TCC","AT.TCA","CC.TCC","GT.GAG","GT.CGC","GT.AAA","GT.GCC","GT.TCG","CG.ACG","GA.TGG","GG.AGC");
my @s4=("CGA.GT","TGA.CA","ACA.TG","GCC.AT","CAG.TC","CTT.TA","ATC.CG","TTA.GC","ACT.GA","GAT.AG","TAG.TT","GGC.AC","AGT.AA","AGT.CC","ATG.CA","CCG.CC","GTA.AG","GTC.GC","GTG.AA","GTG.CC","GTT.CG","CGT.CG","GAG.GG","GGT.GC");
my @s5=("CGAT.T","TGAC.A","ACAG.G","GCCA.T","CAGA.C","CTTG.A","ATCA.G","TTAG.C","ACTT.A","GATC.G","TAGC.T","GGCT.C","AGTC.A","AGTT.C","ATGT.A","CCGT.C","GTAG.G","GTCC.C","GTGA.A","GTGG.C","GTTT.G","CGTA.G","GAGT.G","GGTA.C");
my @s6=("CGATG.","TGACC.","ACAGT.","GCCAA.","CAGAT.","CTTGT.","ATCAC.","TTAGG.","ACTTG.","GATCA.","TAGCT.","GGCTA.","AGTCA.","AGTTC.","ATGTC.","CCGTC.","GTAGA.","GTCCG.","GTGAA.","GTGGC.","GTTTC.","CGTAC.","GAGTG.","GGTAG.");

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
open(P19,">$outP19") || die "Cannot open output file"; open(P20,">$outP20") || die "Cannot open output file";
open(P21,">$outP21") || die "Cannot open output file"; open(P22,">$outP22") || die "Cannot open output file";
open(P23,">$outP23") || die "Cannot open output file"; open(P24,">$outP24") || die "Cannot open output file";

my $l; my $num_seq=0; my @R=(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
while($l=<IN>)
{ if($l =~ /^@/)
  {
    my $h1=$l; chomp($h1); $l=<IN>; my $d1=$l; chomp($d1); $l=<IN>; my $h2=$l; chomp($h2); $l=<IN>; my $d2=$l; chomp($d2);
    my $ef="$h1\n$d1\n$h2\n$d2\n"; my $es="$h1\n".substr($d1,7)."\n$h2\n".substr($d2,7)."\n";
    $num_seq++; my $p=substr($d1,0,6); my $q=substr($d1,1,6); my $f=1;
    
    if(($p eq $s[0]) &&($f==1)){ $R[1]++; $f=0; print P01 $es; } if(($p eq $s[1]) &&($f==1)){ $R[1]++; $f=0; print P02 $es; }
    if(($p eq $s[2]) &&($f==1)){ $R[1]++; $f=0; print P03 $es; } if(($p eq $s[3]) &&($f==1)){ $R[1]++; $f=0; print P04 $es; }
    if(($p eq $s[4]) &&($f==1)){ $R[1]++; $f=0; print P05 $es; } if(($p eq $s[5]) &&($f==1)){ $R[1]++; $f=0; print P06 $es; }
    if(($p eq $s[6]) &&($f==1)){ $R[1]++; $f=0; print P07 $es; } if(($p eq $s[7]) &&($f==1)){ $R[1]++; $f=0; print P08 $es; }
    if(($p eq $s[8]) &&($f==1)){ $R[1]++; $f=0; print P09 $es; } if(($p eq $s[9]) &&($f==1)){ $R[1]++; $f=0; print P10 $es; }
    if(($p eq $s[10])&&($f==1)){ $R[1]++; $f=0; print P11 $es; } if(($p eq $s[11])&&($f==1)){ $R[1]++; $f=0; print P12 $es; }
    if(($p eq $s[12])&&($f==1)){ $R[1]++; $f=0; print P13 $es; } if(($p eq $s[13])&&($f==1)){ $R[1]++; $f=0; print P14 $es; }
    if(($p eq $s[14])&&($f==1)){ $R[1]++; $f=0; print P15 $es; } if(($p eq $s[15])&&($f==1)){ $R[1]++; $f=0; print P16 $es; }
    if(($p eq $s[16])&&($f==1)){ $R[1]++; $f=0; print P17 $es; } if(($p eq $s[17])&&($f==1)){ $R[1]++; $f=0; print P18 $es; }
    if(($p eq $s[18])&&($f==1)){ $R[1]++; $f=0; print P19 $es; } if(($p eq $s[19])&&($f==1)){ $R[1]++; $f=0; print P20 $es; }
    if(($p eq $s[20])&&($f==1)){ $R[1]++; $f=0; print P21 $es; } if(($p eq $s[21])&&($f==1)){ $R[1]++; $f=0; print P22 $es; }
    if(($p eq $s[22])&&($f==1)){ $R[1]++; $f=0; print P23 $es; } if(($p eq $s[23])&&($f==1)){ $R[1]++; $f=0; print P24 $es; }
    
    if(($p =~ $s1[0]) &&($f==1)){ $R[2]++; $f=0; print P01 $es; } if(($p =~ $s1[1]) &&($f==1)){ $R[2]++; $f=0; print P02 $es; }
    if(($p =~ $s1[2]) &&($f==1)){ $R[2]++; $f=0; print P03 $es; } if(($p =~ $s1[3]) &&($f==1)){ $R[2]++; $f=0; print P04 $es; }
    if(($p =~ $s1[4]) &&($f==1)){ $R[2]++; $f=0; print P05 $es; } if(($p =~ $s1[5]) &&($f==1)){ $R[2]++; $f=0; print P06 $es; }
    if(($p =~ $s1[6]) &&($f==1)){ $R[2]++; $f=0; print P07 $es; } if(($p =~ $s1[7]) &&($f==1)){ $R[2]++; $f=0; print P08 $es; }
    if(($p =~ $s1[8]) &&($f==1)){ $R[2]++; $f=0; print P09 $es; } if(($p =~ $s1[9]) &&($f==1)){ $R[2]++; $f=0; print P10 $es; }
    if(($p =~ $s1[10])&&($f==1)){ $R[2]++; $f=0; print P11 $es; } if(($p =~ $s1[11])&&($f==1)){ $R[2]++; $f=0; print P12 $es; }
    if(($p =~ $s1[12])&&($f==1)){ $R[2]++; $f=0; print P13 $es; } if(($p =~ $s1[13])&&($f==1)){ $R[2]++; $f=0; print P14 $es; }
    if(($p =~ $s1[14])&&($f==1)){ $R[2]++; $f=0; print P15 $es; } if(($p =~ $s1[15])&&($f==1)){ $R[2]++; $f=0; print P16 $es; }
    if(($p =~ $s1[16])&&($f==1)){ $R[2]++; $f=0; print P17 $es; } if(($p =~ $s1[17])&&($f==1)){ $R[2]++; $f=0; print P18 $es; }
    if(($p =~ $s1[18])&&($f==1)){ $R[2]++; $f=0; print P19 $es; } if(($p =~ $s1[19])&&($f==1)){ $R[2]++; $f=0; print P20 $es; }
    if(($p =~ $s1[20])&&($f==1)){ $R[2]++; $f=0; print P21 $es; } if(($p =~ $s1[21])&&($f==1)){ $R[2]++; $f=0; print P22 $es; }
    if(($p =~ $s1[22])&&($f==1)){ $R[2]++; $f=0; print P23 $es; } if(($p =~ $s1[23])&&($f==1)){ $R[2]++; $f=0; print P24 $es; }
    
    if(($p =~ $s2[0]) &&($f==1)){ $R[3]++; $f=0; print P01 $es; } if(($p =~ $s2[1]) &&($f==1)){ $R[3]++; $f=0; print P02 $es; }
    if(($p =~ $s2[2]) &&($f==1)){ $R[3]++; $f=0; print P03 $es; } if(($p =~ $s2[3]) &&($f==1)){ $R[3]++; $f=0; print P04 $es; }
    if(($p =~ $s2[4]) &&($f==1)){ $R[3]++; $f=0; print P05 $es; } if(($p =~ $s2[5]) &&($f==1)){ $R[3]++; $f=0; print P06 $es; }
    if(($p =~ $s2[6]) &&($f==1)){ $R[3]++; $f=0; print P07 $es; } if(($p =~ $s2[7]) &&($f==1)){ $R[3]++; $f=0; print P08 $es; }
    if(($p =~ $s2[8]) &&($f==1)){ $R[3]++; $f=0; print P09 $es; } if(($p =~ $s2[9]) &&($f==1)){ $R[3]++; $f=0; print P10 $es; }
    if(($p =~ $s2[10])&&($f==1)){ $R[3]++; $f=0; print P11 $es; } if(($p =~ $s2[11])&&($f==1)){ $R[3]++; $f=0; print P12 $es; }
    if(($p =~ $s2[12])&&($f==1)){ $R[3]++; $f=0; print P13 $es; } if(($p =~ $s2[13])&&($f==1)){ $R[3]++; $f=0; print P14 $es; }
    if(($p =~ $s2[14])&&($f==1)){ $R[3]++; $f=0; print P15 $es; } if(($p =~ $s2[15])&&($f==1)){ $R[3]++; $f=0; print P16 $es; }
    if(($p =~ $s2[16])&&($f==1)){ $R[3]++; $f=0; print P17 $es; } if(($p =~ $s2[17])&&($f==1)){ $R[3]++; $f=0; print P18 $es; }
    if(($p =~ $s2[18])&&($f==1)){ $R[3]++; $f=0; print P19 $es; } if(($p =~ $s2[19])&&($f==1)){ $R[3]++; $f=0; print P20 $es; }
    if(($p =~ $s2[20])&&($f==1)){ $R[3]++; $f=0; print P21 $es; } if(($p =~ $s2[21])&&($f==1)){ $R[3]++; $f=0; print P22 $es; }
    if(($p =~ $s2[22])&&($f==1)){ $R[3]++; $f=0; print P23 $es; } if(($p =~ $s2[23])&&($f==1)){ $R[3]++; $f=0; print P24 $es; }
    
    if(($p =~ $s3[0]) &&($f==1)){ $R[4]++; $f=0; print P01 $es; } if(($p =~ $s3[1]) &&($f==1)){ $R[4]++; $f=0; print P02 $es; }
    if(($p =~ $s3[2]) &&($f==1)){ $R[4]++; $f=0; print P03 $es; } if(($p =~ $s3[3]) &&($f==1)){ $R[4]++; $f=0; print P04 $es; }
    if(($p =~ $s3[4]) &&($f==1)){ $R[4]++; $f=0; print P05 $es; } if(($p =~ $s3[5]) &&($f==1)){ $R[4]++; $f=0; print P06 $es; }
    if(($p =~ $s3[6]) &&($f==1)){ $R[4]++; $f=0; print P07 $es; } if(($p =~ $s3[7]) &&($f==1)){ $R[4]++; $f=0; print P08 $es; }
    if(($p =~ $s3[8]) &&($f==1)){ $R[4]++; $f=0; print P09 $es; } if(($p =~ $s3[9]) &&($f==1)){ $R[4]++; $f=0; print P10 $es; }
    if(($p =~ $s3[10])&&($f==1)){ $R[4]++; $f=0; print P11 $es; } if(($p =~ $s3[11])&&($f==1)){ $R[4]++; $f=0; print P12 $es; }
    if(($p =~ $s3[12])&&($f==1)){ $R[4]++; $f=0; print P13 $es; } if(($p =~ $s3[13])&&($f==1)){ $R[4]++; $f=0; print P14 $es; }
    if(($p =~ $s3[14])&&($f==1)){ $R[4]++; $f=0; print P15 $es; } if(($p =~ $s3[15])&&($f==1)){ $R[4]++; $f=0; print P16 $es; }
    if(($p =~ $s3[16])&&($f==1)){ $R[4]++; $f=0; print P17 $es; } if(($p =~ $s3[17])&&($f==1)){ $R[4]++; $f=0; print P18 $es; }
    if(($p =~ $s3[18])&&($f==1)){ $R[4]++; $f=0; print P19 $es; } if(($p =~ $s3[19])&&($f==1)){ $R[4]++; $f=0; print P20 $es; }
    if(($p =~ $s3[20])&&($f==1)){ $R[4]++; $f=0; print P21 $es; } if(($p =~ $s3[21])&&($f==1)){ $R[4]++; $f=0; print P22 $es; }
    if(($p =~ $s3[22])&&($f==1)){ $R[4]++; $f=0; print P23 $es; } if(($p =~ $s3[23])&&($f==1)){ $R[4]++; $f=0; print P24 $es; }
    
    if(($p =~ $s4[0]) &&($f==1)){ $R[5]++; $f=0; print P01 $es; } if(($p =~ $s4[1]) &&($f==1)){ $R[5]++; $f=0; print P02 $es; }
    if(($p =~ $s4[2]) &&($f==1)){ $R[5]++; $f=0; print P03 $es; } if(($p =~ $s4[3]) &&($f==1)){ $R[5]++; $f=0; print P04 $es; }
    if(($p =~ $s4[4]) &&($f==1)){ $R[5]++; $f=0; print P05 $es; } if(($p =~ $s4[5]) &&($f==1)){ $R[5]++; $f=0; print P06 $es; }
    if(($p =~ $s4[6]) &&($f==1)){ $R[5]++; $f=0; print P07 $es; } if(($p =~ $s4[7]) &&($f==1)){ $R[5]++; $f=0; print P08 $es; }
    if(($p =~ $s4[8]) &&($f==1)){ $R[5]++; $f=0; print P09 $es; } if(($p =~ $s4[9]) &&($f==1)){ $R[5]++; $f=0; print P10 $es; }
    if(($p =~ $s4[10])&&($f==1)){ $R[5]++; $f=0; print P11 $es; } if(($p =~ $s4[11])&&($f==1)){ $R[5]++; $f=0; print P12 $es; }
    if(($p =~ $s4[12])&&($f==1)){ $R[5]++; $f=0; print P13 $es; } if(($p =~ $s4[13])&&($f==1)){ $R[5]++; $f=0; print P14 $es; }
    if(($p =~ $s4[14])&&($f==1)){ $R[5]++; $f=0; print P15 $es; } if(($p =~ $s4[15])&&($f==1)){ $R[5]++; $f=0; print P16 $es; }
    if(($p =~ $s4[16])&&($f==1)){ $R[5]++; $f=0; print P17 $es; } if(($p =~ $s4[17])&&($f==1)){ $R[5]++; $f=0; print P18 $es; }
    if(($p =~ $s4[18])&&($f==1)){ $R[5]++; $f=0; print P19 $es; } if(($p =~ $s4[19])&&($f==1)){ $R[5]++; $f=0; print P20 $es; }
    if(($p =~ $s4[20])&&($f==1)){ $R[5]++; $f=0; print P21 $es; } if(($p =~ $s4[21])&&($f==1)){ $R[5]++; $f=0; print P22 $es; }
    if(($p =~ $s4[22])&&($f==1)){ $R[5]++; $f=0; print P23 $es; } if(($p =~ $s4[23])&&($f==1)){ $R[5]++; $f=0; print P24 $es; }
    
    if(($p =~ $s5[0]) &&($f==1)){ $R[6]++; $f=0; print P01 $es; } if(($p =~ $s5[1]) &&($f==1)){ $R[6]++; $f=0; print P02 $es; }
    if(($p =~ $s5[2]) &&($f==1)){ $R[6]++; $f=0; print P03 $es; } if(($p =~ $s5[3]) &&($f==1)){ $R[6]++; $f=0; print P04 $es; }
    if(($p =~ $s5[4]) &&($f==1)){ $R[6]++; $f=0; print P05 $es; } if(($p =~ $s5[5]) &&($f==1)){ $R[6]++; $f=0; print P06 $es; }
    if(($p =~ $s5[6]) &&($f==1)){ $R[6]++; $f=0; print P07 $es; } if(($p =~ $s5[7]) &&($f==1)){ $R[6]++; $f=0; print P08 $es; }
    if(($p =~ $s5[8]) &&($f==1)){ $R[6]++; $f=0; print P09 $es; } if(($p =~ $s5[9]) &&($f==1)){ $R[6]++; $f=0; print P10 $es; }
    if(($p =~ $s5[10])&&($f==1)){ $R[6]++; $f=0; print P11 $es; } if(($p =~ $s5[11])&&($f==1)){ $R[6]++; $f=0; print P12 $es; }
    if(($p =~ $s5[12])&&($f==1)){ $R[6]++; $f=0; print P13 $es; } if(($p =~ $s5[13])&&($f==1)){ $R[6]++; $f=0; print P14 $es; }
    if(($p =~ $s5[14])&&($f==1)){ $R[6]++; $f=0; print P15 $es; } if(($p =~ $s5[15])&&($f==1)){ $R[6]++; $f=0; print P16 $es; }
    if(($p =~ $s5[16])&&($f==1)){ $R[6]++; $f=0; print P17 $es; } if(($p =~ $s5[17])&&($f==1)){ $R[6]++; $f=0; print P18 $es; }
    if(($p =~ $s5[18])&&($f==1)){ $R[6]++; $f=0; print P19 $es; } if(($p =~ $s5[19])&&($f==1)){ $R[6]++; $f=0; print P20 $es; }
    if(($p =~ $s5[20])&&($f==1)){ $R[6]++; $f=0; print P21 $es; } if(($p =~ $s5[21])&&($f==1)){ $R[6]++; $f=0; print P22 $es; }
    if(($p =~ $s5[22])&&($f==1)){ $R[6]++; $f=0; print P23 $es; } if(($p =~ $s5[23])&&($f==1)){ $R[6]++; $f=0; print P24 $es; }
    
    if(($p =~ $s6[0]) &&($f==1)){ $R[7]++; $f=0; print P01 $es; } if(($p =~ $s6[1]) &&($f==1)){ $R[7]++; $f=0; print P02 $es; }
    if(($p =~ $s6[2]) &&($f==1)){ $R[7]++; $f=0; print P03 $es; } if(($p =~ $s6[3]) &&($f==1)){ $R[7]++; $f=0; print P04 $es; }
    if(($p =~ $s6[4]) &&($f==1)){ $R[7]++; $f=0; print P05 $es; } if(($p =~ $s6[5]) &&($f==1)){ $R[7]++; $f=0; print P06 $es; }
    if(($p =~ $s6[6]) &&($f==1)){ $R[7]++; $f=0; print P07 $es; } if(($p =~ $s6[7]) &&($f==1)){ $R[7]++; $f=0; print P08 $es; }
    if(($p =~ $s6[8]) &&($f==1)){ $R[7]++; $f=0; print P09 $es; } if(($p =~ $s6[9]) &&($f==1)){ $R[7]++; $f=0; print P10 $es; }
    if(($p =~ $s6[10])&&($f==1)){ $R[7]++; $f=0; print P11 $es; } if(($p =~ $s6[11])&&($f==1)){ $R[7]++; $f=0; print P12 $es; }
    if(($p =~ $s6[12])&&($f==1)){ $R[7]++; $f=0; print P13 $es; } if(($p =~ $s6[13])&&($f==1)){ $R[7]++; $f=0; print P14 $es; }
    if(($p =~ $s6[14])&&($f==1)){ $R[7]++; $f=0; print P15 $es; } if(($p =~ $s6[15])&&($f==1)){ $R[7]++; $f=0; print P16 $es; }
    if(($p =~ $s6[16])&&($f==1)){ $R[7]++; $f=0; print P17 $es; } if(($p =~ $s6[17])&&($f==1)){ $R[7]++; $f=0; print P18 $es; }
    if(($p =~ $s6[18])&&($f==1)){ $R[7]++; $f=0; print P19 $es; } if(($p =~ $s6[19])&&($f==1)){ $R[7]++; $f=0; print P20 $es; }
    if(($p =~ $s6[20])&&($f==1)){ $R[7]++; $f=0; print P21 $es; } if(($p =~ $s6[21])&&($f==1)){ $R[7]++; $f=0; print P22 $es; }
    if(($p =~ $s6[22])&&($f==1)){ $R[7]++; $f=0; print P23 $es; } if(($p =~ $s6[23])&&($f==1)){ $R[7]++; $f=0; print P24 $es; }
    
    if(($q eq $s[0]) &&($f==1)){ $R[8]++; $f=0; print P01 $es; } if(($q eq $s[1]) &&($f==1)){ $R[8]++; $f=0; print P02 $es; }
    if(($q eq $s[2]) &&($f==1)){ $R[8]++; $f=0; print P03 $es; } if(($q eq $s[3]) &&($f==1)){ $R[8]++; $f=0; print P04 $es; }
    if(($q eq $s[4]) &&($f==1)){ $R[8]++; $f=0; print P05 $es; } if(($q eq $s[5]) &&($f==1)){ $R[8]++; $f=0; print P06 $es; }
    if(($q eq $s[6]) &&($f==1)){ $R[8]++; $f=0; print P07 $es; } if(($q eq $s[7]) &&($f==1)){ $R[8]++; $f=0; print P08 $es; }
    if(($q eq $s[8]) &&($f==1)){ $R[8]++; $f=0; print P09 $es; } if(($q eq $s[9]) &&($f==1)){ $R[8]++; $f=0; print P10 $es; }
    if(($q eq $s[10])&&($f==1)){ $R[8]++; $f=0; print P11 $es; } if(($q eq $s[11])&&($f==1)){ $R[8]++; $f=0; print P12 $es; }
    if(($q eq $s[12])&&($f==1)){ $R[8]++; $f=0; print P13 $es; } if(($q eq $s[13])&&($f==1)){ $R[8]++; $f=0; print P14 $es; }
    if(($q eq $s[14])&&($f==1)){ $R[8]++; $f=0; print P15 $es; } if(($q eq $s[15])&&($f==1)){ $R[8]++; $f=0; print P16 $es; }
    if(($q eq $s[16])&&($f==1)){ $R[8]++; $f=0; print P17 $es; } if(($q eq $s[17])&&($f==1)){ $R[8]++; $f=0; print P18 $es; }
    if(($q eq $s[18])&&($f==1)){ $R[8]++; $f=0; print P19 $es; } if(($q eq $s[19])&&($f==1)){ $R[8]++; $f=0; print P20 $es; }
    if(($q eq $s[20])&&($f==1)){ $R[8]++; $f=0; print P21 $es; } if(($q eq $s[21])&&($f==1)){ $R[8]++; $f=0; print P22 $es; }
    if(($q eq $s[22])&&($f==1)){ $R[8]++; $f=0; print P23 $es; } if(($q eq $s[23])&&($f==1)){ $R[8]++; $f=0; print P24 $es; }

    if(($q =~ $s1[0]) &&($f==1)){ $R[9]++; $f=0; print P01 $es; } if(($q =~ $s1[1]) &&($f==1)){ $R[9]++; $f=0; print P02 $es; }
    if(($q =~ $s1[2]) &&($f==1)){ $R[9]++; $f=0; print P03 $es; } if(($q =~ $s1[3]) &&($f==1)){ $R[9]++; $f=0; print P04 $es; }
    if(($q =~ $s1[4]) &&($f==1)){ $R[9]++; $f=0; print P05 $es; } if(($q =~ $s1[5]) &&($f==1)){ $R[9]++; $f=0; print P06 $es; }
    if(($q =~ $s1[6]) &&($f==1)){ $R[9]++; $f=0; print P07 $es; } if(($q =~ $s1[7]) &&($f==1)){ $R[9]++; $f=0; print P08 $es; }
    if(($q =~ $s1[8]) &&($f==1)){ $R[9]++; $f=0; print P09 $es; } if(($q =~ $s1[9]) &&($f==1)){ $R[9]++; $f=0; print P10 $es; }
    if(($q =~ $s1[10])&&($f==1)){ $R[9]++; $f=0; print P11 $es; } if(($q =~ $s1[11])&&($f==1)){ $R[9]++; $f=0; print P12 $es; }
    if(($q =~ $s1[12])&&($f==1)){ $R[9]++; $f=0; print P13 $es; } if(($q =~ $s1[13])&&($f==1)){ $R[9]++; $f=0; print P14 $es; }
    if(($q =~ $s1[14])&&($f==1)){ $R[9]++; $f=0; print P15 $es; } if(($q =~ $s1[15])&&($f==1)){ $R[9]++; $f=0; print P16 $es; }
    if(($q =~ $s1[16])&&($f==1)){ $R[9]++; $f=0; print P17 $es; } if(($q =~ $s1[17])&&($f==1)){ $R[9]++; $f=0; print P18 $es; }
    if(($q =~ $s1[18])&&($f==1)){ $R[9]++; $f=0; print P19 $es; } if(($q =~ $s1[19])&&($f==1)){ $R[9]++; $f=0; print P20 $es; }
    if(($q =~ $s1[20])&&($f==1)){ $R[9]++; $f=0; print P21 $es; } if(($q =~ $s1[21])&&($f==1)){ $R[9]++; $f=0; print P22 $es; }
    if(($q =~ $s1[22])&&($f==1)){ $R[9]++; $f=0; print P23 $es; } if(($q =~ $s1[23])&&($f==1)){ $R[9]++; $f=0; print P24 $es; }

    if(($q =~ $s2[0]) &&($f==1)){ $R[10]++; $f=0; print P01 $es; } if(($q =~ $s2[1]) &&($f==1)){ $R[10]++; $f=0; print P02 $es; }
    if(($q =~ $s2[2]) &&($f==1)){ $R[10]++; $f=0; print P03 $es; } if(($q =~ $s2[3]) &&($f==1)){ $R[10]++; $f=0; print P04 $es; }
    if(($q =~ $s2[4]) &&($f==1)){ $R[10]++; $f=0; print P05 $es; } if(($q =~ $s2[5]) &&($f==1)){ $R[10]++; $f=0; print P06 $es; }
    if(($q =~ $s2[6]) &&($f==1)){ $R[10]++; $f=0; print P07 $es; } if(($q =~ $s2[7]) &&($f==1)){ $R[10]++; $f=0; print P08 $es; }
    if(($q =~ $s2[8]) &&($f==1)){ $R[10]++; $f=0; print P09 $es; } if(($q =~ $s2[9]) &&($f==1)){ $R[10]++; $f=0; print P10 $es; }
    if(($q =~ $s2[10])&&($f==1)){ $R[10]++; $f=0; print P11 $es; } if(($q =~ $s2[11])&&($f==1)){ $R[10]++; $f=0; print P12 $es; }
    if(($q =~ $s2[12])&&($f==1)){ $R[10]++; $f=0; print P13 $es; } if(($q =~ $s2[13])&&($f==1)){ $R[10]++; $f=0; print P14 $es; }
    if(($q =~ $s2[14])&&($f==1)){ $R[10]++; $f=0; print P15 $es; } if(($q =~ $s2[15])&&($f==1)){ $R[10]++; $f=0; print P16 $es; }
    if(($q =~ $s2[16])&&($f==1)){ $R[10]++; $f=0; print P17 $es; } if(($q =~ $s2[17])&&($f==1)){ $R[10]++; $f=0; print P18 $es; }
    if(($q =~ $s2[18])&&($f==1)){ $R[10]++; $f=0; print P19 $es; } if(($q =~ $s2[19])&&($f==1)){ $R[10]++; $f=0; print P20 $es; }
    if(($q =~ $s2[20])&&($f==1)){ $R[10]++; $f=0; print P21 $es; } if(($q =~ $s2[21])&&($f==1)){ $R[10]++; $f=0; print P22 $es; }
    if(($q =~ $s2[22])&&($f==1)){ $R[10]++; $f=0; print P23 $es; } if(($q =~ $s2[23])&&($f==1)){ $R[10]++; $f=0; print P24 $es; }

    if(($q =~ $s3[0]) &&($f==1)){ $R[11]++; $f=0; print P01 $es; } if(($q =~ $s3[1]) &&($f==1)){ $R[11]++; $f=0; print P02 $es; }
    if(($q =~ $s3[2]) &&($f==1)){ $R[11]++; $f=0; print P03 $es; } if(($q =~ $s3[3]) &&($f==1)){ $R[11]++; $f=0; print P04 $es; }
    if(($q =~ $s3[4]) &&($f==1)){ $R[11]++; $f=0; print P05 $es; } if(($q =~ $s3[5]) &&($f==1)){ $R[11]++; $f=0; print P06 $es; }
    if(($q =~ $s3[6]) &&($f==1)){ $R[11]++; $f=0; print P07 $es; } if(($q =~ $s3[7]) &&($f==1)){ $R[11]++; $f=0; print P08 $es; }
    if(($q =~ $s3[8]) &&($f==1)){ $R[11]++; $f=0; print P09 $es; } if(($q =~ $s3[9]) &&($f==1)){ $R[11]++; $f=0; print P10 $es; }
    if(($q =~ $s3[10])&&($f==1)){ $R[11]++; $f=0; print P11 $es; } if(($q =~ $s3[11])&&($f==1)){ $R[11]++; $f=0; print P12 $es; }
    if(($q =~ $s3[12])&&($f==1)){ $R[11]++; $f=0; print P13 $es; } if(($q =~ $s3[13])&&($f==1)){ $R[11]++; $f=0; print P14 $es; }
    if(($q =~ $s3[14])&&($f==1)){ $R[11]++; $f=0; print P15 $es; } if(($q =~ $s3[15])&&($f==1)){ $R[11]++; $f=0; print P16 $es; }
    if(($q =~ $s3[16])&&($f==1)){ $R[11]++; $f=0; print P17 $es; } if(($q =~ $s3[17])&&($f==1)){ $R[11]++; $f=0; print P18 $es; }
    if(($q =~ $s3[18])&&($f==1)){ $R[11]++; $f=0; print P19 $es; } if(($q =~ $s3[19])&&($f==1)){ $R[11]++; $f=0; print P20 $es; }
    if(($q =~ $s3[20])&&($f==1)){ $R[11]++; $f=0; print P21 $es; } if(($q =~ $s3[21])&&($f==1)){ $R[11]++; $f=0; print P22 $es; }
    if(($q =~ $s3[22])&&($f==1)){ $R[11]++; $f=0; print P23 $es; } if(($q =~ $s3[23])&&($f==1)){ $R[11]++; $f=0; print P24 $es; }
    
    if(($q =~ $s4[0]) &&($f==1)){ $R[12]++; $f=0; print P01 $es; } if(($q =~ $s4[1]) &&($f==1)){ $R[12]++; $f=0; print P02 $es; }
    if(($q =~ $s4[2]) &&($f==1)){ $R[12]++; $f=0; print P03 $es; } if(($q =~ $s4[3]) &&($f==1)){ $R[12]++; $f=0; print P04 $es; }
    if(($q =~ $s4[4]) &&($f==1)){ $R[12]++; $f=0; print P05 $es; } if(($q =~ $s4[5]) &&($f==1)){ $R[12]++; $f=0; print P06 $es; }
    if(($q =~ $s4[6]) &&($f==1)){ $R[12]++; $f=0; print P07 $es; } if(($q =~ $s4[7]) &&($f==1)){ $R[12]++; $f=0; print P08 $es; }
    if(($q =~ $s4[8]) &&($f==1)){ $R[12]++; $f=0; print P09 $es; } if(($q =~ $s4[9]) &&($f==1)){ $R[12]++; $f=0; print P10 $es; }
    if(($q =~ $s4[10])&&($f==1)){ $R[12]++; $f=0; print P11 $es; } if(($q =~ $s4[11])&&($f==1)){ $R[12]++; $f=0; print P12 $es; }
    if(($q =~ $s4[12])&&($f==1)){ $R[12]++; $f=0; print P13 $es; } if(($q =~ $s4[13])&&($f==1)){ $R[12]++; $f=0; print P14 $es; }
    if(($q =~ $s4[14])&&($f==1)){ $R[12]++; $f=0; print P15 $es; } if(($q =~ $s4[15])&&($f==1)){ $R[12]++; $f=0; print P16 $es; }
    if(($q =~ $s4[16])&&($f==1)){ $R[12]++; $f=0; print P17 $es; } if(($q =~ $s4[17])&&($f==1)){ $R[12]++; $f=0; print P18 $es; }
    if(($q =~ $s4[18])&&($f==1)){ $R[12]++; $f=0; print P19 $es; } if(($q =~ $s4[19])&&($f==1)){ $R[12]++; $f=0; print P20 $es; }
    if(($q =~ $s4[20])&&($f==1)){ $R[12]++; $f=0; print P21 $es; } if(($q =~ $s4[21])&&($f==1)){ $R[12]++; $f=0; print P22 $es; }
    if(($q =~ $s4[22])&&($f==1)){ $R[12]++; $f=0; print P23 $es; } if(($q =~ $s4[23])&&($f==1)){ $R[12]++; $f=0; print P24 $es; }

    if(($q =~ $s5[0]) &&($f==1)){ $R[13]++; $f=0; print P01 $es; } if(($q =~ $s5[1]) &&($f==1)){ $R[13]++; $f=0; print P02 $es; }
    if(($q =~ $s5[2]) &&($f==1)){ $R[13]++; $f=0; print P03 $es; } if(($q =~ $s5[3]) &&($f==1)){ $R[13]++; $f=0; print P04 $es; }
    if(($q =~ $s5[4]) &&($f==1)){ $R[13]++; $f=0; print P05 $es; } if(($q =~ $s5[5]) &&($f==1)){ $R[13]++; $f=0; print P06 $es; }
    if(($q =~ $s5[6]) &&($f==1)){ $R[13]++; $f=0; print P07 $es; } if(($q =~ $s5[7]) &&($f==1)){ $R[13]++; $f=0; print P08 $es; }
    if(($q =~ $s5[8]) &&($f==1)){ $R[13]++; $f=0; print P09 $es; } if(($q =~ $s5[9]) &&($f==1)){ $R[13]++; $f=0; print P10 $es; }
    if(($q =~ $s5[10])&&($f==1)){ $R[13]++; $f=0; print P11 $es; } if(($q =~ $s5[11])&&($f==1)){ $R[13]++; $f=0; print P12 $es; }
    if(($q =~ $s5[12])&&($f==1)){ $R[13]++; $f=0; print P13 $es; } if(($q =~ $s5[13])&&($f==1)){ $R[13]++; $f=0; print P14 $es; }
    if(($q =~ $s5[14])&&($f==1)){ $R[13]++; $f=0; print P15 $es; } if(($q =~ $s5[15])&&($f==1)){ $R[13]++; $f=0; print P16 $es; }
    if(($q =~ $s5[16])&&($f==1)){ $R[13]++; $f=0; print P17 $es; } if(($q =~ $s5[17])&&($f==1)){ $R[13]++; $f=0; print P18 $es; }
    if(($q =~ $s5[18])&&($f==1)){ $R[13]++; $f=0; print P19 $es; } if(($q =~ $s5[19])&&($f==1)){ $R[13]++; $f=0; print P20 $es; }
    if(($q =~ $s5[20])&&($f==1)){ $R[13]++; $f=0; print P21 $es; } if(($q =~ $s5[21])&&($f==1)){ $R[13]++; $f=0; print P22 $es; }
    if(($q =~ $s5[22])&&($f==1)){ $R[13]++; $f=0; print P23 $es; } if(($q =~ $s5[23])&&($f==1)){ $R[13]++; $f=0; print P24 $es; }

    if(($q =~ $s6[0]) &&($f==1)){ $R[14]++; $f=0; print P01 $es; } if(($q =~ $s6[1]) &&($f==1)){ $R[14]++; $f=0; print P02 $es; }
    if(($q =~ $s6[2]) &&($f==1)){ $R[14]++; $f=0; print P03 $es; } if(($q =~ $s6[3]) &&($f==1)){ $R[14]++; $f=0; print P04 $es; }
    if(($q =~ $s6[4]) &&($f==1)){ $R[14]++; $f=0; print P05 $es; } if(($q =~ $s6[5]) &&($f==1)){ $R[14]++; $f=0; print P06 $es; }
    if(($q =~ $s6[6]) &&($f==1)){ $R[14]++; $f=0; print P07 $es; } if(($q =~ $s6[7]) &&($f==1)){ $R[14]++; $f=0; print P08 $es; }
    if(($q =~ $s6[8]) &&($f==1)){ $R[14]++; $f=0; print P09 $es; } if(($q =~ $s6[9]) &&($f==1)){ $R[14]++; $f=0; print P10 $es; }
    if(($q =~ $s6[10])&&($f==1)){ $R[14]++; $f=0; print P11 $es; } if(($q =~ $s6[11])&&($f==1)){ $R[14]++; $f=0; print P12 $es; }
    if(($q =~ $s6[12])&&($f==1)){ $R[14]++; $f=0; print P13 $es; } if(($q =~ $s6[13])&&($f==1)){ $R[14]++; $f=0; print P14 $es; }
    if(($q =~ $s6[14])&&($f==1)){ $R[14]++; $f=0; print P15 $es; } if(($q =~ $s6[15])&&($f==1)){ $R[14]++; $f=0; print P16 $es; }
    if(($q =~ $s6[16])&&($f==1)){ $R[14]++; $f=0; print P17 $es; } if(($q =~ $s6[17])&&($f==1)){ $R[14]++; $f=0; print P18 $es; }
    if(($q =~ $s6[18])&&($f==1)){ $R[14]++; $f=0; print P19 $es; } if(($q =~ $s6[19])&&($f==1)){ $R[14]++; $f=0; print P20 $es; }
    if(($q =~ $s6[20])&&($f==1)){ $R[14]++; $f=0; print P21 $es; } if(($q =~ $s6[21])&&($f==1)){ $R[14]++; $f=0; print P22 $es; }
    if(($q =~ $s6[22])&&($f==1)){ $R[14]++; $f=0; print P23 $es; } if(($q =~ $s6[23])&&($f==1)){ $R[14]++; $f=0; print P24 $es; }
    
    if($f==1){ print PUN $ef; } else{ $R[0]++; }
  }
}

close(P01); close(P02); close(P03); close(P04); close(P05); close(P06); close(P07); close(P08);
close(P09); close(P10); close(P11); close(P12); close(P13); close(P14); close(P15); close(P16);
close(P17); close(P18); close(P19); close(P20); close(P21); close(P22); close(P23); close(P24);
close(PUN); close(IN);

print "\n$num_seq sequences found in input.\n\nResult Sequences   :\n".join("\t",@R)."\n\n";

