#!/usr/bin/perl
use strict;
use DBI;

my $fastq="R203-L7-Sequences.txt";              my $outPUN="R203-L7-PrNotRecog-Sequences.txt";
my $outP01="R203-L7-P01-TCGCAGG-Sequences.txt"; my $outP02="R203-L7-P02-CTCTGCA-Sequences.txt";
my $outP03="R203-L7-P03-CCTAGGT-Sequences.txt"; my $outP04="R203-L7-P04-GGATCAA-Sequences.txt";
my $outP05="R203-L7-P05-GCAAGAT-Sequences.txt"; my $outP06="R203-L7-P06-ATGGAGA-Sequences.txt";
my $outP07="R203-L7-P07-CTCGATG-Sequences.txt"; my $outP08="R203-L7-P08-GCTCGAA-Sequences.txt";
my $outP09="R203-L7-P09-ACCAACT-Sequences.txt"; my $outP10="R203-L7-P10-CCGGTAC-Sequences.txt";
my $outP11="R203-L7-P11-AACTCCG-Sequences.txt"; my $outP12="R203-L7-P12-TTGAAGT-Sequences.txt";
my $outP13="R203-L7-P13-ACTATCA-Sequences.txt"; my $outP14="R203-L7-P14-TTGGATC-Sequences.txt";
my $outP15="R203-L7-P15-CGACCTG-Sequences.txt"; my $outP16="R203-L7-P16-TAATGCG-Sequences.txt";
my $outP17="R203-L7-P17-AGGTACC-Sequences.txt"; my $outP18="R203-L7-P18-TGCGTCC-Sequences.txt";
my $outP19="R203-L7-P19-GAATCTC-Sequences.txt"; my $outP20="R203-L7-P20-CATGCTC-Sequences.txt";
my $outP21="R203-L7-P21-ACGCAAC-Sequences.txt"; my $outP22="R203-L7-P22-GCATTGG-Sequences.txt";
my $outP23="R203-L7-P23-GATCTCG-Sequences.txt"; my $outP24="R203-L7-P24-CAATATG-Sequences.txt";
my $outP25="R203-L7-P25-TGACGTC-Sequences.txt"; my $outP26="R203-L7-P26-GATGCCA-Sequences.txt";
my $outP27="R203-L7-P27-CAATTAC-Sequences.txt"; my $outP28="R203-L7-P28-AGATAGG-Sequences.txt";
my $outP29="R203-L7-P29-CCGATTG-Sequences.txt"; my $outP30="R203-L7-P30-ATGCCGC-Sequences.txt";
my $outP31="R203-L7-P31-CAGTACT-Sequences.txt"; my $outP32="R203-L7-P32-AATAGTA-Sequences.txt";
my $outP33="R203-L7-P33-CATCCGG-Sequences.txt"; my $outP34="R203-L7-P34-TCATGGT-Sequences.txt";
my $outP35="R203-L7-P35-AGAACCG-Sequences.txt"; my $outP36="R203-L7-P36-TGGAATA-Sequences.txt";
my $outP37="R203-L7-P37-CAGGAGG-Sequences.txt"; my $outP38="R203-L7-P38-AATACCT-Sequences.txt";
my $outP39="R203-L7-P39-CGAATGC-Sequences.txt"; my $outP40="R203-L7-P40-TTCGCAA-Sequences.txt";
my $outP41="R203-L7-P41-AATTCAA-Sequences.txt"; my $outP42="R203-L7-P42-CGCGCAG-Sequences.txt";
my $outP43="R203-L7-P43-AAGGTCT-Sequences.txt"; my $outP44="R203-L7-P44-ACTGGAC-Sequences.txt";
my $outP45="R203-L7-P45-AGCAGGT-Sequences.txt"; my $outP46="R203-L7-P46-GTACCGG-Sequences.txt";
my $outP47="R203-L7-P47-GGTCAAG-Sequences.txt"; my $outP48="R203-L7-P48-AATGATG-Sequences.txt";

my @s=("TCGCAGG","CTCTGCA","CCTAGGT","GGATCAA","GCAAGAT","ATGGAGA","CTCGATG","GCTCGAA",
"ACCAACT","CCGGTAC","AACTCCG","TTGAAGT","ACTATCA","TTGGATC","CGACCTG","TAATGCG",
"AGGTACC","TGCGTCC","GAATCTC","CATGCTC","ACGCAAC","GCATTGG","GATCTCG","CAATATG",
"TGACGTC","GATGCCA","CAATTAC","AGATAGG","CCGATTG","ATGCCGC","CAGTACT","AATAGTA",
"CATCCGG","TCATGGT","AGAACCG","TGGAATA","CAGGAGG","AATACCT","CGAATGC","TTCGCAA",
"AATTCAA","CGCGCAG","AAGGTCT","ACTGGAC","AGCAGGT","GTACCGG","GGTCAAG","AATGATG");
my @s1=(".CGCAGG",".TCTGCA",".CTAGGT",".GATCAA",".CAAGAT",".TGGAGA",".TCGATG",".CTCGAA",
".CCAACT",".CGGTAC",".ACTCCG",".TGAAGT",".CTATCA",".TGGATC",".GACCTG",".AATGCG",
".GGTACC",".GCGTCC",".AATCTC",".ATGCTC",".CGCAAC",".CATTGG",".ATCTCG",".AATATG",
".GACGTC",".ATGCCA",".AATTAC",".GATAGG",".CGATTG",".TGCCGC",".AGTACT",".ATAGTA",
".ATCCGG",".CATGGT",".GAACCG",".GGAATA",".AGGAGG",".ATACCT",".GAATGC",".TCGCAA",
".ATTCAA",".GCGCAG",".AGGTCT",".CTGGAC",".GCAGGT",".TACCGG",".GTCAAG",".ATGATG");
my @s2=("T.GCAGG","C.CTGCA","C.TAGGT","G.ATCAA","G.AAGAT","A.GGAGA","C.CGATG","G.TCGAA",
"A.CAACT","C.GGTAC","A.CTCCG","T.GAAGT","A.TATCA","T.GGATC","C.ACCTG","T.ATGCG",
"A.GTACC","T.CGTCC","G.ATCTC","C.TGCTC","A.GCAAC","G.ATTGG","G.TCTCG","C.ATATG",
"T.ACGTC","G.TGCCA","C.ATTAC","A.ATAGG","C.GATTG","A.GCCGC","C.GTACT","A.TAGTA",
"C.TCCGG","T.ATGGT","A.AACCG","T.GAATA","C.GGAGG","A.TACCT","C.AATGC","T.CGCAA",
"A.TTCAA","C.CGCAG","A.GGTCT","A.TGGAC","A.CAGGT","G.ACCGG","G.TCAAG","A.TGATG");
my @s3=("TC.CAGG","CT.TGCA","CC.AGGT","GG.TCAA","GC.AGAT","AT.GAGA","CT.GATG","GC.CGAA",
"AC.AACT","CC.GTAC","AA.TCCG","TT.AAGT","AC.ATCA","TT.GATC","CG.CCTG","TA.TGCG",
"AG.TACC","TG.GTCC","GA.TCTC","CA.GCTC","AC.CAAC","GC.TTGG","GA.CTCG","CA.TATG",
"TG.CGTC","GA.GCCA","CA.TTAC","AG.TAGG","CC.ATTG","AT.CCGC","CA.TACT","AA.AGTA",
"CA.CCGG","TC.TGGT","AG.ACCG","TG.AATA","CA.GAGG","AA.ACCT","CG.ATGC","TT.GCAA",
"AA.TCAA","CG.GCAG","AA.GTCT","AC.GGAC","AG.AGGT","GT.CCGG","GG.CAAG","AA.GATG");
my @s4=("TCG.AGG","CTC.GCA","CCT.GGT","GGA.CAA","GCA.GAT","ATG.AGA","CTC.ATG","GCT.GAA",
"ACC.ACT","CCG.TAC","AAC.CCG","TTG.AGT","ACT.TCA","TTG.ATC","CGA.CTG","TAA.GCG",
"AGG.ACC","TGC.TCC","GAA.CTC","CAT.CTC","ACG.AAC","GCA.TGG","GAT.TCG","CAA.ATG",
"TGA.GTC","GAT.CCA","CAA.TAC","AGA.AGG","CCG.TTG","ATG.CGC","CAG.ACT","AAT.GTA",
"CAT.CGG","TCA.GGT","AGA.CCG","TGG.ATA","CAG.AGG","AAT.CCT","CGA.TGC","TTC.CAA",
"AAT.CAA","CGC.CAG","AAG.TCT","ACT.GAC","AGC.GGT","GTA.CGG","GGT.AAG","AAT.ATG");
my @s5=("TCGC.GG","CTCT.CA","CCTA.GT","GGAT.AA","GCAA.AT","ATGG.GA","CTCG.TG","GCTC.AA",
"ACCA.CT","CCGG.AC","AACT.CG","TTGA.GT","ACTA.CA","TTGG.TC","CGAC.TG","TAAT.CG",
"AGGT.CC","TGCG.CC","GAAT.TC","CATG.TC","ACGC.AC","GCAT.GG","GATC.CG","CAAT.TG",
"TGAC.TC","GATG.CA","CAAT.AC","AGAT.GG","CCGA.TG","ATGC.GC","CAGT.CT","AATA.TA",
"CATC.GG","TCAT.GT","AGAA.CG","TGGA.TA","CAGG.GG","AATA.CT","CGAA.GC","TTCG.AA",
"AATT.AA","CGCG.AG","AAGG.CT","ACTG.AC","AGCA.GT","GTAC.GG","GGTC.AG","AATG.TG");
my @s6=("TCGCA.G","CTCTG.A","CCTAG.T","GGATC.A","GCAAG.T","ATGGA.A","CTCGA.G","GCTCG.A",
"ACCAA.T","CCGGT.C","AACTC.G","TTGAA.T","ACTAT.A","TTGGA.C","CGACC.G","TAATG.G",
"AGGTA.C","TGCGT.C","GAATC.C","CATGC.C","ACGCA.C","GCATT.G","GATCT.G","CAATA.G",
"TGACG.C","GATGC.A","CAATT.C","AGATA.G","CCGAT.G","ATGCC.C","CAGTA.T","AATAG.A",
"CATCC.G","TCATG.T","AGAAC.G","TGGAA.A","CAGGA.G","AATAC.T","CGAAT.C","TTCGC.A",
"AATTC.A","CGCGC.G","AAGGT.T","ACTGG.C","AGCAG.T","GTACC.G","GGTCA.G","AATGA.G");
my @s7=("TCGCAG.","CTCTGC.","CCTAGG.","GGATCA.","GCAAGA.","ATGGAG.","CTCGAT.","GCTCGA.",
"ACCAAC.","CCGGTA.","AACTCC.","TTGAAG.","ACTATC.","TTGGAT.","CGACCT.","TAATGC.",
"AGGTAC.","TGCGTC.","GAATCT.","CATGCT.","ACGCAA.","GCATTG.","GATCTC.","CAATAT.",
"TGACGT.","GATGCC.","CAATTA.","AGATAG.","CCGATT.","ATGCCG.","CAGTAC.","AATAGT.",
"CATCCG.","TCATGG.","AGAACC.","TGGAAT.","CAGGAG.","AATACC.","CGAATG.","TTCGCA.",
"AATTCA.","CGCGCA.","AAGGTC.","ACTGGA.","AGCAGG.","GTACCG.","GGTCAA.","AATGAT.");

open(IN,$fastq) || die "Cannot open input file";
open(PUN,">$outPUN") || die "Cannot open output file";
open(P01,">$outP01") || die "Cannot open output file";
open(P02,">$outP02") || die "Cannot open output file";
open(P03,">$outP03") || die "Cannot open output file";
open(P04,">$outP04") || die "Cannot open output file";
open(P05,">$outP05") || die "Cannot open output file";
open(P06,">$outP06") || die "Cannot open output file";
open(P07,">$outP07") || die "Cannot open output file";
open(P08,">$outP08") || die "Cannot open output file";
open(P09,">$outP09") || die "Cannot open output file";
open(P10,">$outP10") || die "Cannot open output file";
open(P11,">$outP11") || die "Cannot open output file";
open(P12,">$outP12") || die "Cannot open output file";
open(P13,">$outP13") || die "Cannot open output file";
open(P14,">$outP14") || die "Cannot open output file";
open(P15,">$outP15") || die "Cannot open output file";
open(P16,">$outP16") || die "Cannot open output file";
open(P17,">$outP17") || die "Cannot open output file";
open(P18,">$outP18") || die "Cannot open output file";
open(P19,">$outP19") || die "Cannot open output file";
open(P20,">$outP20") || die "Cannot open output file";
open(P21,">$outP21") || die "Cannot open output file";
open(P22,">$outP22") || die "Cannot open output file";
open(P23,">$outP23") || die "Cannot open output file";
open(P24,">$outP24") || die "Cannot open output file";
open(P25,">$outP25") || die "Cannot open output file";
open(P26,">$outP26") || die "Cannot open output file";
open(P27,">$outP27") || die "Cannot open output file";
open(P28,">$outP28") || die "Cannot open output file";
open(P29,">$outP29") || die "Cannot open output file";
open(P30,">$outP30") || die "Cannot open output file";
open(P31,">$outP31") || die "Cannot open output file";
open(P32,">$outP32") || die "Cannot open output file";
open(P33,">$outP33") || die "Cannot open output file";
open(P34,">$outP34") || die "Cannot open output file";
open(P35,">$outP35") || die "Cannot open output file";
open(P36,">$outP36") || die "Cannot open output file";
open(P37,">$outP37") || die "Cannot open output file";
open(P38,">$outP38") || die "Cannot open output file";
open(P39,">$outP39") || die "Cannot open output file";
open(P40,">$outP40") || die "Cannot open output file";
open(P41,">$outP41") || die "Cannot open output file";
open(P42,">$outP42") || die "Cannot open output file";
open(P43,">$outP43") || die "Cannot open output file";
open(P44,">$outP44") || die "Cannot open output file";
open(P45,">$outP45") || die "Cannot open output file";
open(P46,">$outP46") || die "Cannot open output file";
open(P47,">$outP47") || die "Cannot open output file";
open(P48,">$outP48") || die "Cannot open output file";

my $l; my $num_seq=0; my @R=(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);

while($l=<IN>)
{
  if($l =~ /^@/)
  {
    my $h1=$l; chomp($h1); $l=<IN>; my $d1=$l; chomp($d1); $l=<IN>; my $h2=$l;
    chomp($h2); $l=<IN>; my $d2=$l; chomp($d2); my $ef="$h1\n$d1\n$h2\n$d2\n";
    my $es="$h1\n".substr($d1,7)."\n$h2\n".substr($d2,7)."\n";
    $num_seq++; my $p=substr($d1,0,7); my $f=1;
    
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
    if(($p eq $s[11])&&($f==1)){ $R[1]++; $f=0; print P12 $es; }
    if(($p eq $s[12])&&($f==1)){ $R[1]++; $f=0; print P13 $es; }
    if(($p eq $s[13])&&($f==1)){ $R[1]++; $f=0; print P14 $es; }
    if(($p eq $s[14])&&($f==1)){ $R[1]++; $f=0; print P15 $es; }
    if(($p eq $s[15])&&($f==1)){ $R[1]++; $f=0; print P16 $es; }
    if(($p eq $s[16])&&($f==1)){ $R[1]++; $f=0; print P17 $es; }
    if(($p eq $s[17])&&($f==1)){ $R[1]++; $f=0; print P18 $es; }
    if(($p eq $s[18])&&($f==1)){ $R[1]++; $f=0; print P19 $es; }
    if(($p eq $s[19])&&($f==1)){ $R[1]++; $f=0; print P20 $es; }
    if(($p eq $s[20])&&($f==1)){ $R[1]++; $f=0; print P21 $es; }
    if(($p eq $s[21])&&($f==1)){ $R[1]++; $f=0; print P22 $es; }
    if(($p eq $s[22])&&($f==1)){ $R[1]++; $f=0; print P23 $es; }
    if(($p eq $s[23])&&($f==1)){ $R[1]++; $f=0; print P24 $es; }
    if(($p eq $s[24])&&($f==1)){ $R[1]++; $f=0; print P25 $es; }
    if(($p eq $s[25])&&($f==1)){ $R[1]++; $f=0; print P26 $es; }
    if(($p eq $s[26])&&($f==1)){ $R[1]++; $f=0; print P27 $es; }
    if(($p eq $s[27])&&($f==1)){ $R[1]++; $f=0; print P28 $es; }
    if(($p eq $s[28])&&($f==1)){ $R[1]++; $f=0; print P29 $es; }
    if(($p eq $s[29])&&($f==1)){ $R[1]++; $f=0; print P30 $es; }
    if(($p eq $s[30])&&($f==1)){ $R[1]++; $f=0; print P31 $es; }
    if(($p eq $s[31])&&($f==1)){ $R[1]++; $f=0; print P32 $es; }
    if(($p eq $s[32])&&($f==1)){ $R[1]++; $f=0; print P33 $es; }
    if(($p eq $s[33])&&($f==1)){ $R[1]++; $f=0; print P34 $es; }
    if(($p eq $s[34])&&($f==1)){ $R[1]++; $f=0; print P35 $es; }
    if(($p eq $s[35])&&($f==1)){ $R[1]++; $f=0; print P36 $es; }
    if(($p eq $s[36])&&($f==1)){ $R[1]++; $f=0; print P37 $es; }
    if(($p eq $s[37])&&($f==1)){ $R[1]++; $f=0; print P38 $es; }
    if(($p eq $s[38])&&($f==1)){ $R[1]++; $f=0; print P39 $es; }
    if(($p eq $s[39])&&($f==1)){ $R[1]++; $f=0; print P40 $es; }
    if(($p eq $s[40])&&($f==1)){ $R[1]++; $f=0; print P41 $es; }
    if(($p eq $s[41])&&($f==1)){ $R[1]++; $f=0; print P42 $es; }
    if(($p eq $s[42])&&($f==1)){ $R[1]++; $f=0; print P43 $es; }
    if(($p eq $s[43])&&($f==1)){ $R[1]++; $f=0; print P44 $es; }
    if(($p eq $s[44])&&($f==1)){ $R[1]++; $f=0; print P45 $es; }
    if(($p eq $s[45])&&($f==1)){ $R[1]++; $f=0; print P46 $es; }
    if(($p eq $s[46])&&($f==1)){ $R[1]++; $f=0; print P47 $es; }
    if(($p eq $s[47])&&($f==1)){ $R[1]++; $f=0; print P48 $es; }
    
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
    if(($p =~ $s1[11])&&($f==1)){ $R[2]++; $f=0; print P12 $es; }
    if(($p =~ $s1[12])&&($f==1)){ $R[2]++; $f=0; print P13 $es; }
    if(($p =~ $s1[13])&&($f==1)){ $R[2]++; $f=0; print P14 $es; }
    if(($p =~ $s1[14])&&($f==1)){ $R[2]++; $f=0; print P15 $es; }
    if(($p =~ $s1[15])&&($f==1)){ $R[2]++; $f=0; print P16 $es; }
    if(($p =~ $s1[16])&&($f==1)){ $R[2]++; $f=0; print P17 $es; }
    if(($p =~ $s1[17])&&($f==1)){ $R[2]++; $f=0; print P18 $es; }
    if(($p =~ $s1[18])&&($f==1)){ $R[2]++; $f=0; print P19 $es; }
    if(($p =~ $s1[19])&&($f==1)){ $R[2]++; $f=0; print P20 $es; }
    if(($p =~ $s1[20])&&($f==1)){ $R[2]++; $f=0; print P21 $es; }
    if(($p =~ $s1[21])&&($f==1)){ $R[2]++; $f=0; print P22 $es; }
    if(($p =~ $s1[22])&&($f==1)){ $R[2]++; $f=0; print P23 $es; }
    if(($p =~ $s1[23])&&($f==1)){ $R[2]++; $f=0; print P24 $es; }
    if(($p =~ $s1[24])&&($f==1)){ $R[2]++; $f=0; print P25 $es; }
    if(($p =~ $s1[25])&&($f==1)){ $R[2]++; $f=0; print P26 $es; }
    if(($p =~ $s1[26])&&($f==1)){ $R[2]++; $f=0; print P27 $es; }
    if(($p =~ $s1[27])&&($f==1)){ $R[2]++; $f=0; print P28 $es; }
    if(($p =~ $s1[28])&&($f==1)){ $R[2]++; $f=0; print P29 $es; }
    if(($p =~ $s1[29])&&($f==1)){ $R[2]++; $f=0; print P30 $es; }
    if(($p =~ $s1[30])&&($f==1)){ $R[2]++; $f=0; print P31 $es; }
    if(($p =~ $s1[31])&&($f==1)){ $R[2]++; $f=0; print P32 $es; }
    if(($p =~ $s1[32])&&($f==1)){ $R[2]++; $f=0; print P33 $es; }
    if(($p =~ $s1[33])&&($f==1)){ $R[2]++; $f=0; print P34 $es; }
    if(($p =~ $s1[34])&&($f==1)){ $R[2]++; $f=0; print P35 $es; }
    if(($p =~ $s1[35])&&($f==1)){ $R[2]++; $f=0; print P36 $es; }
    if(($p =~ $s1[36])&&($f==1)){ $R[2]++; $f=0; print P37 $es; }
    if(($p =~ $s1[37])&&($f==1)){ $R[2]++; $f=0; print P38 $es; }
    if(($p =~ $s1[38])&&($f==1)){ $R[2]++; $f=0; print P39 $es; }
    if(($p =~ $s1[39])&&($f==1)){ $R[2]++; $f=0; print P40 $es; }
    if(($p =~ $s1[40])&&($f==1)){ $R[2]++; $f=0; print P41 $es; }
    if(($p =~ $s1[41])&&($f==1)){ $R[2]++; $f=0; print P42 $es; }
    if(($p =~ $s1[42])&&($f==1)){ $R[2]++; $f=0; print P43 $es; }
    if(($p =~ $s1[43])&&($f==1)){ $R[2]++; $f=0; print P44 $es; }
    if(($p =~ $s1[44])&&($f==1)){ $R[2]++; $f=0; print P45 $es; }
    if(($p =~ $s1[45])&&($f==1)){ $R[2]++; $f=0; print P46 $es; }
    if(($p =~ $s1[46])&&($f==1)){ $R[2]++; $f=0; print P47 $es; }
    if(($p =~ $s1[47])&&($f==1)){ $R[2]++; $f=0; print P48 $es; }
    
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
    if(($p =~ $s2[11])&&($f==1)){ $R[3]++; $f=0; print P12 $es; }
    if(($p =~ $s2[12])&&($f==1)){ $R[3]++; $f=0; print P13 $es; }
    if(($p =~ $s2[13])&&($f==1)){ $R[3]++; $f=0; print P14 $es; }
    if(($p =~ $s2[14])&&($f==1)){ $R[3]++; $f=0; print P15 $es; }
    if(($p =~ $s2[15])&&($f==1)){ $R[3]++; $f=0; print P16 $es; }
    if(($p =~ $s2[16])&&($f==1)){ $R[3]++; $f=0; print P17 $es; }
    if(($p =~ $s2[17])&&($f==1)){ $R[3]++; $f=0; print P18 $es; }
    if(($p =~ $s2[18])&&($f==1)){ $R[3]++; $f=0; print P19 $es; }
    if(($p =~ $s2[19])&&($f==1)){ $R[3]++; $f=0; print P20 $es; }
    if(($p =~ $s2[20])&&($f==1)){ $R[3]++; $f=0; print P21 $es; }
    if(($p =~ $s2[21])&&($f==1)){ $R[3]++; $f=0; print P22 $es; }
    if(($p =~ $s2[22])&&($f==1)){ $R[3]++; $f=0; print P23 $es; }
    if(($p =~ $s2[23])&&($f==1)){ $R[3]++; $f=0; print P24 $es; }
    if(($p =~ $s2[24])&&($f==1)){ $R[3]++; $f=0; print P25 $es; }
    if(($p =~ $s2[25])&&($f==1)){ $R[3]++; $f=0; print P26 $es; }
    if(($p =~ $s2[26])&&($f==1)){ $R[3]++; $f=0; print P27 $es; }
    if(($p =~ $s2[27])&&($f==1)){ $R[3]++; $f=0; print P28 $es; }
    if(($p =~ $s2[28])&&($f==1)){ $R[3]++; $f=0; print P29 $es; }
    if(($p =~ $s2[29])&&($f==1)){ $R[3]++; $f=0; print P30 $es; }
    if(($p =~ $s2[30])&&($f==1)){ $R[3]++; $f=0; print P31 $es; }
    if(($p =~ $s2[31])&&($f==1)){ $R[3]++; $f=0; print P32 $es; }
    if(($p =~ $s2[32])&&($f==1)){ $R[3]++; $f=0; print P33 $es; }
    if(($p =~ $s2[33])&&($f==1)){ $R[3]++; $f=0; print P34 $es; }
    if(($p =~ $s2[34])&&($f==1)){ $R[3]++; $f=0; print P35 $es; }
    if(($p =~ $s2[35])&&($f==1)){ $R[3]++; $f=0; print P36 $es; }
    if(($p =~ $s2[36])&&($f==1)){ $R[3]++; $f=0; print P37 $es; }
    if(($p =~ $s2[37])&&($f==1)){ $R[3]++; $f=0; print P38 $es; }
    if(($p =~ $s2[38])&&($f==1)){ $R[3]++; $f=0; print P39 $es; }
    if(($p =~ $s2[39])&&($f==1)){ $R[3]++; $f=0; print P40 $es; }
    if(($p =~ $s2[40])&&($f==1)){ $R[3]++; $f=0; print P41 $es; }
    if(($p =~ $s2[41])&&($f==1)){ $R[3]++; $f=0; print P42 $es; }
    if(($p =~ $s2[42])&&($f==1)){ $R[3]++; $f=0; print P43 $es; }
    if(($p =~ $s2[43])&&($f==1)){ $R[3]++; $f=0; print P44 $es; }
    if(($p =~ $s2[44])&&($f==1)){ $R[3]++; $f=0; print P45 $es; }
    if(($p =~ $s2[45])&&($f==1)){ $R[3]++; $f=0; print P46 $es; }
    if(($p =~ $s2[46])&&($f==1)){ $R[3]++; $f=0; print P47 $es; }
    if(($p =~ $s2[47])&&($f==1)){ $R[3]++; $f=0; print P48 $es; }
    
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
    if(($p =~ $s3[11])&&($f==1)){ $R[4]++; $f=0; print P12 $es; }
    if(($p =~ $s3[12])&&($f==1)){ $R[4]++; $f=0; print P13 $es; }
    if(($p =~ $s3[13])&&($f==1)){ $R[4]++; $f=0; print P14 $es; }
    if(($p =~ $s3[14])&&($f==1)){ $R[4]++; $f=0; print P15 $es; }
    if(($p =~ $s3[15])&&($f==1)){ $R[4]++; $f=0; print P16 $es; }
    if(($p =~ $s3[16])&&($f==1)){ $R[4]++; $f=0; print P17 $es; }
    if(($p =~ $s3[17])&&($f==1)){ $R[4]++; $f=0; print P18 $es; }
    if(($p =~ $s3[18])&&($f==1)){ $R[4]++; $f=0; print P19 $es; }
    if(($p =~ $s3[19])&&($f==1)){ $R[4]++; $f=0; print P20 $es; }
    if(($p =~ $s3[20])&&($f==1)){ $R[4]++; $f=0; print P21 $es; }
    if(($p =~ $s3[21])&&($f==1)){ $R[4]++; $f=0; print P22 $es; }
    if(($p =~ $s3[22])&&($f==1)){ $R[4]++; $f=0; print P23 $es; }
    if(($p =~ $s3[23])&&($f==1)){ $R[4]++; $f=0; print P24 $es; }
    if(($p =~ $s3[24])&&($f==1)){ $R[4]++; $f=0; print P25 $es; }
    if(($p =~ $s3[25])&&($f==1)){ $R[4]++; $f=0; print P26 $es; }
    if(($p =~ $s3[26])&&($f==1)){ $R[4]++; $f=0; print P27 $es; }
    if(($p =~ $s3[27])&&($f==1)){ $R[4]++; $f=0; print P28 $es; }
    if(($p =~ $s3[28])&&($f==1)){ $R[4]++; $f=0; print P29 $es; }
    if(($p =~ $s3[29])&&($f==1)){ $R[4]++; $f=0; print P30 $es; }
    if(($p =~ $s3[30])&&($f==1)){ $R[4]++; $f=0; print P31 $es; }
    if(($p =~ $s3[31])&&($f==1)){ $R[4]++; $f=0; print P32 $es; }
    if(($p =~ $s3[32])&&($f==1)){ $R[4]++; $f=0; print P33 $es; }
    if(($p =~ $s3[33])&&($f==1)){ $R[4]++; $f=0; print P34 $es; }
    if(($p =~ $s3[34])&&($f==1)){ $R[4]++; $f=0; print P35 $es; }
    if(($p =~ $s3[35])&&($f==1)){ $R[4]++; $f=0; print P36 $es; }
    if(($p =~ $s3[36])&&($f==1)){ $R[4]++; $f=0; print P37 $es; }
    if(($p =~ $s3[37])&&($f==1)){ $R[4]++; $f=0; print P38 $es; }
    if(($p =~ $s3[38])&&($f==1)){ $R[4]++; $f=0; print P39 $es; }
    if(($p =~ $s3[39])&&($f==1)){ $R[4]++; $f=0; print P40 $es; }
    if(($p =~ $s3[40])&&($f==1)){ $R[4]++; $f=0; print P41 $es; }
    if(($p =~ $s3[41])&&($f==1)){ $R[4]++; $f=0; print P42 $es; }
    if(($p =~ $s3[42])&&($f==1)){ $R[4]++; $f=0; print P43 $es; }
    if(($p =~ $s3[43])&&($f==1)){ $R[4]++; $f=0; print P44 $es; }
    if(($p =~ $s3[44])&&($f==1)){ $R[4]++; $f=0; print P45 $es; }
    if(($p =~ $s3[45])&&($f==1)){ $R[4]++; $f=0; print P46 $es; }
    if(($p =~ $s3[46])&&($f==1)){ $R[4]++; $f=0; print P47 $es; }
    if(($p =~ $s3[47])&&($f==1)){ $R[4]++; $f=0; print P48 $es; }
    
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
    if(($p =~ $s4[11])&&($f==1)){ $R[5]++; $f=0; print P12 $es; }
    if(($p =~ $s4[12])&&($f==1)){ $R[5]++; $f=0; print P13 $es; }
    if(($p =~ $s4[13])&&($f==1)){ $R[5]++; $f=0; print P14 $es; }
    if(($p =~ $s4[14])&&($f==1)){ $R[5]++; $f=0; print P15 $es; }
    if(($p =~ $s4[15])&&($f==1)){ $R[5]++; $f=0; print P16 $es; }
    if(($p =~ $s4[16])&&($f==1)){ $R[5]++; $f=0; print P17 $es; }
    if(($p =~ $s4[17])&&($f==1)){ $R[5]++; $f=0; print P18 $es; }
    if(($p =~ $s4[18])&&($f==1)){ $R[5]++; $f=0; print P19 $es; }
    if(($p =~ $s4[19])&&($f==1)){ $R[5]++; $f=0; print P20 $es; }
    if(($p =~ $s4[20])&&($f==1)){ $R[5]++; $f=0; print P21 $es; }
    if(($p =~ $s4[21])&&($f==1)){ $R[5]++; $f=0; print P22 $es; }
    if(($p =~ $s4[22])&&($f==1)){ $R[5]++; $f=0; print P23 $es; }
    if(($p =~ $s4[23])&&($f==1)){ $R[5]++; $f=0; print P24 $es; }
    if(($p =~ $s4[24])&&($f==1)){ $R[5]++; $f=0; print P25 $es; }
    if(($p =~ $s4[25])&&($f==1)){ $R[5]++; $f=0; print P26 $es; }
    if(($p =~ $s4[26])&&($f==1)){ $R[5]++; $f=0; print P27 $es; }
    if(($p =~ $s4[27])&&($f==1)){ $R[5]++; $f=0; print P28 $es; }
    if(($p =~ $s4[28])&&($f==1)){ $R[5]++; $f=0; print P29 $es; }
    if(($p =~ $s4[29])&&($f==1)){ $R[5]++; $f=0; print P30 $es; }
    if(($p =~ $s4[30])&&($f==1)){ $R[5]++; $f=0; print P31 $es; }
    if(($p =~ $s4[31])&&($f==1)){ $R[5]++; $f=0; print P32 $es; }
    if(($p =~ $s4[32])&&($f==1)){ $R[5]++; $f=0; print P33 $es; }
    if(($p =~ $s4[33])&&($f==1)){ $R[5]++; $f=0; print P34 $es; }
    if(($p =~ $s4[34])&&($f==1)){ $R[5]++; $f=0; print P35 $es; }
    if(($p =~ $s4[35])&&($f==1)){ $R[5]++; $f=0; print P36 $es; }
    if(($p =~ $s4[36])&&($f==1)){ $R[5]++; $f=0; print P37 $es; }
    if(($p =~ $s4[37])&&($f==1)){ $R[5]++; $f=0; print P38 $es; }
    if(($p =~ $s4[38])&&($f==1)){ $R[5]++; $f=0; print P39 $es; }
    if(($p =~ $s4[39])&&($f==1)){ $R[5]++; $f=0; print P40 $es; }
    if(($p =~ $s4[40])&&($f==1)){ $R[5]++; $f=0; print P41 $es; }
    if(($p =~ $s4[41])&&($f==1)){ $R[5]++; $f=0; print P42 $es; }
    if(($p =~ $s4[42])&&($f==1)){ $R[5]++; $f=0; print P43 $es; }
    if(($p =~ $s4[43])&&($f==1)){ $R[5]++; $f=0; print P44 $es; }
    if(($p =~ $s4[44])&&($f==1)){ $R[5]++; $f=0; print P45 $es; }
    if(($p =~ $s4[45])&&($f==1)){ $R[5]++; $f=0; print P46 $es; }
    if(($p =~ $s4[46])&&($f==1)){ $R[5]++; $f=0; print P47 $es; }
    if(($p =~ $s4[47])&&($f==1)){ $R[5]++; $f=0; print P48 $es; }
    
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
    if(($p =~ $s5[11])&&($f==1)){ $R[6]++; $f=0; print P12 $es; }
    if(($p =~ $s5[12])&&($f==1)){ $R[6]++; $f=0; print P13 $es; }
    if(($p =~ $s5[13])&&($f==1)){ $R[6]++; $f=0; print P14 $es; }
    if(($p =~ $s5[14])&&($f==1)){ $R[6]++; $f=0; print P15 $es; }
    if(($p =~ $s5[15])&&($f==1)){ $R[6]++; $f=0; print P16 $es; }
    if(($p =~ $s5[16])&&($f==1)){ $R[6]++; $f=0; print P17 $es; }
    if(($p =~ $s5[17])&&($f==1)){ $R[6]++; $f=0; print P18 $es; }
    if(($p =~ $s5[18])&&($f==1)){ $R[6]++; $f=0; print P19 $es; }
    if(($p =~ $s5[19])&&($f==1)){ $R[6]++; $f=0; print P20 $es; }
    if(($p =~ $s5[20])&&($f==1)){ $R[6]++; $f=0; print P21 $es; }
    if(($p =~ $s5[21])&&($f==1)){ $R[6]++; $f=0; print P22 $es; }
    if(($p =~ $s5[22])&&($f==1)){ $R[6]++; $f=0; print P23 $es; }
    if(($p =~ $s5[23])&&($f==1)){ $R[6]++; $f=0; print P24 $es; }
    if(($p =~ $s5[24])&&($f==1)){ $R[6]++; $f=0; print P25 $es; }
    if(($p =~ $s5[25])&&($f==1)){ $R[6]++; $f=0; print P26 $es; }
    if(($p =~ $s5[26])&&($f==1)){ $R[6]++; $f=0; print P27 $es; }
    if(($p =~ $s5[27])&&($f==1)){ $R[6]++; $f=0; print P28 $es; }
    if(($p =~ $s5[28])&&($f==1)){ $R[6]++; $f=0; print P29 $es; }
    if(($p =~ $s5[29])&&($f==1)){ $R[6]++; $f=0; print P30 $es; }
    if(($p =~ $s5[30])&&($f==1)){ $R[6]++; $f=0; print P31 $es; }
    if(($p =~ $s5[31])&&($f==1)){ $R[6]++; $f=0; print P32 $es; }
    if(($p =~ $s5[32])&&($f==1)){ $R[6]++; $f=0; print P33 $es; }
    if(($p =~ $s5[33])&&($f==1)){ $R[6]++; $f=0; print P34 $es; }
    if(($p =~ $s5[34])&&($f==1)){ $R[6]++; $f=0; print P35 $es; }
    if(($p =~ $s5[35])&&($f==1)){ $R[6]++; $f=0; print P36 $es; }
    if(($p =~ $s5[36])&&($f==1)){ $R[6]++; $f=0; print P37 $es; }
    if(($p =~ $s5[37])&&($f==1)){ $R[6]++; $f=0; print P38 $es; }
    if(($p =~ $s5[38])&&($f==1)){ $R[6]++; $f=0; print P39 $es; }
    if(($p =~ $s5[39])&&($f==1)){ $R[6]++; $f=0; print P40 $es; }
    if(($p =~ $s5[40])&&($f==1)){ $R[6]++; $f=0; print P41 $es; }
    if(($p =~ $s5[41])&&($f==1)){ $R[6]++; $f=0; print P42 $es; }
    if(($p =~ $s5[42])&&($f==1)){ $R[6]++; $f=0; print P43 $es; }
    if(($p =~ $s5[43])&&($f==1)){ $R[6]++; $f=0; print P44 $es; }
    if(($p =~ $s5[44])&&($f==1)){ $R[6]++; $f=0; print P45 $es; }
    if(($p =~ $s5[45])&&($f==1)){ $R[6]++; $f=0; print P46 $es; }
    if(($p =~ $s5[46])&&($f==1)){ $R[6]++; $f=0; print P47 $es; }
    if(($p =~ $s5[47])&&($f==1)){ $R[6]++; $f=0; print P48 $es; }
    
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
    if(($p =~ $s6[11])&&($f==1)){ $R[7]++; $f=0; print P12 $es; }
    if(($p =~ $s6[12])&&($f==1)){ $R[7]++; $f=0; print P13 $es; }
    if(($p =~ $s6[13])&&($f==1)){ $R[7]++; $f=0; print P14 $es; }
    if(($p =~ $s6[14])&&($f==1)){ $R[7]++; $f=0; print P15 $es; }
    if(($p =~ $s6[15])&&($f==1)){ $R[7]++; $f=0; print P16 $es; }
    if(($p =~ $s6[16])&&($f==1)){ $R[7]++; $f=0; print P17 $es; }
    if(($p =~ $s6[17])&&($f==1)){ $R[7]++; $f=0; print P18 $es; }
    if(($p =~ $s6[18])&&($f==1)){ $R[7]++; $f=0; print P19 $es; }
    if(($p =~ $s6[19])&&($f==1)){ $R[7]++; $f=0; print P20 $es; }
    if(($p =~ $s6[20])&&($f==1)){ $R[7]++; $f=0; print P21 $es; }
    if(($p =~ $s6[21])&&($f==1)){ $R[7]++; $f=0; print P22 $es; }
    if(($p =~ $s6[22])&&($f==1)){ $R[7]++; $f=0; print P23 $es; }
    if(($p =~ $s6[23])&&($f==1)){ $R[7]++; $f=0; print P24 $es; }
    if(($p =~ $s6[24])&&($f==1)){ $R[7]++; $f=0; print P25 $es; }
    if(($p =~ $s6[25])&&($f==1)){ $R[7]++; $f=0; print P26 $es; }
    if(($p =~ $s6[26])&&($f==1)){ $R[7]++; $f=0; print P27 $es; }
    if(($p =~ $s6[27])&&($f==1)){ $R[7]++; $f=0; print P28 $es; }
    if(($p =~ $s6[28])&&($f==1)){ $R[7]++; $f=0; print P29 $es; }
    if(($p =~ $s6[29])&&($f==1)){ $R[7]++; $f=0; print P30 $es; }
    if(($p =~ $s6[30])&&($f==1)){ $R[7]++; $f=0; print P31 $es; }
    if(($p =~ $s6[31])&&($f==1)){ $R[7]++; $f=0; print P32 $es; }
    if(($p =~ $s6[32])&&($f==1)){ $R[7]++; $f=0; print P33 $es; }
    if(($p =~ $s6[33])&&($f==1)){ $R[7]++; $f=0; print P34 $es; }
    if(($p =~ $s6[34])&&($f==1)){ $R[7]++; $f=0; print P35 $es; }
    if(($p =~ $s6[35])&&($f==1)){ $R[7]++; $f=0; print P36 $es; }
    if(($p =~ $s6[36])&&($f==1)){ $R[7]++; $f=0; print P37 $es; }
    if(($p =~ $s6[37])&&($f==1)){ $R[7]++; $f=0; print P38 $es; }
    if(($p =~ $s6[38])&&($f==1)){ $R[7]++; $f=0; print P39 $es; }
    if(($p =~ $s6[39])&&($f==1)){ $R[7]++; $f=0; print P40 $es; }
    if(($p =~ $s6[40])&&($f==1)){ $R[7]++; $f=0; print P41 $es; }
    if(($p =~ $s6[41])&&($f==1)){ $R[7]++; $f=0; print P42 $es; }
    if(($p =~ $s6[42])&&($f==1)){ $R[7]++; $f=0; print P43 $es; }
    if(($p =~ $s6[43])&&($f==1)){ $R[7]++; $f=0; print P44 $es; }
    if(($p =~ $s6[44])&&($f==1)){ $R[7]++; $f=0; print P45 $es; }
    if(($p =~ $s6[45])&&($f==1)){ $R[7]++; $f=0; print P46 $es; }
    if(($p =~ $s6[46])&&($f==1)){ $R[7]++; $f=0; print P47 $es; }
    if(($p =~ $s6[47])&&($f==1)){ $R[7]++; $f=0; print P48 $es; }
    
    if(($p =~ $s7[0]) &&($f==1)){ $R[8]++; $f=0; print P01 $es; }
    if(($p =~ $s7[1]) &&($f==1)){ $R[8]++; $f=0; print P02 $es; }
    if(($p =~ $s7[2]) &&($f==1)){ $R[8]++; $f=0; print P03 $es; }
    if(($p =~ $s7[3]) &&($f==1)){ $R[8]++; $f=0; print P04 $es; }
    if(($p =~ $s7[4]) &&($f==1)){ $R[8]++; $f=0; print P05 $es; }
    if(($p =~ $s7[5]) &&($f==1)){ $R[8]++; $f=0; print P06 $es; }
    if(($p =~ $s7[6]) &&($f==1)){ $R[8]++; $f=0; print P07 $es; }
    if(($p =~ $s7[7]) &&($f==1)){ $R[8]++; $f=0; print P08 $es; }
    if(($p =~ $s7[8]) &&($f==1)){ $R[8]++; $f=0; print P09 $es; }
    if(($p =~ $s7[9]) &&($f==1)){ $R[8]++; $f=0; print P10 $es; }
    if(($p =~ $s7[10])&&($f==1)){ $R[8]++; $f=0; print P11 $es; }
    if(($p =~ $s7[11])&&($f==1)){ $R[8]++; $f=0; print P12 $es; }
    if(($p =~ $s7[12])&&($f==1)){ $R[8]++; $f=0; print P13 $es; }
    if(($p =~ $s7[13])&&($f==1)){ $R[8]++; $f=0; print P14 $es; }
    if(($p =~ $s7[14])&&($f==1)){ $R[8]++; $f=0; print P15 $es; }
    if(($p =~ $s7[15])&&($f==1)){ $R[8]++; $f=0; print P16 $es; }
    if(($p =~ $s7[16])&&($f==1)){ $R[8]++; $f=0; print P17 $es; }
    if(($p =~ $s7[17])&&($f==1)){ $R[8]++; $f=0; print P18 $es; }
    if(($p =~ $s7[18])&&($f==1)){ $R[8]++; $f=0; print P19 $es; }
    if(($p =~ $s7[19])&&($f==1)){ $R[8]++; $f=0; print P20 $es; }
    if(($p =~ $s7[20])&&($f==1)){ $R[8]++; $f=0; print P21 $es; }
    if(($p =~ $s7[21])&&($f==1)){ $R[8]++; $f=0; print P22 $es; }
    if(($p =~ $s7[22])&&($f==1)){ $R[8]++; $f=0; print P23 $es; }
    if(($p =~ $s7[23])&&($f==1)){ $R[8]++; $f=0; print P24 $es; }
    if(($p =~ $s7[24])&&($f==1)){ $R[8]++; $f=0; print P25 $es; }
    if(($p =~ $s7[25])&&($f==1)){ $R[8]++; $f=0; print P26 $es; }
    if(($p =~ $s7[26])&&($f==1)){ $R[8]++; $f=0; print P27 $es; }
    if(($p =~ $s7[27])&&($f==1)){ $R[8]++; $f=0; print P28 $es; }
    if(($p =~ $s7[28])&&($f==1)){ $R[8]++; $f=0; print P29 $es; }
    if(($p =~ $s7[29])&&($f==1)){ $R[8]++; $f=0; print P30 $es; }
    if(($p =~ $s7[30])&&($f==1)){ $R[8]++; $f=0; print P31 $es; }
    if(($p =~ $s7[31])&&($f==1)){ $R[8]++; $f=0; print P32 $es; }
    if(($p =~ $s7[32])&&($f==1)){ $R[8]++; $f=0; print P33 $es; }
    if(($p =~ $s7[33])&&($f==1)){ $R[8]++; $f=0; print P34 $es; }
    if(($p =~ $s7[34])&&($f==1)){ $R[8]++; $f=0; print P35 $es; }
    if(($p =~ $s7[35])&&($f==1)){ $R[8]++; $f=0; print P36 $es; }
    if(($p =~ $s7[36])&&($f==1)){ $R[8]++; $f=0; print P37 $es; }
    if(($p =~ $s7[37])&&($f==1)){ $R[8]++; $f=0; print P38 $es; }
    if(($p =~ $s7[38])&&($f==1)){ $R[8]++; $f=0; print P39 $es; }
    if(($p =~ $s7[39])&&($f==1)){ $R[8]++; $f=0; print P40 $es; }
    if(($p =~ $s7[40])&&($f==1)){ $R[8]++; $f=0; print P41 $es; }
    if(($p =~ $s7[41])&&($f==1)){ $R[8]++; $f=0; print P42 $es; }
    if(($p =~ $s7[42])&&($f==1)){ $R[8]++; $f=0; print P43 $es; }
    if(($p =~ $s7[43])&&($f==1)){ $R[8]++; $f=0; print P44 $es; }
    if(($p =~ $s7[44])&&($f==1)){ $R[8]++; $f=0; print P45 $es; }
    if(($p =~ $s7[45])&&($f==1)){ $R[8]++; $f=0; print P46 $es; }
    if(($p =~ $s7[46])&&($f==1)){ $R[8]++; $f=0; print P47 $es; }
    if(($p =~ $s7[47])&&($f==1)){ $R[8]++; $f=0; print P48 $es; }
    
    if($f==1){ print PUN $ef; } else{ $R[0]++; }
  }
}

close(P01); close(P02); close(P03); close(P04); close(P05); close(P06); close(P07); close(P08);
close(P09); close(P10); close(P11); close(P12); close(P13); close(P14); close(P15); close(P16);
close(P17); close(P18); close(P19); close(P20); close(P21); close(P22); close(P23); close(P24);
close(P25); close(P26); close(P27); close(P28); close(P29); close(P30); close(P31); close(P32);
close(P33); close(P34); close(P35); close(P36); close(P37); close(P38); close(P39); close(P40);
close(P41); close(P42); close(P43); close(P44); close(P45); close(P46); close(P47); close(P48);
close(PUN); close(IN);

print "\n$num_seq sequences found in input.\n\nResult Sequences   :\n".join("\t",@R)."\n\n";

