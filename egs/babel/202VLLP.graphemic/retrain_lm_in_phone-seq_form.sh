#!/bin/bash

set -e;

. lang.conf
. local.conf
. ./utils/parse_options.sh

if [ $# != 1 ]; then
  echo "Usage: <src-srilm-dir>"
  exit 1;
fi
src_srilm_dir=$1

org_lm_filename=`basename $(readlink -f $src_srilm_dir/lm.gz)`
org_lm_dir=`dirname $(readlink -f $src_srilm_dir/lm.gz)`
org_lm_train_text=$org_lm_dir/train.txt
order=`echo $org_lm_filename | grep -Po '^(\d+)(?=gram)'`
smooth=`echo $org_lm_filename | grep -Po '(?<=gram\.)[^\d]+(?=\d)'`
mins=`echo $org_lm_filename | grep -Po '\d+(?=\.gz$)'`
mins=`echo $mins | perl -e '$mins=<STDIN>; @col=split(//,$mins); print join(" ", @col);'`
ext=${org_lm_dir##*_}
ext=${ext%%.*}
ext=${ext%%+*}
echo $ext

n=0
options="-order $order"
for min in $mins; do
  n=$[n+1]
  options="$options -gt${n}min $min"
  if [ $smooth == kn ]; then
    options="$options -kndiscount${n}"
  fi
done

des_dir=$src_srilm_dir-phoneseq
mkdir -p $des_dir
cp $src_srilm_dir/vocab $des_dir/
mkdir -p data/extra_w2s
# TODO phoneme_mapping
cut -f 2 data/extra_lexicon/$ext | sed 's/^ \+//' | sed 's/ \+$//' |\
  sed 's/ \+/-/g' | paste <(cut -f 1 data/extra_lexicon/$ext) - \
  > data/extra_w2s/${ext}2phoneSeq.txt
./czpScripts/subword/convert-text-to-sub-level.pl data/extra_w2s/${ext}2phoneSeq.txt \
  < $org_lm_train_text > $des_dir/train.txt
cut -f 2 data/extra_lexicon/${ext} | paste <(cut -f 2 data/extra_w2s/${ext}2phoneSeq.txt) - > data/extra_lexicon/${ext}phoneSeq
./czpScripts/subword/convert-text-to-sub-level.pl data/extra_w2s/${ext}2phoneSeq.txt \
  < $src_srilm_dir/vocab | sort -u > $des_dir/vocab

/home/kaldi/code/kaldi-trunk/tools/srilm/lm/bin/i686-m64/ngram-count \
  -lm $des_dir/$org_lm_filename $options -text $des_dir/train.txt -vocab $des_dir/vocab -unk -sort

ln -s $org_lm_filename $des_dir/lm.gz
