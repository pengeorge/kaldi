#!/bin/bash

# chenzp 2015
# Calulate the score difference of each word between 2 LMs.

set -e

lm1=$1
lm2=$2

perl -e '
  use strict;
  my %p1;
  my %p2;
  my $working = 0;
  open(LM1, "'<(gzip -cdf $lm1)'") or die;
  open(LM2, "'<(gzip -cdf $lm2)'") or die;
  while (<LM1>) {
    chomp;
    if (/1-grams:/) {
      $working = 1;
      next;
    }
    if ($_ eq "") {
      next;
    }
    if (/2-grams/) {
      last;
    }
    if ($working == 0) {
      next;
    }
    my @col = split(/\t/, $_);
    $p1{$col[1]} = $col[0];
  }
  while (<LM2>) {
    chomp;
    if (/1-grams:/) {
      $working = 1;
      next;
    }
    if ($_ eq "") {
      next;
    }
    if (/2-grams/) {
      last;
    }
    if ($working == 0) {
      next;
    }
    my @col = split(/\t/, $_);
    $p2{$col[1]} = $col[0];
  }
  foreach my $w (sort keys %p1) {
    print "$w\t".($p1{$w} - $p2{$w})."\n";
  }
'

