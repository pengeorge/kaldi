#!/usr/bin/perl
use strict;

use Encode;

my $thres = 0.1;
if ($#ARGV < 0 || $#ARGV > 1) {
  die "Usage: $0 lexicon [ threshold ]\n"
}

my $lexicon = $ARGV[0];
if ($#ARGV == 1) {
  $thres = $ARGV[1];
}

open(LEX, "$lexicon") or die;
my %words;
while(<LEX>) {
  chomp;
  my $line = decode('utf8', $_);
  my @col = split(/[\t ]/, $line); # separator may be \t or ' '
  $words{$col[0]} = 1;
}
while (<STDIN>) {
  chomp;
  my $line = decode('utf8', $_);
  my @col = split(/ /, $line);
  my $wnum = @col;
  my $onum = 0;
  foreach my $w (@col) {
    if (!defined($words{$w})) {
      $onum++;
    }
  }
  if ($onum/$wnum < $thres) {
    print encode('utf8', $line)."\n";
  }
  #printf "%d\t%d\t%.2f\n", $wnum, $onum, $onum/$wnum;
}
