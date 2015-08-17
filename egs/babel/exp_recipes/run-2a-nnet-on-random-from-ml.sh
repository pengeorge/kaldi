#!/bin/bash

. conf/common_vars.sh

ali_dir=exp/tri6_nnet_ali
ali_model=exp/tri6b_nnet/
ali_model_transform_dir=exp/tri5_ali

semisupervised=false
bnf_weight_threshold=0.7
weights_dir=exp_bnf_semisup/best_path_weights/unsup.seg/decode_unsup.seg/

. ./utils/parse_options.sh

set -e;

if [ $# != 2 ]; then
  echo "Usage: $0 <ml-exp-dir> <rand-fake-mldir>"
  exit 1;
fi

mldir=$1
randdir=$2

if [ ! -f $randdir/.done ]; then
  mkdir -p $randdir/0

  # Creating fake ML dir
  cp $mldir/0/0.mdl $randdir/0/final.mdl
  cp $mldir/feat_type $randdir/
  cp $mldir/splice_width $randdir/
fi

target_num_hidden=$[`nnet-am-info $mldir/0/final.mdl 2>/dev/null |grep -Po '(?<=num-updatable-components )\d+$'` - 1]

./run-2a-nnet-finetune-on-ml.sh \
  --mldir $randdir \
  --num-additional-hidden-layers $[target_num_hidden-1] \
  --hidden-config "$mldir/hidden.config" \
  --ali-dir "$ali_dir" \
  --ali-model "$ali_model" \
  --ali-model-transform-dir "$ali_model_transform_dir" \
  --semisupervised $semisupervised \
  --bnf-weight-threshold $bnf_weight_threshold \
  --weights-dir "$weights_dir"
  

