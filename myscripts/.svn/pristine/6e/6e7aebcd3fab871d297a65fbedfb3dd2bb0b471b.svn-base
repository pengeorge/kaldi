#!/usr/bin/perl
use strict;

use Encode;

my $thres_en = 0.4;
my $thres_sw = 0.2;
if ($#ARGV < 1 || $#ARGV > 3) {
  die "Usage: $0 english_word_list swahili_word_list [ threshold_en threshold_sw ]\n"
}

my $enlex = $ARGV[0];
my $swlex = $ARGV[1];
if ($#ARGV >= 2) {
  $thres_en = $ARGV[2];
  if ($#ARGV == 3) {
    $thres_sw = $ARGV[3];
  }
}

open(ENLEX, "$enlex") or die;
my %enWords;
while(<ENLEX>) {
  chomp;
  my $line = decode('utf8', $_);
  my @col = split(/[\t ]/, $line); # separator may be \t or ' '
  $enWords{$col[0]} = 1;
}
close(ENLEX);
open(SWLEX, "$swlex") or die;
my %swWords;
while(<SWLEX>) {
  chomp;
  my $line = decode('utf8', $_);
  my @col = split(/[\t ]/, $line); # separator may be \t or ' '
  $swWords{$col[0]} = 1;
}
close(SWLEX);

while (<STDIN>) {
  chomp;
  my $line = decode('utf8', $_);
  my @col = split(/ /, $line);
  my $wNum = @col;
  my $enNum = 0;
  my $swNum = 0;
  my $commonNum = 0;
  foreach my $w (@col) {
    if (defined($enWords{$w})) {
      $enNum++;
    }
    if (defined($swWords{$w})) {
      $swNum++;
    }
    if (defined($enWords{$w}) && defined($swWords{$w})) {
      $commonNum++;
    }
  }
  if ($swNum / $wNum >= $thres_sw || $enNum / $wNum <= $thres_en) {
    #printf "%d\t%d\t%d\t%d\t%s\n", $swNum, $enNum, $commonNum, $wNum, $_;
    print "$_\n";
  }
}
