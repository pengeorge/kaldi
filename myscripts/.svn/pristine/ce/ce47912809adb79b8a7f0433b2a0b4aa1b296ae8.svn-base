#!/usr/bin/perl

use strict;
use warnings;

my %tfidf;
my %sim;

while (<STDIN>) {
  chomp;
  my @col = split(/ /, $_);
  my $doc = shift @col;
  my $norm = 0;
  foreach my $pair (@col) {
    my ($idx, $val) = split(/:/, $pair);
    $tfidf{$doc}{$idx} = $val;
    # normalization
    $norm += $val * $val;
  }
  $norm = sqrt($norm);
  foreach my $idx (sort keys %{$tfidf{$doc}}) {
    $tfidf{$doc}{$idx} /= $norm;
  }
}

#

my @dockeys = sort keys %tfidf;
my @sim;
my $maxsim = -1;
my $minsim = 2;
for (my $i = 0; $i < @dockeys; $i++) {
  for (my $j = $i+1; $j < @dockeys; $j++) {
    $sim[$i][$j] = 0;
    foreach my $idx (sort keys %{$tfidf{$dockeys[$i]}}) {
      if (defined($tfidf{$dockeys[$j]}{$idx})) {
        $sim[$i][$j] += $tfidf{$dockeys[$i]}{$idx} * $tfidf{$dockeys[$j]}{$idx};
      }
    }
    $sim[$j][$i] = $sim[$i][$j];
    if ($sim[$i][$j] > $maxsim) {
      $maxsim = $sim[$i][$j];
    }
    if ($sim[$i][$j] < $minsim) {
      $minsim = $sim[$i][$j];
    }
  }
  $sim[$i][$i] = 1;
}

for (my $i = 0; $i < @dockeys; $i++) {
  for (my $j = $i+1; $j < @dockeys; $j++) {
    $sim[$i][$j] = ($sim[$i][$j] - $minsim) / ($maxsim - $minsim);
    $sim[$j][$i] = $sim[$i][$j];
  }
  $sim[$i][$i] = 1;
}

for (my $i = 0; $i < @dockeys; $i++) {
  my %this_sims;
  for (my $k = 0; $k < @dockeys; $k++) {
    if ($k != $i) {
      $this_sims{$dockeys[$k]} = $sim[$i][$k];
    }
  }
  print "$dockeys[$i]";
  foreach (sort { $this_sims{$b} <=> $this_sims{$a} } keys %this_sims) {
    print " $_:$this_sims{$_}";
  }
  print "\n";
}



