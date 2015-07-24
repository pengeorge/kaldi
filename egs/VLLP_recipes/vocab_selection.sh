#!/bin/bash

set -e

num=200000

. path.sh
export PATH=$KALDI_ROOT/tools/srilm/bin/i686-m64:$PATH
. lang.conf
. local.conf
. ./utils/parse_options.sh

if [ $# -ne 1 ]; then
  echo "Usage: $0 org-vocab"
  exit 1;
fi

org_vocab=$1
dir=exp/vocab_select
lmdir=$dir/pron_lm

mkdir -p $lmdir

cut -f 2 $lexicon_file | perl -e '
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

if [[ ! -f $lmdir/lm.arpa || $lmdir/lm.arpa -ot $lmdir/train.txt ]]; then
  pron_vocab=$lmdir/vocab
  cat $lmdir/train.txt | sed 's/ /\n/g' | sort -u > $pron_vocab
  echo ---------------------------------------------------------------------
  echo "Training SRILM language models on" `date`
  echo ---------------------------------------------------------------------
  ngram-count -lm $lmdir/lm.arpa -gt1min 0 -kndiscount2 -gt2min 1 -kndiscount3 -gt3min 2 -order 3 -text $lmdir/train.txt -sort -vocab $pron_vocab
fi

org_vocab_pron=$dir/`basename $org_vocab`.pron.txt
cut -f 2 $org_vocab > $org_vocab_pron
cand_filename=`basename $org_vocab_pron`

sorted_filename=${cand_filename%%.*}.pron.mode1.sorted.gz
echo $sorted_filename
pushd $dir
if [ ! -f ./$sorted_filename ]; then
  XenC -m 1 -s pron --mono -i ./pron_lm/train.txt -o $cand_filename --in-slm ./pron_lm/lm.arpa --to-lower true --bin-lm 0
fi
popd

gzip -cdf $dir/$sorted_filename |\
  head -n $num | cut -f 2 | sort -u |\
  perl -e '
    my %p2w;
    open(ALL, "$ARGV[0]") or die;
    while (<ALL>) {
      chomp;
      my @col = split(/\t/, $_);
      if (!defined($p2w{$col[1]})) {
        @{$p2w{$col[1]}} = ();
      }
      push(@{$p2w{$col[1]}}, $_);
    }
    close(ALL);
    while (<STDIN>) {
      chomp;
      my $p = $_;
      if (!defined($p2w{$p})) {
        die "something wrong: $p\n";
      }
      foreach my $w (@{$p2w{$p}}) {
        print "$w\n";
      }
    }
  ' $org_vocab | sort -u > ${org_vocab}lm$num

