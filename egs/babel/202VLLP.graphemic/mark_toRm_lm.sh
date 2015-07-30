#!/bin/bash

fix_set=

. ./utils/parse_options.sh

if false; then
for d in `find ./data/ -name 'srilm_*'`; do
  if [ -f $d/train.txt ]; then
    ext=`echo $d | sed 's/^.*_\([^_]*\)$/\1/'`
    if [ -f data/extra_text/$ext ]; then
      if [ -f data/srilm_$ext/train.txt ]; then
        diffLen=`diff data/extra_text/$ext data/srilm_$ext/train.txt | wc -l`
      else
        if [ TMP_COL != `head -n 1 $(dirname $(readlink -f data/srilm_$ext/lm.gz))/raw_train_text | cut -f 1` ]; then
          diffLen=1
        fi
      fi
      if [ $diffLen -ne 0 ] || [[ "$force_fix_set" =~ " $ext " ]]; then # so we need fixing
        fix_set="$fix_set $ext"
      fi
    fi
  fi
done
fi

for ext in $fix_set; do
  echo "Fixing $ext......................."
  # Backup
  for t in srilm lang local; do
    if [ -d data/${t}_${ext} ]; then
      mv data/${t}_${ext} data/toRm.${t}_${ext}
    fi
  done
  for t in mkgraph_${ext}.log decode_dev10h.pem_${ext}.si decode_dev10h.pem_${ext} graph_${ext}; do
    mv exp/tri5/$t exp/tri5/toRm.$t
  done
  for t in exp/dnn_*/decode_dev10h.pem_${ext}*; do
    mv $t $(dirname $t)/toRm.$(basename $t)
  done
done 




exit 0;





# ext_lexicon (merge lexicon with VLLP)
normal_set=
ol_set=
mix_lex_set=" FLP-colv8 FLP-bbnC FLP-bbnC-colv8 "
#"bbnut02 bbnut02c50 bbnut05c100s02e05 colut05c100s02e05 colut02 colut02c50 "
for ext in $normal_set; do
  if [ ! -f exp/tri5/decode_dev10h.pem_${ext}/.done.score ]; then
    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext} --do-ext-lexicon true --merge-lexicon true --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true
  fi
done

# original_lexicon
for ext in $ol_set; do
  if [ ! -f exp/tri5/decode_dev10h.pem_${ext}OL/.done.score ]; then
    ln -sf ${ext} data/extra_lexicon/${ext}OL
    ln -sf ${ext} data/extra_text/${ext}OL
    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext}OL --do-ext-lexicon false --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true
  fi
done

# mix_lexicon_only (merge other extra_lexicon, text is the same with ext1)

for ext in $ext_lex_set; do
  if [ ! -f exp/tri5/decode_dev10h.pem_${ext}/.done.score ]; then
    ext1=`echo $ext | sed 's/^\(.*\)\-\([^\-]*\)$/\1/'`
    ext2=`echo $ext | sed 's/^\(.*\)\-\([^\-]*\)$/\2/'`
    cat data/extra_lexicon/$ext1 data/extra_lexicon/$ext2 | sort -u > data/extra_lexicon/
    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext} --do-ext-lexicon true --merge-lexicon true --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true
  fi
done

