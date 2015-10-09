#!/usr/bin/perl

use strict;

if (@ARGV != 1) {
  die "Usage: $0 <lexicon>\n";
}
my $lex = shift @ARGV;

my %w2s;
open(LEX, "<$lex") or die "Cannot open $lex\n";
while (<LEX>) {
  chomp;
  my @col = split(/\t/, $_);
  $w2s{$col[0]} = $col[1];
}
close(LEX);

while (<STDIN>) {
  chomp;
  my @col = split(/ /, $_);
  my $w = shift @col;
  if (defined($w2s{$w})) {
    print "$w2s{$w}";
  } else {
    print "$w";
  }
  while ($w = shift @col) {
    if (defined($w2s{$w})) {
      print " $w2s{$w}";
    } else {
      print " $w";
    }
  }
  print "\n";
}

