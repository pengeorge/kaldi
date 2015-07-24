#!/bin/bash

. conf/common_vars.sh
. ./lang.conf

train_stage=-10
dir=exp/tri6b_nnet

. ./utils/parse_options.sh

set -e
set -o pipefail
set -u

temp_dir=`pwd`/nnet_gpu_egs
egs_dir=

# Wait till the main run.sh gets to the stage where's it's 
# finished aligning the tri5 model.
echo "Waiting till exp/tri5_ali/.done exists...."
while [ ! -f exp/tri5_ali/.done ]; do sleep 30; done
echo "...done waiting for exp/tri5_ali/.done"

if [ ! -f $dir/.done ]; then
  steps/nnet2/train_pnorm_ensemble.sh \
    --stage $train_stage --mix-up $dnn_mixup --egs-dir "$egs_dir" \
    --initial-learning-rate $ensemble_dnn_init_learning_rate \
    --final-learning-rate $ensemble_dnn_final_learning_rate \
    --num-hidden-layers $ensemble_dnn_num_hidden_layers \
    --pnorm-input-dim $ensemble_dnn_pnorm_input_dim \
    --pnorm-output-dim $ensemble_dnn_pnorm_output_dim \
    --cmd "$train_cmd" \
    "${dnn_gpu_parallel_opts[@]}" \
    --ensemble-size $ensemble_size --initial-beta $ensemble_initial_beta --final-beta $ensemble_final_beta \
    data/train data/lang exp/tri5_ali $dir || exit 1
  touch $dir/.done
fi

