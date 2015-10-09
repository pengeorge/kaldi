#!/usr/bin/perl

use strict;

if ($#ARGV != 1) {
  die "Usage: $0 lex1 lex2\n";
}

my $lex1file = $ARGV[0];
my $lex2file = $ARGV[1];

if ($lex1file eq '-' && $lex2file eq '-') {
  die "Wrong parameters: $lex1file $lex2file\n";
}

my $lex1src;
my $lex2src;
if ($lex1file eq '-') {
  $lex1src = 'STDIN';
} else {
  open(LEX1, "<$lex1file") or die;
  $lex1src = 'LEX1';
}
if ($lex2file eq '-') {
  $lex2src = 'STDIN';
} else {
  open(LEX2, "<$lex2file") or die;
  $lex2src = 'LEX2';
}

my %lex2;

while (<$lex2src>) {
  chomp;
  my @col = split(/\t| /, $_);
  $lex2{$col[0]} = $_;
}
if ($lex2file ne '-') {
  close(LEX2);
}

while (<$lex1src>) {
  chomp;
  my @col = split(/\t| /, $_);
  if (!defined($lex2{$col[0]})) {
    print "$_\n";
  } else {
  }
}
if ($lex1file ne '-') {
  close(LEX1);
}
