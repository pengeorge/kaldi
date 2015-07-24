#!/bin/bash
# Support using other LM for denlats generation (chenzp)

input_model=exp/dnn_scratch_6langFLPNN.raw_cont  #exp/tri6_nnet
transform_dir=   #exp/tri5_ali
feat_type=raw
ext=
sub_split=48
train_stage=-100
. conf/common_vars.sh
. ./lang.conf

. ./utils/parse_options.sh

set -e
set -o pipefail
set -u

if [ ! -z "$ext" ]; then
  ext=_$ext
fi

# Wait for cross-entropy training.
echo "Waiting till $input_model/.done exists...."
while [ ! -f $input_model/.done ]; do sleep 30; done
echo "...done waiting for $input_model/.done"

# Generate denominator lattices.
if [ ! -f ${input_model}_denlats$ext/.done ]; then
  steps/nnet2/make_denlats.chenzp.sh "${dnn_denlats_extra_opts[@]}" \
    --nj $train_nj --sub-split $sub_split \
    --feat-type "$feat_type" \
    --transform-dir "$transform_dir" \
    data/train data/lang$ext $input_model ${input_model}_denlats$ext || exit 1
 
  touch ${input_model}_denlats$ext/.done
fi

# Generate alignment.
if [ ! -f ${input_model}_ali/.done ]; then
  steps/nnet2/align.sh --use-gpu yes \
    --cmd "$decode_cmd $dnn_parallel_opts" \
    --transform-dir "$transform_dir" --nj $train_nj \
    data/train data/lang$ext ${input_model} ${input_model}_ali || exit 1

  touch ${input_model}_ali/.done
fi

if [ ! -f ${input_model}_mpe$ext/.done ]; then
  steps/nnet2/train_discriminative.sh \
    --stage $train_stage --cmd "$decode_cmd" \
    --learning-rate $dnn_mpe_learning_rate \
    --modify-learning-rates true \
    --last-layer-factor $dnn_mpe_last_layer_factor \
    --num-epochs 4 --cleanup true \
    --retroactive $dnn_mpe_retroactive \
    --transform-dir "$transform_dir" \
    "${dnn_gpu_mpe_parallel_opts[@]}" data/train data/lang$ext \
    ${input_model}_ali ${input_model}_denlats$ext ${input_model}/final.mdl ${input_model}_mpe$ext || exit 1

  touch ${input_model}_mpe$ext/.done
fi
