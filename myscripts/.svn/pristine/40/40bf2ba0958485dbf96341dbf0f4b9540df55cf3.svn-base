#!/usr/bin/perl

use strict;

if ($#ARGV != 1) {
  die "Usage: $0 lex1 lex2\n";
}

my $lex1file = $ARGV[0];
my $lex2file = $ARGV[1];
open(LEX1, "<$lex1file") or die;
open(LEX2, "<$lex2file") or die;

my %lex2;

while (<LEX2>) {
  chomp;
  my @col = split(/\t| /, $_);
  $lex2{$col[0]} = $_;
}
close(LEX2);

while (<LEX1>) {
  chomp;
  my @col = split(/\t| /, $_);
  if (!defined($lex2{$col[0]})) {
    print "$_\n";
  } else {
  }
}
close(LEX1);
