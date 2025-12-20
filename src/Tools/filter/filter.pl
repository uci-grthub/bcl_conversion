#!/usr/bin/perl

# filter

use strict;
use warnings;

 
# (1) quit unless we have the correct number of command-line args
my $num_args = $#ARGV + 1;
if ($num_args !=1) {
    print "\nUsage: filter.pl bc-list-file Unrecognized-file1\n";
    exit;
}

print "$ARGV[$0]\n";
print "$ARGV[$1]\n";

my $filename = 'bc-file.txt';
open(my $fh, '<:encoding(UTF-8)', $filename)
  or die "Could not open file '$filename' $!";
 
my $linecount=1;
while (my $row = <$fh>) {
  chomp $row;
  
  print "$row\n";
  print "$linecount\n";
  $linecount = $linecount +1;
}
