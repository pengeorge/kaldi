#!/bin/bash

set -e

# chenzp 2015
# This is an earlier version of modify OOC prob, deprecated. See modify_OOC_prob2.sh.

inlm=./data/srilm_bbnucoluc100w5+.kn/lm.gz
outlm=./data/srilm_bbnucoluc100w5+.knModOOCbyPPL/lm.gz
score_file=./ppl_info.txt

. ./utils/parse_options.sh

mkdir -p `dirname $outlm`
./czpScripts/prep_lex/lexicon_subtraction.pl \
  $score_file ./data/extra_lexicon/VLLP \
  | sort -nr -k 3 | perl -e '
    use strict;
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
    my $logNumOOC = log($numOOC) / log(10);
    my $logTotalProb = log($totalProb) / log(10);
    print STDERR "log(|OOC|) = $logNumOOC\n";
    print STDERR "log(total prob) = $logTotalProb\n";
    my $logPooc = 0;
    open(LM, "$ARGV[0]") or die;
    my $operating = 0;
    while (<LM>) {
      chomp;
      if ($operating == 0) {
        if ($_ =~ m/\\1\-grams/) {
          $operating = 1;
        }
        print "$_\n";
        next;
      } else {
        if ($_ =~ m/\\2\-grams/) {
          $operating = 0;
        } elsif ($_ eq "") {
          print "\n";
          next;
        }
        my @col = split(/\t/, $_);
        if (defined($score{$col[1]})) {
          if ($logPooc == 0) {
            $logPooc = $col[0];
          }
          $col[0] = $score{$col[1]} + $logPooc
                    + $logNumOOC - $logTotalProb;
          printf "%.6f", $col[0];
          for (my $i = 1; $i<@col; $i++) {
            print "\t$col[$i]";
          }
          print "\n";
        } else {
          print "$_\n";
        }
      }
    }
    close(LM);
  ' <(gzip -cdf $inlm) | gzip -c - > $outlm
