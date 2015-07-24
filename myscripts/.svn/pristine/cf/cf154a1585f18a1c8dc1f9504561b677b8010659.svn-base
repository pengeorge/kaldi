#!/bin/bash

suffix=.raw
dir=exp/rnn_bound_det${suffix}
set -e

mkdir -p $dir
currennt --train false --network $dir/saved_network.jsn --cuda true \
    --ff_input_file ../204LLP/exp/tri6_nnet_ali/bound_det_test4VLLP${suffix}/bound_det_test4VLLP${suffix}.nc \
    --ff_output_file $dir/test_output.csv

