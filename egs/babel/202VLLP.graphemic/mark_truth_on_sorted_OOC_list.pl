#!/usr/bin/perl

use strict;

my $dev = $ARGV[0];
my %in_dev_hash;
open(DEV, "$dev") or die;
while (<DEV>) {
  chomp;
  my @col = split(/\t/, $_);
  $in_dev_hash{$col[0]} = 1;
}
close(DEV);

open(COVER, ">$ARGV[1]") or die;
my $interval = 1000;
my $hit = 0;
my $k = 0;
while (<STDIN>) {
  $k++;
  chomp;
  print "$_\t";
  my @col = split(/\t/, $_);
  if (defined($in_dev_hash{$col[1]})) {
    print "1\n";
    $hit++;
  } else {
    print "0\n";
  }
  if ($k % $interval == 0) {
    print COVER "$hit\n";
  }
}
print COVER "$hit\n";
