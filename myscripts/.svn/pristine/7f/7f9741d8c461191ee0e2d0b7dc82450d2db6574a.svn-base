#!/bin/bash

set -e

if [ $# != 3 ]; then
  echo "Usage: $0 <word-list> <web-lm> <outfile>"
  exit 1
fi
wlist=$1
weblm=$2
out=$3

gzip -cdf $weblm | perl -e '
  use strict;
  my %list;
  open(LIST, "$ARGV[0]") or die;
  while (<LIST>) {
    chomp;
    my @col = split(/\t/, $_);
    $list{$col[0]} = 1;
  }
  close(LIST);
  my $working = 0;
  while (<STDIN>) {
    chomp;
    if ($working == 0) {
      if (m/^\\1-gram/) {
        $working = 1;
      }
      next;
    } elsif (m/\\2-gram/) {
      last;
    }
    my @col = split(/\t/, $_);
    if (defined($list{$col[1]})) {
      $list{$col[1]} = $col[0];
    }
  }
  foreach my $w (sort keys %list) {
    print "$w\t$list{$w}\n";
  }  ' $wlist > $out

