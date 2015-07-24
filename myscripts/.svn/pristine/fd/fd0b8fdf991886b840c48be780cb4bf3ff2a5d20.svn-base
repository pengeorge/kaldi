#!/usr/bin/perl

use strict;
use warnings;

if ($#ARGV != 2) {
  die "Usage: $0 <word-list> <text> <output-tf-file> \n  e.g. $0 data/lang/words.txt data/train/text data/train/tf.txt > data/train/df.txt\n";
}

my $wlist = $ARGV[0];
my $text = $ARGV[1];
my $tffile = $ARGV[2];

open(WLIST, "$wlist") or die "can't open $wlist\n";
open(TEXT, "$text") or die "can't open $text\n";

my %word2idx;
my @widx2id;
my $idx = 0;
while (<WLIST>) {
  chomp;
  my @col = split(/ /, $_);
  if ($col[0] !~ m/^</ && $col[0] !~ m/^#/) {
    $word2idx{$col[0]} = $idx;
    push(@widx2id, $col[1]);
    $idx++;
  }
}

close(WLIST);

my $isSTM = 1;
if ($text =~ m/text$/) {
  $isSTM = 0;
}

my %tf;
my %df;
while (<TEXT>) {
  chomp;
  my @col = split(/ /, $_);
  my $doc = shift @col;
  if ($isSTM) {
    if ($doc =~ m/^;/) {
      next;
    }
    foreach (1..4) {shift @col; }
  } else {
    $doc =~ s/_\d+$//;
  }
  if (!defined($tf{$doc})) {
    @{$tf{$doc}} = (0)x$idx;
  }
  foreach my $w (@col) {
    if ($w =~ m/^</) { next; }
    $w =~ tr/[A-Z]/[a-z]/;
    if (!defined($word2idx{$w})) {
      print STDERR "Warning: unknown word $w\n";
      next;
    }
    if ($tf{$doc}[$word2idx{$w}] == 0) { # first occurrance of the word in the doc
      if (!defined($df{$w})) {
        $df{$w} = 0;
      }
      $df{$w}++;
    }
    $tf{$doc}[$word2idx{$w}]++;
  }
}

close(TEXT);

foreach my $word (sort keys %word2idx) {
  if (!defined($df{$word})) {
    print STDERR "Warning: df of $word is zero\n";
    $df{$word} = 0;
  }
}

print "".(scalar keys %tf)."\n";  # output #doc
foreach my $word (sort keys %df) {
  print "$word\t$word2idx{$word}\t$widx2id[$word2idx{$word}]\t$df{$word}\n";
}

open(TF, ">$tffile") or die "can't open $tffile\n";
foreach my $doc (sort keys %tf) {
  my $doc_print = $doc;
  if (!$isSTM) {
    $doc_print =~ s/^(\d+)_([A|B])_(\d+)_(\d+)$/BABEL_OP2_202_$1_$3_$4_$2/;
    $doc_print =~ s/A$/inLine/;
    $doc_print =~ s/B$/outLine/;
  }
  print TF "$doc_print";
  for (my $k = 0; $k < @{$tf{$doc}}; $k++) {
    if ($tf{$doc}[$k] != 0) {
      print TF " $k:$tf{$doc}[$k]";
    }
  }
  print TF "\n";
}
close(TF);

