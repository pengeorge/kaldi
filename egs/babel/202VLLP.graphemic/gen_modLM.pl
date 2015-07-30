#!/usr/bin/perl

use strict;
if ($#ARGV != 1) {
  die "Usage: $0 <in-LM> lambda < ppl-info-file\n";
}
my $lambda = $ARGV[1];

my %score;
my $totalProb = 0;
my $numOOC = 0;
while (<STDIN>) {
  chomp;
  my @col = split(/\t/, $_);
  my $s = -$col[2];
  #print STDERR "$col[0]\t$s\n";
  $score{$col[0]} = $s;
  $totalProb += 10 ** $s;
  $numOOC++;
}
my $log10 = log(10);
my $logNumOOC = log($numOOC) / $log10;
my $logTotalProb = log($totalProb) / $log10;
print STDERR "log(|OOC|) = $logNumOOC\n";
print STDERR "log(total prob) = $logTotalProb\n";
my $logPooc = 0;
open(LM, "$ARGV[0]") or die;
my $operating = 0;
my %cp;
my %bow;
my $smax = -100;
my $smax_w;
my %snorm;
my $minIC = 100; # Q
my $minIC_w;

while (<LM>) {
  chomp;
  if ($operating == 0) {
    if ($_ =~ m/\\1\-grams/) {
      $operating = 1;
    }
    print "$_\n";
    next;
  } else {
    if ($_ eq "") {
      $operating = 0;
      last;
    }
    my @col = split(/\t/, $_);
    $cp{$col[1]} = $col[0];
    if (@col > 2) {
      $bow{$col[1]} = $col[2];
    }
    if (defined($score{$col[1]})) {
      if ($logPooc == 0) {
        $logPooc = $col[0];
      }
      $cp{$col[1]} = $score{$col[1]} + $logPooc
                + $logNumOOC - $logTotalProb;
      $snorm{$col[1]} = $cp{$col[1]};
      if ($snorm{$col[1]} > $smax) {
        $smax = $snorm{$col[1]};
        $smax_w = $col[1];
      }
    } else {
      if ($col[0] < $minIC) {
        if ($col[1] ne '<s>') {
          $minIC = $col[0];
          $minIC_w = $col[1];
        }
      }
    }
  }
}
print STDERR "max_OOC log P(w) = log P($smax_w) = $smax\n";
print STDERR "min_IC log P(w) = log P($minIC_w) = $minIC\n";
$minIC = $lambda * $minIC + (1 - $lambda) * $logPooc;
print STDERR "min_IC = lambda * (min_IC - log Pooc) + log Pooc = $minIC\n";

# Looking for solution
my $bmin = 0.0;
my $bmax = 1.0;
my $target = $logNumOOC + $logPooc - $minIC;
my @sorted_keys_snorm = sort {$snorm{$a} <=> $snorm{$b}} keys %snorm;
my %log_pw_div_pm;
foreach my $w (@sorted_keys_snorm) {
  $log_pw_div_pm{$w} = $snorm{$w} - $smax;
}
my $result = $target + 1;
my $b = 0;
print STDERR "Looking for solution of alpha, beta.......\n";
do {
  if ($result > $target) {
    $bmin = $b;
  } elsif ($result < $target) {
    $bmax = $b;
  }
  $b = ($bmin + $bmax) / 2;
  my $bnormSum = 0;
  foreach my $w (@sorted_keys_snorm) {
    $bnormSum += 10 ** ($b * $log_pw_div_pm{$w});
  }
  $result = log($bnormSum) / $log10;
  print STDERR "b = $b, result = $result, diff = ".($result - $target)."\n";
} while (abs($result - $target) > 0.01);
 
my $log_a = $minIC - $b * $smax;

print STDERR "log(alpha) = $log_a\n";
print STDERR "beta = $b\n";
print STDERR "P'(w) = alpha * P(w)^beta\n";

# Output
for my $w (sort keys %cp) {
  if (!defined($snorm{$w})) {
    print "$cp{$w}\t$w";
  } else {
    $cp{$w} = $b * $cp{$w} + $log_a;
    printf "%.6f\t%s", $cp{$w}, $w;
  }
  if (defined($bow{$w}) && $bow{$w} ne '') {
    print "\t$bow{$w}";
  }
  print "\n";
}
print "\n";
while (<LM>) {
  print $_;
}

close(LM);
