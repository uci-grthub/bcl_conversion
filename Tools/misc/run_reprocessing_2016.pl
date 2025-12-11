#!/usr/bin/perl
use strict;

my $version1="$ARGV[0]";
my $version2="$ARGV[1]";
my $logfile="$ARGV[2]";

if(! -f "$version1"){
  print "cannot find file $version1\n"; exit 1; }
if(! -f "$version2"){
  print "cannot find file $version2\n"; exit 1; }
if(-f "$logfile"){
  print "log file $logfile already exist\n"; exit 1; }

open(IN1,"$version1");
open(IN2,"$version2");
open(LOG,">$logfile");

my $ofh = select LOG;
$| = 1; select $ofh;

my $num_reads_total=0;
my $num_reads_zeros=0;

print LOG "\n  Starting to compare the fastq files...\n\n";
while(my $l1=<IN1>){ chomp($l1);
  my $l2=<IN2>; chomp($l2);
  $num_reads_total++;
  if($l1 ne $l2){
    $num_reads_zeros++;
    my @S1=split(" ",$l1);
    my @S2=split(" ",$l2);
    if(($#S1!=1)||($#S2!=1)){
      print LOG "Inconsistent headers 1\n\n$l1\n$l2\n"; exit 1; }
    if($S1[1] ne $S2[1]){
      print LOG "Mismatch headers 2\n\n$l1\n$l2\n"; }
    my @T1=split(":",$S1[0]);
    my @T2=split(":",$S2[0]);
    if(($#T1!=6)||($#T2!=6)){
      print LOG "Inconsistent headers 3\n\n$l1\n$l2\n"; exit 1; }
    if((($T1[6] ne "0")&&($T1[6]!~/^[0-9]+$/))||($T2[6]!~/^[0-9]+$/)){
      print LOG "Inconsistent headers 4\n\n$l1\n$l2\n"; exit 1; }
    if((($T1[5] ne "0")&&($T1[5]!~/^[0-9]+$/))||($T2[5]!~/^[0-9]+$/)){
      print LOG "Inconsistent headers 5\n\n$l1\n$l2\n"; exit 1; }
    if(($T2[5] eq "0")&&($T2[6] eq "0")){
      print LOG "Inconsistent new fastq files\n\n$l2\n"; exit 1; }
    pop(@T1); pop(@T1); pop(@T2); pop(@T2);
    if(join(":",@T1) ne join(":",@T2)){
      print LOG "Inconsistent headers 6\n\n$l1\n$l2\n"; exit 1; } }
  $l1=<IN1>; $l2=<IN2>; if($l1 ne $l2){
    print LOG "Mismatch sequences:\n\n$l1\n$l2\n"; exit 1; }
  $l1=<IN1>; $l2=<IN2>; if($l1 ne $l2){
    print LOG "Mismatch third line:\n\n$l1\n$l2\n"; exit 1; }
  $l1=<IN1>; $l2=<IN2>; if($l1 ne $l2){
    print LOG "Mismatch scores:\n\n$l1\n$l2\n"; exit 1; }
  if(($num_reads_total%10000000)==0){
    my $p=sprintf("%.2f",($num_reads_zeros/$num_reads_total)*100);
    print LOG "  Processed $num_reads_total sequencing reads ($p% with zeros)\n"; } }

if(my $l=<IN2>){ print LOG "Mismatch file length\n"; exit 1; }
my $p=sprintf("%.2f",($num_reads_zeros/$num_reads_total)*100);
print LOG "\n  TOTAL READS = $num_reads_total WITH ZEROS = $num_reads_zeros ($p%)\n\n";
close(IN1); close(IN2); close(LOG); `chmod 770 $logfile`;

