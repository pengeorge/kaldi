#!/bin/bash

set -e

indomain_text= #data/extra_text/VLLP
outdomain_text= #./data/extra_text/bbnucoluc100w5
indomain_lexicon= #data/extra_lexicon/VLLP
outdomain_lexicon= #./data/extra_lexicon/bbnucoluc100w5

subword_num_iters=6

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

id_subword_dir=exp/subword_${indomain_ext}
if [ ! -f $id_subword_dir/.done.$subword_num_iters ]; then
  mkdir -p $id_subword_dir
  grep -v '^<' $indomain_lexicon | sed 's/ / . /g' > $id_subword_dir/${indomain_ext}_lexicon.atom_seperated.txt
  ./czpScripts/subword/generate_w2s_lexicon.sh \
    --dir $id_subword_dir \
    --num-iters $subword_num_iters \
    $id_subword_dir/${indomain_ext}_lexicon.atom_seperated.txt \
    $indomain_text
fi


cut -f 2- $id_subword_dir/w2s.txt | sed 's/ \|\t/\n/g' |\
  sort -u > $id_subword_dir/subword_list.txt

cat $id_subword_dir/subword_list.txt | sed 's/\./\n/g' | sort -u > $id_subword_dir/atom_list.txt
cat $id_subword_dir/subword_list.txt $id_subword_dir/atom_list.txt |\
  sort -u > $id_subword_dir/subword_and_atom_list.txt

cat $id_subword_dir/subword_and_atom_list.txt |\
  sed 's/\./ /g' |\
  paste $id_subword_dir/subword_and_atom_list.txt - \
  > $id_subword_dir/subword_lexicon.txt

cat $indomain_lexicon $id_subword_dir/subword_lexicon.txt |\
  sort -u > $id_subword_dir/hybrid_lexicon.txt

od_subword_dir=exp/subword_${indomain_ext}/test_${outdomain_ext}
mkdir -p $od_subword_dir
./czpScripts/prep_lex/lexicon_subtraction.pl \
  $outdomain_lexicon \
  $indomain_lexicon | sed 's/ / . /g' > $od_subword_dir/od_lexicon.txt

generate-w2s-lexicon $od_subword_dir/od_lexicon.txt exp/subword_${indomain_ext}/lm.${subword_num_iters}.txt $od_subword_dir/w2s.txt > $od_subword_dir/score.log

cat $outdomain_text |\
  ./czpScripts/subword/convert-text-to-hybrid-level.pl $od_subword_dir/w2s.txt > data/extra_text/$new_ext

cp $id_subword_dir/subword_lexicon.txt data/extra_lexicon/$new_ext

cut -f 1 $indomain_lexicon | paste - <(cut -f 1 $indomain_lexicon) | cat - $od_subword_dir/w2s.txt $id_subword_dir/w2s.${subword_num_iters}.txt | sort -u > data/extra_w2s/$new_ext

