#!/usr/bin/perl
use strict;

my $fastq = $ARGV[0]; open(FASTQ,"$fastq"); my %bcs;
while(my $line = <FASTQ>){ if($line =~ /^\@HISEQ-MFG/)
{
  chomp($line); my $bc=substr($line,-7);
  if($bc!~/^[ACNGT]{7}$/){ print "BC : $bc\n"; exit; }
  $bcs{"$bc"}++;
} }
close(FASTQ); my @list=keys(%bcs);
foreach my $e (@list){ if($bcs{"$e"}>=10000){
print "$e : ".$bcs{"$e"}."\n"; } }

