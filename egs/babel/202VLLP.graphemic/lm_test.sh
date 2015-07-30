#!/bin/bash -v
set -e

ext_set="bbnut02 bbnut02c50 bbnut05c100s02e05 colut05c100s02e05 colut02 colut02c50 "
for ext in $ext_set; do
  if [ ! -f exp/tri5/decode_dev10h.pem_${ext}OL/.done.score ]; then
    ln -sf ${ext} data/extra_lexicon/${ext}OL
    ln -sf ${ext} data/extra_text/${ext}OL
    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext}OL --do-ext-lexicon false --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true
  fi

  if [ ! -f exp/tri5/decode_dev10h.pem_${ext}MixVLLP/.done.score ]; then
    ln -sf ${ext} data/extra_lexicon/${ext}MixVLLP
    ln -sf ${ext} data/extra_text/${ext}MixVLLP
    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext}MixVLLP --do-ext-lexicon true --merge-lexicon true --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true
  fi
done
