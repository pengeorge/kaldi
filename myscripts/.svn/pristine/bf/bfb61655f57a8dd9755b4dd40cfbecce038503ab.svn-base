#!/usr/bin/perl
use strict;

use Encode;

my $thres = 5;
if ($#ARGV != 0) {
  die "Usage: $0 threshold \n"
}

my $thres = $ARGV[0];

my %cnt;
my @text;
while (<STDIN>) {
  chomp;
  push(@text, $_);
  my $line = decode('utf8', $_);
  my @col = split(/ /, $line);
  for my $w (@col) {
    if (!defined($cnt{$w})) {
      $cnt{$w} = 0;
    }
    $cnt{$w}++;
  }
}

for my $line (@text) {
  my $dcd = decode('utf8', $line);
  my @col = split(/ /, $dcd);
  my $toExclude = 0;
  for my $w (@col) {
    if ($cnt{$w} < $thres) {
      $toExclude = 1;
      last;
    }
  }
  if ($toExclude == 0) {
    print "$line\n";
  }
}
