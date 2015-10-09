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

my %lex1;
my %lex2;
my @list1;
my @list2;

while (<$lex1src>) {
  chomp;
  my @col = split(/\t| /, $_);
  push(@list1, $col[0]);
  $lex1{$col[0]} = $_;
}
if ($lex1file ne '-') {
  close(LEX1);
}
while (<$lex2src>) {
  chomp;
  my @col = split(/\t| /, $_);
  push(@list2, $col[0]);
  $lex2{$col[0]} = $_;
}
if ($lex2file ne '-') {
  close(LEX2);
}

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


