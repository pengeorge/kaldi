#!/bin/bash
set -u;
set -e;
set -o pipefail;

. conf/common_vars_leave1q.sh || exit 1;

decode_dir=exp/tri6_nnet_mpe/decode_evalpart1.seg_epoch4
lang_dir=data/lang
data_dir=data/evalpart1.seg
for nbest in 0 2200 4000 5000 7000 2500 2000 10 20 30 40 50 60 70 80 90 100 120 140 160 180 200 240 280 320 400 500 600 700 800 900 1000 1200 1600 1800; do
ive_type=ive-4-tri6_nnet-$nbest-3-0.5
kwsres=$decode_dir/kws_${ive_type}_11
if [ ! -f $kwsres/.done.search ]; then
  set +e;
#  mv $decode_dir/.*${ive_type} $decode_dir/bak/
  mv $decode_dir/*${ive_type} $decode_dir/bak/
  mv $decode_dir/*${ive_type}_* $decode_dir/bak/
  set -e;
  czpScripts/kws/kws_search.chenzp.sh --cmd "$decode_cmd" --suffix ${ive_type} --max-states 150000 \
      --min-lmwt 11 --max-lmwt 11 --skip-scoring false \
      --indices-dir $decode_dir/kws_indices $lang_dir $data_dir $decode_dir 
else
  echo "skip ${ive_type}"
fi
done
