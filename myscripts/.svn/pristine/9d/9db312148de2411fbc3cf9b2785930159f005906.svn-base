#!/bin/bash

set -e;

dir=exp/gen_subword
num_iters=6
cutoff_cnt=3

. path.sh
export PATH=$KALDI_ROOT/src/subword:$KALDI_ROOT/tools/srilm/bin/i686-m64:$PATH
. lang.conf
. parse_options.sh || exit 1;

if [ $# -ne 2 ]; then
  echo "Usage: $0 <input-lexicon> <text-corpus>";
  exit 1;
fi

inlex=$1
text=$2

mkdir -p $dir

  ./czpScripts/subword/init-lm.pl --cutoff=$cutoff_cnt $inlex $dir/lm.0.txt
  cp $text $dir/text.word.txt
x=0
while [ $x -lt $num_iters ]; do
  if [ -f $dir/.done.$[$x+1] ]; then
    x=$[x+1]
    continue
  fi
  # generate w2s.${x}.txt
  # TODO parallel
  echo "iter $x: generating w2s"
  generate-w2s-lexicon $inlex $dir/lm.${x}.txt $dir/w2s.${x}.txt > $dir/score.${x}.log
  # generate corpus by w2s.${x}.txt: text.$[$x+1].txt
  echo "iter $x: generating corpus"
  cat $dir/text.word.txt |\
    ./czpScripts/subword/convert-text-to-sub-level.pl $dir/w2s.${x}.txt > $dir/text.$[$x+1].txt
  ngram -order 3 -lm $dir/lm.${x}.txt -unk -ppl $dir/text.$[$x+1].txt 
  x=$[$x+1]
  cat $dir/text.${x}.txt | sed 's/ /\n/g' | sort -u | grep -v '<' > $dir/vocab.${x}.sub.txt
  cat $dir/vocab.${x}.sub.txt | sed 's/\./\n/g' | sort -u > $dir/vocab.${x}.atom.txt
  cat $dir/vocab.${x}.sub.txt $dir/vocab.${x}.atom.txt  | sort -u > $dir/vocab.${x}.txt
  # train LM with new corpus: lm.$[$x+1].txt
  echo "iter $x: training LM"
  ngram-count -lm $dir/lm.${x}.txt -kndiscount1 -gt1min 0 -kndiscount2 -gt2min 1 -kndiscount3 -gt3min 2 -order 3 -text $dir/text.${x}.txt -vocab $dir/vocab.${x}.txt -unk -sort
  touch $dir/.done.${x}
done

echo "Final iter $x: generating w2s"
generate-w2s-lexicon $inlex $dir/lm.${x}.txt $dir/w2s.${x}.txt > $dir/score.${x}.log

ln -s w2s.${x}.txt $dir/w2s.txt
