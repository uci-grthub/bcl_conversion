#!/usr/bin/perl
use strict;

if($#ARGV != 3){ print "Four parameters are required. Exit.\n"; exit; }
my $fastq = $ARGV[0]; my $output = $ARGV[1];
my $left=$ARGV[2]; my $right=$ARGV[3];
my $length = 0; my $num_seq = 0; my $line;

open(FASTQ,"$fastq");
open(OUT,">$output");

while($line = <FASTQ>)
{
  if($line =~ /\@/)
  {
    chomp($line);
    print OUT "$line\n";
    $line = <FASTQ>;
    chomp($line);
    if($num_seq==0){ $length = length($line); }
    my $seq=$line;
    if($left>0){ $seq=substr($seq,$left); }
    if($right>0){ $seq=substr($seq,0,-$right); }
    print OUT "$seq\n";
    $line = <FASTQ>;
    chomp($line);
    print OUT "$line\n";
    $line = <FASTQ>;
    chomp($line);
    my $scores=$line;
    if($left>0){ $scores=substr($scores,$left); }
    if($right>0){ $scores=substr($scores,0,-$right); }
    print OUT "$scores\n";
    $num_seq++;
  }
}

close(FASTQ);
close(OUT);
