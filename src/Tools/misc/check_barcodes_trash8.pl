#!/usr/bin/perl
use strict;

my $fastq = $ARGV[0]; open(FASTQ,"$fastq"); my %bcs;
while(my $line = <FASTQ>){ if($line =~ /^\@D980ZTR1/)
{
  chomp($line); my $bc=substr($line,-8);
  if($bc!~/^[ACNGT]{8}$/){ print "BC : $bc\n"; exit; }
  $bcs{"$bc"}++;
} }
close(FASTQ); my @list=keys(%bcs);
foreach my $e (@list){ if($bcs{"$e"}>=1000){
print "$e : ".$bcs{"$e"}."\n"; } }

