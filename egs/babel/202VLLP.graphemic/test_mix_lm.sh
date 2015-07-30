#!/bin/bash

set -e

lm_only=true
ext=bbnucoluc100w5+.kn
ext_for_mix=bbnucoluc100w5+bbnucoluc100w5-VLLP.kn
skip_kws=true

. ./utils/parse_options.sh

for lambda in 7; do
  ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext} \
    --ext-for-mix ${ext_for_mix} --org-lm-lambda 0.${lambda} --lm-only true

  if ! $lm_only; then
    mix_ext=${ext}-${ext_for_mix}-0.${lambda}
    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${mix_ext} \
      --sys-to-decode "" --sys-to-kws-stt "" --skip-kws $skip_kws
  fi
done
