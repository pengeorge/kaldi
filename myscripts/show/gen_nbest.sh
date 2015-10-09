#!/bin/bash
dir=./exp/tri6_nnet_mpe/decode_music3.man_ext_music-ext_music_LM_corpus-0.05_epoch1
LMWT=10
decode_mbr=true
word_ins_penalty=0.5
beam=5

. path.sh
if [ -z "$model" ] ; then
  model=`dirname $dir`/final.mdl # Relative path does not work in some cases
fi
lang=./data/lang_ext_music

lattice-scale --inv-acoustic-scale=$LMWT "ark:gunzip -c $dir/lat.*.gz|" ark:- | \
lattice-add-penalty --word-ins-penalty=$word_ins_penalty ark:- ark:- | \
lattice-prune --beam=$beam ark:- ark:- | \
lattice-align-words $lang/phones/word_boundary.int $model ark:- ark:- | \
lattice-to-nbest --n=50 ark:- ark,t:- |\
utils/int2sym.pl -f 3 $lang/words.txt  >  $dir/score_$LMWT/nbest50
