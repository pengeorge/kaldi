#!/bin/bash

set -e

indomain_text= #data/extra_text/VLLP
outdomain_text= #./data/extra_text/bbnucoluc100w5
indomain_lexicon= #data/extra_lexicon/VLLP
outdomain_lexicon= #./data/extra_lexicon/bbnucoluc100w5

subword_num_iters=6
use_indomain_or_outdomain_for_subword=false

. path.sh
export PATH=$KALDI_ROOT/src/subword:$KALDI_ROOT/tools/srilm/bin/i686-m64:$PATH
. ./utils/parse_options.sh

if [ $# != 3 ]; then
  echo "Usage: $0 <indomain-ext> <outdomain-ext> <new-ext>"
  exit 1;
fi

indomain_ext=$1 #VLLP
outdomain_ext=$2 #bbnucoluc100w5
new_ext=$3

if [ -z $indomain_text ]; then
  indomain_text=data/extra_text/$indomain_ext
fi
if [ -z $indomain_lexicon ]; then
  indomain_lexicon=data/extra_lexicon/$indomain_ext
fi
if [ -z $outdomain_text ]; then
  outdomain_text=data/extra_text/$outdomain_ext
fi
if [ -z $outdomain_lexicon ]; then
  outdomain_lexicon=data/extra_lexicon/$outdomain_ext
fi

if $use_indomain_or_outdomain_for_subword; then
  ext_for_subword=${indomain_ext}
  word_lexicon_for_subword=${indomain_lexicon}
  text_for_subword=$indomain_text
else
  ext_for_subword=${outdomain_ext}
  word_lexicon_for_subword=${outdomain_lexicon}
  text_for_subword=$outdomain_text
fi
subword_dir=exp/subword_${ext_for_subword}
if [ ! -f $subword_dir/.done.$subword_num_iters ]; then
  mkdir -p $subword_dir
  grep -v '^<' $word_lexicon_for_subword | sed 's/ / . /g' > $subword_dir/${ext_for_subword}_lexicon.atom_seperated.txt
  ./czpScripts/subword/generate_w2s_lexicon.sh \
    --dir $subword_dir \
    --num-iters $subword_num_iters \
    $subword_dir/${ext_for_subword}_lexicon.atom_seperated.txt \
    $text_for_subword
fi


if $use_indomain_or_outdomain_for_subword; then
  cut -f 2- $subword_dir/w2s.txt | sed 's/ \|\t/\n/g' |\
    sort -u > $subword_dir/subword_list.txt

  cat $subword_dir/subword_list.txt | sed 's/\./\n/g' | sort -u > $subword_dir/atom_list.txt
  cat $subword_dir/subword_list.txt $subword_dir/atom_list.txt |\
    sort -u > $subword_dir/subword_and_atom_list.txt

  cat $subword_dir/subword_and_atom_list.txt |\
    sed 's/\./ /g' |\
    paste $subword_dir/subword_and_atom_list.txt - \
    > $subword_dir/subword_lexicon.txt
else
  ./czpScripts/prep_lex/lexicon_subtraction.pl \
    $subword_dir/w2s.txt $indomain_lexicon |\
    cut -f 2- | sed 's/ \|\t/\n/g' |\
    sort -u > $subword_dir/subword_list.txt # only those constructing OOV

  cat $subword_dir/subword_list.txt |\
    sed 's/\./ /g' |\
    paste $subword_dir/subword_list.txt - \
    > $subword_dir/subword_lexicon.txt
fi

cat $indomain_lexicon $subword_dir/subword_lexicon.txt |\
  sort -u > $subword_dir/hybrid_lexicon.txt

if $use_indomain_or_outdomain_for_subword; then
  apply_subword_dir=$subword_dir/test_${outdomain_ext}
  mkdir -p $apply_subword_dir
  ./czpScripts/prep_lex/lexicon_subtraction.pl \
    $outdomain_lexicon \
    $indomain_lexicon | sed 's/ / . /g' > $apply_subword_dir/od_lexicon.txt

  generate-w2s-lexicon $apply_subword_dir/od_lexicon.txt ${subword_dir}/lm.${subword_num_iters}.txt $apply_subword_dir/oov_w2s.txt > $apply_subword_dir/score.log

  cat $outdomain_text |\
    ./czpScripts/subword/convert-text-to-hybrid-level.pl $apply_subword_dir/oov_w2s.txt > data/extra_text/$new_ext

  cp $subword_dir/subword_lexicon.txt data/extra_lexicon/$new_ext

  cut -f 1 $indomain_lexicon | paste - <(cut -f 1 $indomain_lexicon) | cat - $apply_subword_dir/oov_w2s.txt | sort -u > data/extra_w2s/$new_ext
else
  ./czpScripts/prep_lex/lexicon_subtraction.pl \
    $subword_dir/w2s.txt \
    $indomain_lexicon > $subword_dir/oov_w2s.txt
  cat $outdomain_text |\
    ./czpScripts/subword/convert-text-to-hybrid-level.pl $subword_dir/oov_w2s.txt > data/extra_text/$new_ext

  cp $subword_dir/subword_lexicon.txt data/extra_lexicon/$new_ext

  cut -f 1 $indomain_lexicon | paste - <(cut -f 1 $indomain_lexicon) | cat - $subword_dir/oov_w2s.txt | sort -u > data/extra_w2s/$new_ext
fi


