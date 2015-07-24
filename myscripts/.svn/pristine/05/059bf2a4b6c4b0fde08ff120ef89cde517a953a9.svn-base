#!/usr/bin/perl

use strict;

if ($#ARGV != 1) {
  die "Usage: $0 lex1 lex2\n";
}

my $lex1file = $ARGV[0];
my $lex2file = $ARGV[1];
open(LEX1, "<$lex1file") or die;
open(LEX2, "<$lex2file") or die;

my %lex1;
my %lex2;
my @list1;
my @list2;

while (<LEX1>) {
  chomp;
  my @col = split(/\t| /, $_);
  push(@list1, $col[0]);
  $lex1{$col[0]} = $_;
}
close(LEX1);
while (<LEX2>) {
  chomp;
  my @col = split(/\t| /, $_);
  push(@list2, $col[0]);
  $lex2{$col[0]} = $_;
}
close(LEX2);

my @olist1 = sort @list1;
my @olist2 = sort @list2;

my $i = 0;
my $j = 0;
my $w1;
my $w2;
my $skip1 = 0;
my $skip2 = 0;

while (defined($olist1[$i]) && defined($olist2[$j])) {
  if ($olist1[$i] lt $olist2[$j]) {
    #print STDERR "$olist1[$i] < $olist2[$j]\n";
    $i++;
  } elsif ($olist1[$i] gt $olist2[$j]) {
    #print STDERR "$olist1[$i] > $olist2[$j]\n";
    $j++;
  } else {
    print "$lex1{$olist1[$i]}\n";
    $i++;
    $j++;
  }
}


