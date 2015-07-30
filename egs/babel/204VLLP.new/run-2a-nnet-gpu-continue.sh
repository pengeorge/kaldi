#!/bin/bash
input_model=exp/dnn_4lang10hr/0/final.mdl
dir=exp/dnn_4lang10hr_cont
train_stage=-10

. conf/common_vars.sh
. ./lang.conf

# This parameter will be used when the training dies at a certain point.
train_stage=-100
. ./utils/parse_options.sh

set -e
set -o pipefail
set -u

# Wait till the main run.sh gets to the stage where's it's 
# finished aligning the tri5 model.
echo "Waiting till exp/tri5_ali/.done exists...."
while [ ! -f exp/tri5_ali/.done ]; do sleep 30; done
echo "...done waiting for exp/tri5_ali/.done"

if [ ! -f $dir/.done ]; then
  steps/nnet2/train_pnorm_fast_continue.sh \
    --stage $train_stage --mix-up $dnn_mixup \
    --initial-learning-rate $dnn_init_learning_rate \
    --final-learning-rate $dnn_final_learning_rate \
    --cmd "$train_cmd" \
    "${dnn_gpu_parallel_opts[@]}" \
    data/train data/lang exp/tri5_ali $input_model $dir || exit 1

  touch $dir/.done
fi

