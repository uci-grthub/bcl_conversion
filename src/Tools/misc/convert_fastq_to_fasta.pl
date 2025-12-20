#!/usr/bin/env perl

my $fasta_file = $ARGV[0];
open (FASTA, '>'.$fasta_file) or die "Can't read file '$fasta_file' [$!]\n";

while (my $line = <STDIN>)
{
	print FASTA ">".substr($line,1);
	$line = <STDIN>;
	print FASTA "$line";
	$line = <STDIN>;
	$line = <STDIN>;
}

close (FASTA);

