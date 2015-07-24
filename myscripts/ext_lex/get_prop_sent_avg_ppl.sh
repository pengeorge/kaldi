#!/bin/bash
set -e

if [ $# != 3 ]; then
  echo "Usage: $0 <word-list> <LM-corpus-file> <outfile>"
  exit 1
fi
wlist=$1
corpus=$2
out=$3

corpus_ext=`basename $corpus`
./czpScripts/ext_lex/calc_sent_ppl.sh --src $corpus_ext \
  --lmdir data/srilm_kn --srclm-flag kn

gzip -cdf data/extra_text/kn.${corpus_ext}/${corpus_ext}.sw.mode1.sorted.gz | perl -e '
  use strict;
  my %ppl;
  my %oovRate;
  my %num;
  open(LIST, "$ARGV[0]") or die;
  while (<LIST>) {
    chomp;
    my @col = split(/\t/, $_);
    $ppl{$col[0]} = 0;
    $oovRate{$col[0]} = 0;
    $num{$col[0]} = 0;
  }
  close(LIST);

  my %vllplist;
  open(VLLPLIST, "$ARGV[1]") or die;
  while (<VLLPLIST>) {
    chomp;
    my @col = split(/\t/, $_);
    $vllplist{$col[0]} = 1;
  }
  close(VLLPLIST);
  while (<STDIN>) {
    chomp;
    my @col = split(/\t/, $_);
    my $score = $col[0];
    @col = split(/ +/, $col[1]);
    my %exist = ();
    my $n = 0;
    my $noov = 0;
    while (my $w = shift @col) {
      if (defined($ppl{$w})) {
        $exist{$w} = 1;
      }
      if (!defined($vllplist{$w})) {
        $noov++;
      }
      $n++;
    }
    my $thisOOVRate = ($n > 0) ? $noov / $n : 1;
    foreach my $w (keys %exist) {
      $ppl{$w} += $score;
      $oovRate{$w} += $thisOOVRate;
      $num{$w}++;
    }
  }
  foreach my $w (sort keys %ppl) {
    if ($num{$w} > 0) {
      printf "%s\t%f\t%f\n", $w, $ppl{$w} / $num{$w}, $oovRate{$w}/$num{$w};
    }
  }  ' $wlist data/extra_lexicon/VLLP > $out


