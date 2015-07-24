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

while (<STDIN>) {
  chomp;
  print "$_\t";
  my @col = split(/\t/, $_);
  if (defined($in_dev_hash{$col[0]})) {
    print "1\n";
  } else {
    print "0\n";
  }
}
