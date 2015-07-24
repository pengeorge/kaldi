#!/bin/bash

suffix=.raw
dir=exp/rnn_bound_det${suffix}
set -e

mkdir -p $dir
currennt --train true --network conf/rnn_bound_det${suffix}.jsn --cuda true \
    --parallel_sequences 64 --shuffle_fractions true --hybrid_online_batch true \
    --save_network $dir/saved_network.jsn --autosave true --autosave_prefix $dir/ \
    --max_epochs 60 --max_epochs_no_best 10 \
    --validate_every 1 --test_every 5 \
    --train_file exp/tri6_nnet_ali/bound_det_train$suffix/bound_det_train${suffix}.nc \
    --val_file exp/tri6_nnet_ali/bound_det_valid$suffix/bound_det_valid${suffix}.nc \
    --test_file ../204LLP/exp/tri6_nnet_ali/bound_det_test4VLLP$suffix/bound_det_test4VLLP${suffix}.nc \
    --learning_rate 0.0000005 --momentum 0.9

