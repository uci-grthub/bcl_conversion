#!/usr/bin/env perl
use strict;
use POSIX qw(strftime);

####################################################################################################

my $dryrun = 0;
my @new_argv = ();
foreach my $arg (@ARGV) {
    if ($arg eq "--dryrun") {
        $dryrun = 1;
    } else {
        push(@new_argv, $arg);
    }
}
@ARGV = @new_argv;

if(($#ARGV < 3) || ($#ARGV > 5) ){ print "\n  USAGE : ./postprocess_hiseq_lane.pl ";
  print "sample_sheet num_reads lane_number library_name [optional fastq directory, default output] [optional start S number, blank is S1] [--dryrun]\n\n"; exit 1; }
my $start_s_id=1;
my $fastqdir="output";
if($#ARGV>=4){ print "Using Fastq Directory of $ARGV[4] \n"; $fastqdir=$ARGV[4]}
if($#ARGV==5){ print "Using Start S number of $ARGV[5] \n"; $start_s_id=$ARGV[5]}
my $sample_sheet=$ARGV[0]; my $num_reads=$ARGV[1]; my $lane=$ARGV[2]; my $name=$ARGV[3]; 
if(! -f "$sample_sheet"){ print "Cannot find sample sheet\n"; exit 1; }
if(($num_reads!=1)&&($num_reads!=2)){ print "Num reads must be 1 or 2\n"; exit 1; }
if(!(($lane>=1)&&($lane<=8))){ print "Lane must between 1 and 8\n"; exit 1; }

# Setup logging
my $log_dir = "logs";
unless(-e $log_dir or mkdir $log_dir) {
    die "Unable to create $log_dir\n";
}
my $timestamp_fn = strftime "%Y%m%d_%H%M%S", localtime;
my $log_file = "$log_dir/${name}_${timestamp_fn}.log";
open(our $LOG_FH, '>', $log_file) or die "Could not open log file $log_file: $!";
log_msg("Log file created: $log_file");

my $process_single="Tools/analyze/analyze_single_reads_centos7_test-gzip.pl";
my $process_paired="Tools/analyze/analyze_paired_reads_centos7_test-gzip.pl";
my $start_time = time();
log_msg("Starting postprocess_hiseq_lane.pl with args: @ARGV");
print "Start id S number =$start_s_id\n";

####################################################################################################

# Load Sample Information
log_msg("Loading sample sheet: $sample_sheet");
my $is_barcoded=0; my $num_barcodes=0; my @barcodes; my @prefixes; my @projects; open(IN,"$sample_sheet");
if((my $l=<IN>)!~"Data"){ print "Incorrect file header"; exit 1; }
if((my $l=<IN>)!~"Project,Lane,Sample_ID"){ print "Incorrect file header"; exit 1; }
my $generic_sample_id="1"; my @generic;
while(my $l=<IN>){
  chomp($l); my @d=split(",",$l);
  if($d[1]==$lane){
    if($d[4] eq ""){ my $prefix=$d[2];
      if(($is_barcoded!=0)||($num_barcodes!=0)){
        print "Inconsistent sample sheet\n"; exit 1; }
      if($prefix!~/^R[0-9]{3}-L$lane$/){
        print "Inconsistent sample prefix.\n"; exit 1; }
      push(@prefixes,"$prefix"); }
    else{ $is_barcoded=1; $num_barcodes++;
      if($d[5] eq ""){ push(@barcodes,"$d[4]"); }
      else{ push(@barcodes,"$d[4]-$d[5]"); }
      push(@prefixes,"$d[2]");
      push(@projects,"$d[0]");
      push(@generic,"$generic_sample_id"); } }
      print "in check $d[2] \n";
  $generic_sample_id++; } close(IN);

####################################################################################################

# Process Lane (Case Not Multiplexed)
if($is_barcoded==0)
{
  print "Samples not barcoded : write corresponding code\n"; exit 1;
}

####################################################################################################

# Process Lane (Case Multiplexed)
else{
  print "\n  Found $num_barcodes Barcodes For Lane $lane ($name)\n\n";
  my %project_counters;
  for(my $i=0;$i<$num_barcodes;$i++){
    my $project=$projects[$i]; $project_counters{$project}++;
    my $barcode=$barcodes[$i]; my $prefix=$prefixes[$i]; 
    my $sample_id_in_project=$project_counters{$project};
    my $genid=$generic[$i] + $start_s_id - 1;
    print "  Processing Library \"$name\" - Barcode $barcode ($prefix)... genid=${genid} \n";
    log_msg("Processing Library \"$name\" - Barcode $barcode ($prefix)... genid=${genid}");
    my $file_in_R1="${fastqdir}/${project}/${prefix}_S${genid}_L00${lane}_R1_001.fastq.gz";
    my $file_in_R2="${fastqdir}/${project}/${prefix}_S${genid}_L00${lane}_R2_001.fastq.gz";
    
    ################################################################################################
    
    if($num_reads==1){
      my $file_out="${fastqdir}/${project}/${prefix}-${barcode}_S${genid}_L00${lane}_R1_001.fastq.gz";
      
      if(! -f "$file_in_R1" && ! -f "$file_out"){ print "Cannot find fastq file 1 $file_in_R1 or output $file_out \n"; exit 1; }

      if($dryrun){
          if (-f "$file_in_R1") {
             print "DRYRUN: mv $file_in_R1 $file_out\n";
          } else {
             print "DRYRUN: Input $file_in_R1 missing, using existing $file_out\n";
          }
          print "DRYRUN: perl $process_single $file_out ${prefix}-${barcode} \"$name\"\n";
          print "DRYRUN: chmod 770 $prefix*\n";
          print "DRYRUN: chmod 770 $file_out\n";
          print "DRYRUN: md5sum $file_out >> md5sum_lane$lane.txt\n";
      } else {
          if (-f "$file_in_R1") {
              log_msg("Moving $file_in_R1 to $file_out");
              `mv $file_in_R1 $file_out`;
          } else {
              log_msg("Input $file_in_R1 missing, using existing $file_out");
          }
          log_msg("Running process_single: perl $process_single $file_out ${fastqdir}/${project}/${prefix}-${barcode} \"$name\"");
          `perl $process_single $file_out ${fastqdir}/${project}/${prefix}-${barcode} \"$name\"`;
          log_msg("Changing permissions for $prefix* and $file_out");
          `chmod 770 ${fastqdir}/${project}/$prefix*`; `chmod 770 $file_out`;
          print "case A $file_out ";
          log_msg("Calculating md5sum for $file_out");
          `md5sum $file_out >> md5sum_lane$lane.txt`; 
      }
    }
    
    ################################################################################################
    
    elsif($num_reads==2){
      my $file_out_R1="${fastqdir}/${project}/${prefix}-${barcode}_S${genid}_L00${lane}_R1_001.fastq.gz";
      my $file_out_R2="${fastqdir}/${project}/${prefix}-${barcode}_S${genid}_L00${lane}_R2_001.fastq.gz";

      if(! -f "$file_in_R1" && ! -f "$file_out_R1"){ print "Cannot find fastq file 1 $file_in_R1 or output $file_out_R1 \n"; exit 1; }
      if(! -f "$file_in_R2" && ! -f "$file_out_R2"){ print "Cannot find fastq file 2 $file_in_R2 or output $file_out_R2 \n"; exit 1; }

      if($dryrun){
          if (-f "$file_in_R1") {
              print "DRYRUN: mv $file_in_R1 $file_out_R1\n";
          } else {
              print "DRYRUN: Input $file_in_R1 missing, using existing $file_out_R1\n";
          }
          if (-f "$file_in_R2") {
              print "DRYRUN: mv $file_in_R2 $file_out_R2\n";
          } else {
              print "DRYRUN: Input $file_in_R2 missing, using existing $file_out_R2\n";
          }
          print "DRYRUN: perl $process_paired $file_out_R1 $file_out_R2 ${fastqdir}/${project}/${prefix}-${barcode} \"$name\"\n";
          print "DRYRUN: chmod 770 ${fastqdir}/${project}/$prefix*\n";
          print "DRYRUN: chmod 770 $file_out_R1\n";
          print "DRYRUN: chmod 770 $file_out_R2\n";
          print "DRYRUN: md5sum $file_out_R1 >> md5sum_lane$lane.txt\n";
          print "DRYRUN: md5sum $file_out_R2 >> md5sum_lane$lane.txt\n";
      } else {
          if (-f "$file_in_R1") {
              log_msg("Moving $file_in_R1 to $file_out_R1");
              `mv $file_in_R1 $file_out_R1`;
          } else {
              log_msg("Input $file_in_R1 missing, using existing $file_out_R1");
          }
          if (-f "$file_in_R2") {
              log_msg("Moving $file_in_R2 to $file_out_R2");
              `mv $file_in_R2 $file_out_R2`;
          } else {
              log_msg("Input $file_in_R2 missing, using existing $file_out_R2");
          }
          log_msg("Running process_paired: perl $process_paired $file_out_R1 $file_out_R2 ${fastqdir}/${project}/${prefix}-${barcode} \"$name\"");
          `perl $process_paired $file_out_R1 $file_out_R2 ${fastqdir}/${project}/${prefix}-${barcode} \"$name\"`;
          log_msg("Changing permissions for ${fastqdir}/${project}/$prefix*, $file_out_R1, $file_out_R2");
          `chmod 770 ${fastqdir}/${project}/$prefix*`; 
          `chmod 770 $file_out_R1`;
          `chmod 770 $file_out_R2`;
          log_msg("Calculating md5sum for $file_out_R1 and $file_out_R2");
          `md5sum $file_out_R1 >> md5sum_lane$lane.txt`;
          `md5sum $file_out_R2 >> md5sum_lane$lane.txt`; 
      }
    } }
  
  ##################################################################################################
  
  my @d=split("-",$prefixes[0]); my $prefix="$d[0]-$d[1]";
  if($prefix!~/^(4R|mR|nR|xR|R)[0-9]{3}-L$lane$/){ print "Cannot process trash\n"; exit 0; }
  $prefix="$prefix-PrNotRecog";
  print "  Processing Library \"$name\" - Barcode Not Recognized ($prefix)...\n";
  my $file_in_R1="${fastqdir}/Undetermined_S0_L00${lane}_R1_001.fastq.gz";
  my $file_in_R2="${fastqdir}/Undetermined_S0_L00${lane}_R2_001.fastq.gz";
  if(! -f "$file_in_R1"){ print "Cannot find fastq file\n"; exit 1; }
  if(($num_reads==2)&&(! -f "$file_in_R2")){ print "Cannot find fastq file\n"; exit 1; }
  
  ##################################################################################################
  
  my $project="Undetermined_indices";
  my $barcode="Undetermined";
  my $genid="0";

  if($num_reads==1){
    my $file_out="${fastqdir}/${project}/${prefix}-${barcode}_S${genid}_L00${lane}_R1_001.fastq.gz";
    
    if(! -f "$file_in_R1" && ! -f "$file_out"){ print "Cannot find fastq file 1 $file_in_R1 or output $file_out \n"; exit 1; }

    if($dryrun){
        if (-f "$file_in_R1") {
            print "DRYRUN: mv $file_in_R1 $file_out\n";
        } else {
            print "DRYRUN: Input $file_in_R1 missing, using existing $file_out\n";
        }
        print "DRYRUN: perl $process_single $file_out ${prefix} \"$name\"\n";
        print "DRYRUN: chmod 770 $prefix*\n";
        print "DRYRUN: chmod 770 $file_out\n";
        print "DRYRUN: md5sum $file_out >> md5sum_lane$lane.txt\n";
    } else {
        if (-f "$file_in_R1") {
            log_msg("Moving $file_in_R1 to $file_out");
            `mv $file_in_R1 $file_out`;
        } else {
            log_msg("Input $file_in_R1 missing, using existing $file_out");
        }
        log_msg("Running process_single: perl $process_single $file_out ${prefix} \"$name\"");
        `perl $process_single $file_out ${prefix} \"$name\"`;
        log_msg("Changing permissions for $prefix* and $file_out");
        `chmod 770 ${fastqdir}/${project}/$prefix*`; `chmod 770 $file_out`;
        print "case B $file_out ";
        log_msg("Calculating md5sum for $file_out");
        `md5sum $file_out >> md5sum_lane$lane.txt`; 
    }
  }
  
  ##################################################################################################
  
  elsif($num_reads==2){
    my $file_out_R1="${fastqdir}/${project}/${prefix}-${barcode}_S${genid}_L00${lane}_R1_001.fastq.gz";
    my $file_out_R2="${fastqdir}/${project}/${prefix}-${barcode}_S${genid}_L00${lane}_R2_001.fastq.gz";

    if(! -f "$file_in_R1" && ! -f "$file_out_R1"){ print "Cannot find fastq file 1 $file_in_R1 or output $file_out_R1 \n"; exit 1; }
    if(! -f "$file_in_R2" && ! -f "$file_out_R2"){ print "Cannot find fastq file 2 $file_in_R2 or output $file_out_R2 \n"; exit 1; }

    if($dryrun){
        if (-f "$file_in_R1") {
            print "DRYRUN: mv $file_in_R1 $file_out_R1\n";
        } else {
            print "DRYRUN: Input $file_in_R1 missing, using existing $file_out_R1\n";
        }
        if (-f "$file_in_R2") {
            print "DRYRUN: mv $file_in_R2 $file_out_R2\n";
        } else {
            print "DRYRUN: Input $file_in_R2 missing, using existing $file_out_R2\n";
        }
        print "DRYRUN: perl $process_paired $file_out_R1 $file_out_R2 ${prefix} \"$name\"\n";
        print "DRYRUN: chmod 770 $prefix*\n";
        print "DRYRUN: chmod 770 $file_out_R1\n";
        print "DRYRUN: chmod 770 $file_out_R2\n";
        print "DRYRUN: md5sum $file_out_R1 >> md5sum_lane$lane.txt\n";
        print "DRYRUN: md5sum $file_out_R2 >> md5sum_lane$lane.txt\n";
    } else {
        if (-f "$file_in_R1") {
            log_msg("Moving $file_in_R1 to $file_out_R1");
            `mv $file_in_R1 $file_out_R1`;
        } else {
            log_msg("Input $file_in_R1 missing, using existing $file_out_R1");
        }
        if (-f "$file_in_R2") {
            log_msg("Moving $file_in_R2 to $file_out_R2");
            `mv $file_in_R2 $file_out_R2`;
        } else {
            log_msg("Input $file_in_R2 missing, using existing $file_out_R2");
        }
        log_msg("Running process_paired: perl $process_paired $file_out_R1 $file_out_R2 ${prefix} \"$name\"");
        `perl $process_paired $file_out_R1 $file_out_R2 ${prefix} \"$name\"`;
        log_msg("Changing permissions for $prefix*, $file_out_R1, $file_out_R2");
        `chmod 770 $prefix*`; 
        `chmod 770 $file_out_R1`;
        `chmod 770 $file_out_R2`;
        log_msg("Calculating md5sum for $file_out_R1 and $file_out_R2");
        `md5sum $file_out_R1 >> md5sum_lane$lane.txt`;
        `md5sum $file_out_R2 >> md5sum_lane$lane.txt`; 
    }
  }
}

my $end_time = time();
my $duration = $end_time - $start_time;
my $duration_str = sprintf("%02d:%02d:%02d", int($duration / 3600), int(($duration % 3600) / 60), int($duration % 60));
log_msg("Finished postprocess_hiseq_lane.pl. Total runtime: $duration_str");
close($LOG_FH) if defined $LOG_FH;

####################################################################################################

sub log_msg {
    my ($msg) = @_;
    my $timestamp = strftime "%Y-%m-%d %H:%M:%S", localtime;
    print "[$timestamp] $msg\n";
    if (defined $LOG_FH) {
        print $LOG_FH "[$timestamp] $msg\n";
    }
}

