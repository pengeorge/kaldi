#!/bin/bash
exp_dir=exp_concat_4lang10hr.raw_3hid/tri7_nnet
splice_width=0
feat_type=raw
do_lda=true  # LDA in NN
train_stage=-10

. conf/common_vars.sh
. ./lang.conf

# This parameter will be used when the training dies at a certain point.
train_stage=-100
. ./utils/parse_options.sh

set -e
set -o pipefail
set -u

data_dir=`dirname $exp_dir | sed 's/exp/data/'`
param_dir=`dirname $exp_dir | sed 's/exp/param/'`

# Wait till the main run.sh gets to the stage where's it's 
# finished aligning the tri5 model.
echo "Waiting till exp/tri5_ali/.done exists...."
while [ ! -f exp/tri5_ali/.done ]; do sleep 30; done
echo "...done waiting for exp/tri5_ali/.done"

if $do_lda; then
  train_script=czpScripts/nnet2/train_pnorm_fast_ext.sh
else
  train_script=czpScripts/nnet2/train_pnorm_fast.no_2nd_lda.sh
  exp_dir=${exp_dir}.no_lda
fi

if [ ! -f $exp_dir/.done ]; then
  $train_script \
    --feat-type $feat_type --splice-width $splice_width \
    --stage $train_stage --mix-up $dnn_mixup \
    --initial-learning-rate $dnn_init_learning_rate \
    --final-learning-rate $dnn_final_learning_rate \
    --num-hidden-layers $dnn_num_hidden_layers \
    --pnorm-input-dim $dnn_input_dim \
    --pnorm-output-dim $dnn_output_dim \
    --cmd "$train_cmd" \
    "${dnn_gpu_parallel_opts[@]}" \
    $data_dir/train data/lang exp/tri5_ali $exp_dir || exit 1

  touch $exp_dir/.done
fi

