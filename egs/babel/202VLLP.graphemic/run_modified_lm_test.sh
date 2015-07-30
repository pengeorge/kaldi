#!/bin/bash
set -e

ext=bbnucoluc100w5+.knModOOCbyPPL2
kwlist_id=bbnucoluc100w5-exc-VLLP

. ./utils/parse_options.sh

ln -sf ${ext%%+*} data/extra_lexicon/${ext}

./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext} --do-ext-lexicon true --merge-lexicon true --sys-to-decode "" --sys-to-kws-stt " sat " --skip-kws false --oov-kws false --vocab-kws false --extra-kws false --tmp-kwlist data/extra_kwlist/${kwlist_id}.xml --tmp-kws-key ${kwlist_id}

kwsoutdir=./exp/tri5/decode_dev10h.pem_${ext}/${kwlist_id}_kws_15
./czpScripts/kws/est_Ntrue.pl data/dev10h.pem_${ext}/${kwlist_id}_kws/keywords.txt \
  $kwsoutdir/kwslist.unnormalized.xml \
  $kwsoutdir/Ntrue.txt

