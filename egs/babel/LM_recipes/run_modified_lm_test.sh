#!/bin/bash
set -e

# chenzp 2015
# Test the probability-reassigned LM and estimate N_true

ext=bbnucoluc100w5+.knModOOCbyLR10
kwlist_id=bbnucoluc100w5-exc-VLLP
lm_only=true

. ./utils/parse_options.sh

ln -sf ${ext%%+*} data/extra_lexicon/${ext}

./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext} --do-ext-lexicon true --merge-lexicon true --sys-to-decode "" --sys-to-kws-stt " sat " --skip-kws false --oov-kws false --vocab-kws false --extra-kws false --tmp-kwlist data/extra_kwlist/${kwlist_id}.xml --tmp-kws-key ${kwlist_id} --lm-only $lm_only

if ! $lm_only; then
  kwsoutdir=./exp/tri5/decode_dev10h.pem_${ext}/${kwlist_id}_kws_15
  ./czpScripts/kws/est_Ntrue.pl data/dev10h.pem_${ext}/${kwlist_id}_kws/keywords.txt \
    $kwsoutdir/kwslist.unnormalized.xml \
    $kwsoutdir/Ntrue.txt
fi

