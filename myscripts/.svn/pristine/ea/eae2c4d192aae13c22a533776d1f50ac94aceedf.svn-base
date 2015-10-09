#!/usr/bin/perl
use strict;

use Encode;

my $thres = 5;
if ($#ARGV != 1) {
  die "Usage: $0 <text> threshold < input_lex > output_lex\n"
}

my $textfile = $ARGV[0];
my $thres = $ARGV[1];

my %cnt;
my @text;
open(TEXT, "$textfile") or die "Cannot open text file: $textfile\n";
while (<TEXT>) {
  chomp;
  my $line = decode('utf8', $_);
  my @col = split(/ /, $line);
  for my $w (@col) {
    if (!defined($cnt{$w})) {
      $cnt{$w} = 0;
    }
    $cnt{$w}++;
  }
}

while (<STDIN>) {
  chomp;
  my $dcd = decode('utf8', $_);
  my @col = split(/\t/, $dcd);
  my $w = $col[0];
  if ($cnt{$w} >= $thres) {
    print encode('utf8', $dcd)."\n";
  }
}
