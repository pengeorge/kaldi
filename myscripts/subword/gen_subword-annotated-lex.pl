#!/bin/perl 
#
use strict;

if ($#ARGV != 1) {
  die "Usage: $0 <original-lexicon> <pron-seg-file>\n";
}

my $flex = $ARGV[0];
my $fseg = $ARGV[1];

my %seg;

open(SEG, "$fseg") or die "Cannot open pron-seg-file $fseg\n";

while (my $psegged = <SEG>) {
  chomp($psegged);
  my $pseq = $psegged;
  $pseq =~ s/ \. / /g;
  $seg{$pseq} = $psegged;
}
close(SEG);

open(LEX, "$flex") or die "Cannot open original-lexicon $flex\n";
while (<LEX>) {
  chomp;
  my @col = split(/\t/, $_);
  my $word = shift @col;
  print $word;
  #shift @col; # for romanized
  while (my $p = shift @col) {
    $p =~ s/ \. / /g;
    $p =~ s/ # / /g;
    if (!defined($seg{$p})) {
      die "Cannot find $p in seg\n"
    }
    print "\t$seg{$p}";
  }
  print "\n"
}
close(LEX);

