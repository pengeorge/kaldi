#!/bin/bash

# Copyright 2015  Brno University of Technology (Author: Karel Vesely)
# Apache 2.0

# This example script trains a LSTM network on FBANK features.
# The LSTM code comes from Yiayu DU, and Wei Li, thanks!

. ./cmd.sh
. ./path.sh

train=data-fbank/train

train_original=data/train

feat_type=fbank  # fbank/bnf

gmm=exp/tri5

suffix=

stage=0
[ ! -f ./conf/common_vars.sh ] && echo 'the file conf/common_vars.sh does not exist!' && exit 1
[ ! -f ./lang.conf ] && echo 'Language configuration does not exist! Use the configurations in conf/lang/* as a startup' && exit 1

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;
[ -f local.conf ] && . ./local.conf

. utils/parse_options.sh || exit 1;

set -u
set -e
set -o pipefail  #Exit if any of the commands in the pipeline will 

# Make the FBANK features
if [ $stage -le 0 ]; then
  if [ $feat_type == "fbank" ]; then
    donefile=$train/.fbank.done
    if [ ! -f $donefile ]; then
      # Training set
      utils/copy_data_dir.sh $train_original $train || exit 1; rm $train/{cmvn,feats}.scp
      steps/make_fbank_pitch.sh --nj $train_nj --cmd "$train_cmd" \
         $train $train/log $train/data || exit 1;
      steps/compute_cmvn_stats.sh $train $train/log $train/data || exit 1;
      touch $donefile
    fi
  else
    donefile=$train/.done
    if [ ! -f $donefile ]; then
      echo "You specify feat_type as bnf, but bnf data is not ready."
      exit 1;
    fi
  fi
  if [ ! -f $train/.subset_tr_cv.done ] || [ $train/.subset_tr_cv.done -ot $donefile ]; then
    # Split the training set
    utils/subset_data_dir_tr_cv.sh --cv-spk-percent 10 $train ${train}_tr90 ${train}_cv10
    touch $train/.subset_tr_cv.done
  fi
fi

if [ $stage -le 1 ]; then
  # Train the DNN optimizing per-frame cross-entropy.
  dir=`dirname $gmm`/lstm4f${suffix}
  ali=${gmm}_ali

  if [ ! -f $dir/.done ]; then
    # Train
    echo =====================================
    echo "Training LSTM"
    echo =====================================
    $cuda_cmd $dir/log/train_nnet.log \
      steps/nnet/train.sh --network-type lstm --learn-rate 0.0001 \
        --cmvn-opts "--norm-means=true --norm-vars=true" --feat-type plain --splice $lstm_splice \
        --train-opts "--momentum 0.9 --halving-factor 0.5" \
        --train-tool "nnet-train-lstm-streams --num-stream=4 --targets-delay=5" \
        --proto-opts "$lstm_proto_opts" \
        ${train}_tr90 ${train}_cv10 data/lang $ali $ali $dir || exit 1;
    echo $train > $dir/train_dir
    touch $dir/.done
  fi
fi

# TODO : sequence training,

echo Success
exit 0

# Getting results [see RESULTS file]
# for x in exp/*/decode*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; done
