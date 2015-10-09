#!/bin/bash

set -e

. path.sh
export PATH=$KALDI_ROOT/tools/srilm/bin/i686-m64:$PATH
. lang.conf
. local.conf
. ./utils/parse_options.sh

if [ $# -ne 3 ]; then
  echo "Usage: $0 <word-lexicon> <in-domain-lexicon> <outfile>"
  exit 1;
fi

out_domain_lex=$1
in_domain_lex=$2
out=$3
dir=exp/OOV_phone_ppl
lmdir=$dir/$(basename $in_domain_lex)_phone_lm

mkdir -p $lmdir

if [ ! -f $lmdir/.done ]; then
  cut -f 2 $in_domain_lex | perl -e '
  #The phonemap is in the form of "ph1=a b c;ph2=a f g;....
  $phonemap = $ARGV[0];
  my %phonemap_hash;
  if ($phonemap) {
    $phonemap=join(" ", split(/\s+/, $phonemap));
    my @phone_map_instances=split(/;/, $phonemap);
    foreach my $instance (@phone_map_instances) {
      my ($phoneme, $tgt) = split(/=/, $instance);
      $phoneme =~ s/^\s+|\s+$//g;
      $tgt =~ s/^\s+|\s+$//g;
      #print "$phoneme=>$tgt\n";
      my @tgtseq=split(/\s+/,$tgt);
      $phonemap_hash{$phoneme} = [];
      push @{$phonemap_hash{$phoneme}}, @tgtseq;
    }
  }
  while (<STDIN>) {
    chomp;
    @col = split(/ /, $_);
    for ($i = 0; $i < @col; $i++) {
      if (defined($phonemap_hash{$col[$i]})) {
        $col[$i] = $phonemap_hash{$col[$i]};
      }
    }
    print join(" ", @col)."\n";
  }
  ' "$phoneme_mapping" > $lmdir/train.txt

  pron_vocab=$lmdir/vocab
  cat $lmdir/train.txt | sed 's/ /\n/g' | grep -vP 'hes\d' | sort -u > $pron_vocab
  echo ---------------------------------------------------------------------
  echo "Training SRILM language models on" `date`
  echo ---------------------------------------------------------------------
  ngram-count -lm $lmdir/lm.arpa -gt1min 0 -kndiscount2 -gt2min 1 -kndiscount3 -gt3min 2 -order 3 -text $lmdir/train.txt -sort -vocab $pron_vocab
  touch $lmdir/.done
fi

out_domain_lex_pron=$dir/`basename $out_domain_lex`.pron.txt
cut -f 2 $out_domain_lex > $out_domain_lex_pron
cand_filename=`basename $out_domain_lex_pron`

scored_filename=${cand_filename%%.*}.pron.mode1.scored.gz
echo $scored_filename
pushd $dir
if [ ! -f ./$scored_filename ]; then
  XenC -m 1 -s pron --mono -i ./$(basename $lmdir)/train.txt -o $cand_filename --in-slm ./$(basename $lmdir)/lm.arpa --to-lower true --bin-lm 0
fi
popd

gzip -cdf $dir/$scored_filename |\
  perl -e '
    my %p2w;
    open(ALL, "$ARGV[0]") or die;
    while (<ALL>) {
      chomp;
      my @col = split(/\t/, $_);
      if (!defined($p2w{$col[1]})) {
        @{$p2w{$col[1]}} = ();
      }
      push(@{$p2w{$col[1]}}, $col[0]);
    }
    close(ALL);
    while (<STDIN>) {
      chomp;
      my @col = split(/\t/, $_);
      my $score = $col[0];
      my $p = $col[1];
      if (!defined($p2w{$p})) {
        die "something wrong: $p\n";
      }
      foreach my $w (@{$p2w{$p}}) {
        print "$w\t$score\n";
      }
    }
  '  $out_domain_lex | sort -u > $out

