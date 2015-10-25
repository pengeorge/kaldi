#!/bin/bash
LMWT=10
word_ins_penalty=0.5
beam=5
n=50
lang=./data/lang

. ./utils/parse_options.sh

. path.sh

if [ $# != 1 ]; then
  echo "Usage: $0 <decode-dir>"
  exit 1;
fi

dir=$1

if [ -z "$model" ] ; then
  model=`dirname $dir`/final.mdl # Relative path does not work in some cases
  if [ ! -f $model ]; then
    echo "Model not found: $model"
    exit 1;
  fi
fi

score_dir=$dir/score_${LMWT}_${word_ins_penalty}
if [ ! -d $score_dir ] && [ -d $dir/score_${LMWT} ] && [ $word_ins_penalty == 0.5 ]; then
    score_dir=$dir/score_${LMWT}
fi
mkdir -p $score_dir

lattice-scale --inv-acoustic-scale=$LMWT "ark:gunzip -c $dir/lat.*.gz|" ark:- | \
lattice-add-penalty --word-ins-penalty=$word_ins_penalty ark:- ark:- | \
lattice-prune --beam=$beam ark:- ark:- | \
lattice-align-words $lang/phones/word_boundary.int $model ark:- ark:- | \
lattice-to-nbest --n=${n} ark:- ark,t:- |\
utils/int2sym.pl -f 3 $lang/words.txt  >  $score_dir/nbest${n}.beam${beam}

