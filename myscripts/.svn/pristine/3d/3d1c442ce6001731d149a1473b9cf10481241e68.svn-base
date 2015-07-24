#!/bin/bash

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

. ./path.sh ## Source the tools/utils (import the queue.pl)


#dev=data-fbank/dev10h.pem
train=data-fbank/train

#dev_original=data/dev10h.pem
train_original=data/train

gmm=exp/tri5
ali=

stage=0
[ ! -f ./conf/common_vars.sh ] && echo 'the file conf/common_vars.sh does not exist!' && exit 1
[ ! -f ./lang.conf ] && echo 'Language configuration does not exist! Use the configurations in conf/lang/* as a startup' && exit 1

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;
[ -f local.conf ] && . ./local.conf

. utils/parse_options.sh

set -u
set -e
set -o pipefail  #Exit if any of the commands in the pipeline will 


# Make the FBANK features
if [ $stage -le 0 ]; then
  if false && [ ! -f $dev/.fbank.done ]; then
    # Dev set
    mkdir -p $dev && cp $dev_original/* $dev && rm $dev/{feats,cmvn}.scp
    steps/make_fbank_pitch.sh --nj $dev10h_nj --cmd "$train_cmd" \
       $dev $dev/log $dev/data || exit 1;
    steps/compute_cmvn_stats.sh $dev $dev/log $dev/data || exit 1;
    touch $dev/.fbank.done
  fi
  if [ ! -f $train/.fbank.done ]; then
    # Training set
    mkdir -p $train && cp $train_original/* $train && rm $train/{feats,cmvn}.scp
    steps/make_fbank_pitch.sh --nj $train_nj --cmd "$train_cmd" \
       $train $train/log $train/data || exit 1;
    steps/compute_cmvn_stats.sh $train $train/log $train/data || exit 1;
    touch $train/.fbank.done
  fi
  if [ ! -f $train/.subset_tr_cv.done ] || [ $train/.subset_tr_cv.done -ot $train/.fbank.done ]; then
    # Split the training set
    utils/subset_data_dir_tr_cv.sh --cv-spk-percent 10 $train ${train}_tr90 ${train}_cv10
    touch $train/.subset_tr_cv.done
  fi
fi

# Run the CNN pre-training.
if [ $stage -le 1 ]; then
  dir=exp/cnn4c
  if [ -z "$ali" ]; then
    ali=${gmm}_ali
  fi
  if [ ! -f $dir/.done ]; then
    # Train
    $cuda_cmd $dir/log/train_nnet.log \
      steps/nnet/train.sh \
        --cmvn-opts "--norm-means=true --norm-vars=true" \
        --delta-opts "--delta-order=2" --splice $cnn_splice \
        --network-type cnn1d --cnn-proto-opts "$cnn_proto_opts" \
        --hid-layers $cnn_num_hidden_layers --learn-rate $cnn_learning_rate --train-opts "--verbose 2" \
        ${train}_tr90 ${train}_cv10 data/lang $ali $ali $dir || exit 1;
    touch $dir/.done
  fi
  if false && [ ! -f $dir/decode/.done ]; then
    # Decode
    steps/nnet/decode.sh --nj $dev10h_nj --cmd "$decode_cmd" --config conf/decode_cnn.config --acwt $cnn_acwt \
      $gmm/graph $dev $dir/decode || exit 1;
    touch $dir/decode/.done
  fi
fi

# Pre-train stack of RBMs on top of the convolutional layers (4 layers, 1024 units)
if [ $stage -le 2 ]; then
  dir=exp/cnn4c_pretrain-dbn
  transf_cnn=exp/cnn4c/final.feature_transform_cnn # transform with convolutional layers
  if [ ! -f $dir/.done ]; then
    # Train
    $cuda_cmd $dir/log/pretrain_dbn.log \
      steps/nnet/pretrain_dbn.sh --nn-depth $cnn_dbn_depth --hid-dim $cnn_dbn_hidden_layer_dim --rbm-iter $cnn_rbm_iter_num \
      --feature-transform $transf_cnn --input-vis-type bern \
      --param-stddev-first $cnn_dbn_param_stddev_first --param-stddev $cnn_dbn_param_stddev \
      $train $dir || exit 1
    touch $dir/.done
  fi
fi

# Re-align using CNN
if [ $stage -le 3 ]; then
  dir=exp/cnn4c
  if [ ! -f ${dir}_ali/.done ]; then
    steps/nnet/align.sh --nj $train_nj --cmd "$train_cmd" \
      $train data/lang $dir ${dir}_ali || exit 1
    touch ${dir}_ali/.done
  fi
fi

# Train the DNN optimizing cross-entropy.
if [ $stage -le 4 ]; then
  dir=exp/cnn4c_pretrain-dbn_dnn; [ ! -d $dir ] && mkdir -p $dir/log;
  ali=exp/cnn4c_ali
  feature_transform=exp/cnn4c/final.feature_transform
  feature_transform_dbn=exp/cnn4c_pretrain-dbn/final.feature_transform
  dbn=exp/cnn4c_pretrain-dbn/4.dbn
  cnn_dbn=$dir/cnn_dbn.nnet
  if [ ! -f $dir/.concat_cnn_dbn.done ]; then
    { # Concatenate CNN layers and DBN,
      num_components=$(nnet-info $feature_transform | grep -m1 num-components | awk '{print $2;}')
      nnet-concat "nnet-copy --remove-first-layers=$num_components $feature_transform_dbn - |" $dbn $cnn_dbn \
        2>$dir/log/concat_cnn_dbn.log || exit 1 
    }
    touch $dir/.concat_cnn_dbn.done
  fi
  if [ ! -f $dir/.done ]; then
    # Train
    $cuda_cmd $dir/log/train_nnet.log \
      steps/nnet/train.sh --feature-transform $feature_transform --dbn $cnn_dbn --hid-layers 0 \
      ${train}_tr90 ${train}_cv10 data/lang $ali $ali $dir || exit 1;
    touch $dir/.done
  fi
  if false && [ ! -f $dir/decode/.done ]; then
    # Decode (reuse HCLG graph)
    steps/nnet/decode.sh --nj $dev10h_nj --cmd "$decode_cmd" --config conf/decode_cnn.config --acwt $cnn_acwt \
      $gmm/graph $dev $dir/decode || exit 1;
    touch $dir/decode/.done
  fi
fi

# Sequence training using sMBR criterion, we do Stochastic-GD 
# with per-utterance updates. For RM good acwt is 0.2
dir=exp/cnn4c_pretrain-dbn_dnn_smbr
srcdir=exp/cnn4c_pretrain-dbn_dnn

# First we generate lattices and alignments:
if [ $stage -le 4 ]; then
  if [ ! -f ${srcdir}_ali/.done ]; then
    steps/nnet/align.sh --nj $train_nj --cmd "$train_cmd" \
      $train data/lang $srcdir ${srcdir}_ali || exit 1;
    touch ${srcdir}_ali/.done
  fi
  if [ ! -f ${srcdir}_denlats/.done ]; then
    steps/nnet/make_denlats.sh --nj $train_nj --cmd "$decode_cmd" --config conf/decode_cnn.config --acwt $cnn_acwt \
      $train data/lang $srcdir ${srcdir}_denlats || exit 1;
    touch ${srcdir}_denlats/.done
  fi
fi

# Re-train the DNN by 6 iterations of sMBR 
if [ $stage -le 5 ]; then
  if [ ! -f $dir/.done ]; then
    steps/nnet/train_mpe.sh --cmd "$cuda_cmd" --num-iters 2 --acwt $cnn_acwt --do-smbr true \
      $train data/lang $srcdir ${srcdir}_ali ${srcdir}_denlats $dir || exit 1
    touch $dir/.done
  fi
  # Decode
  for ITER in 1 2; do
    if false && [ ! -f $dir/decode_it${ITER}/.done ]; then
      steps/nnet/decode.sh --nj $dev10h_nj --cmd "$decode_cmd" --config conf/decode_cnn.config \
        --nnet $dir/${ITER}.nnet --acwt $cnn_acwt \
        $gmm/graph $dev $dir/decode_it${ITER} || exit 1
      touch $dir/decode_it${ITER}/.done
    fi
  done 
fi

echo Success
exit 0


