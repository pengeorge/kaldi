#!/bin/bash

. cmd.sh
set -e

cmd=$decode_cmd
skip_stt_score=true

cer=0
min_lmwt=8
max_lmwt=12
max_states=150000

. utils/parse_options.sh

data=$1
lang=data/lang
decode=$2

if ! $skip_stt_score ; then
  czpScripts/local/score_stm.chenzp.sh --cmd "$cmd" --cer $cer \
    --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} $data $lang $decode
fi

czpScripts/kws/kws_search.chenzp.sh --cmd "$cmd" --stage 4  \
  --max-states ${max_states} --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} \
  --indices-dir $decode/kws_indices     $lang $data $decode 
# scoring extra kws tasks
for extraid in `cat $data/extra_kws_tasks`; do
  czpScripts/kws/kws_search.chenzp.sh --cmd "$cmd" --stage 0 --extraid $extraid \
    --max-states ${max_states} --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} \
    --indices-dir $decode/kws_indices     $lang $data $decode 
done
