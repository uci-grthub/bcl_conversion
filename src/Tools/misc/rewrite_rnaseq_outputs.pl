#!/usr/bin/perl
use strict;

####################################################################################################

open(IN,"Indels.tsv");
open(OUT,">Indels-New.tsv");
my $header1=<IN>;
chomp($header1);
my @d1=split(" ",$header1);
shift(@d1);
shift(@d1);
print OUT join("\t",@d1)."\n";
while(my $l=<IN>)
{
  chomp($l);
  print OUT "$l\n";
}
close(OUT);
close(IN);
`chmod 770 Indels-New.tsv; rm -rf Indels.tsv; mv Indels-New.tsv Indels.tsv`;

####################################################################################################

open(IN,"SNPs.tsv");
open(OUT,">SNPs-New.tsv");
my $header2=<IN>;
chomp($header2);
my @d2=split(" ",$header2);
shift(@d2);
shift(@d2);
print OUT join("\t",@d2)."\n";
while(my $l=<IN>)
{
  chomp($l);
  my @d=split("\t",$l);
  if($d[5]>=12){
    print OUT "$l\n"; }
}
close(OUT);
close(IN);
`chmod 770 SNPs-New.tsv; rm -rf SNPs.tsv; mv SNPs-New.tsv SNPs.tsv`;

####################################################################################################

open(IN,"RPKM-Exons.tsv");
open(OUT,">RPKM-Exons-New.tsv");
print OUT "Chromosome\tStart Position\tStop Position\tGene\tRPKM Value\tRaw Count\n";
while(my $l=<IN>)
{
  chomp($l);
  print OUT "$l\n";
}
close(OUT);
close(IN);
`chmod 770 RPKM-Exons-New.tsv; rm -rf RPKM-Exons.tsv; mv RPKM-Exons-New.tsv RPKM-Exons.tsv`;

####################################################################################################

open(IN,"RPKM-Genes.tsv");
open(OUT,">RPKM-Genes-New.tsv");
print OUT "Chromosome\tStart Position\tStop Position\tGene\tRPKM Value\tRaw Count\n";
while(my $l=<IN>)
{
  chomp($l);
  print OUT "$l\n";
}
close(OUT);
close(IN);
`chmod 770 RPKM-Genes-New.tsv; rm -rf RPKM-Genes.tsv; mv RPKM-Genes-New.tsv RPKM-Genes.tsv`;

####################################################################################################

open(IN,"RPKM-Junctions.tsv");
open(OUT,">RPKM-Junctions-New.tsv");
print OUT "Chromosome\tLeftStop\tRightStart\tGene_LeftBases_RightBases_";
print OUT "Chr_LeftStop_RightStart\tRPKM Value\tRaw Count\n";
while(my $l=<IN>)
{
  chomp($l);
  print OUT "$l\n";
}
close(OUT);
close(IN);
`chmod 770 RPKM-Junctions-New.tsv; rm -rf RPKM-Junctions.tsv`;
`mv RPKM-Junctions-New.tsv RPKM-Junctions.tsv`;

####################################################################################################

