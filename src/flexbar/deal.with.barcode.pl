#!usr/bin/perl -w
use strict;

@ARGV||die"perl $0 sample.info barcode.fa\n";
my ($in,$out)=@ARGV;
open IN,$in;
open OUT,">$out";
while(<IN>){
	chomp;
	my @a=split;
	print OUT ">$a[0]\n";
	my $b=$a[1];
	$b=~tr/ATCG/TAGC/;
	$b=reverse($b);
	print OUT "NNNNN$b","NNNN\n";
}
close OUT;
close IN;
