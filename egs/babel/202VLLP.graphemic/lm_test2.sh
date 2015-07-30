#!/bin/bash -v
set -e

ext_set="bbnut04c100s02e04 colut04c100s02e04"
for ext in $ext_set; do
  if [ ! -f exp/tri5/decode_dev10h.pem_${ext}OL/.done.score ]; then
    ln -sf ${ext} data/extra_lexicon/${ext}OL
    ln -sf ${ext} data/extra_text/${ext}OL
    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext}OL --do-ext-lexicon false --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true
  fi

  if [ ! -f exp/tri5/decode_dev10h.pem_${ext}only/.done.score ]; then
    ln -sf ${ext} data/extra_lexicon/${ext}only
    ln -sf ${ext} data/extra_text/${ext}only
    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext}only --do-ext-lexicon true --merge-lexicon false --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true
  fi

  if [ ! -f exp/tri5/decode_dev10h.pem_${ext}/.done.score ]; then
    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext} --do-ext-lexicon true --merge-lexicon true --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true
  fi
done
