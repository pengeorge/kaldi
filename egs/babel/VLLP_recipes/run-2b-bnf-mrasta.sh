#!/bin/bash

# Copyright 2014  Pegah Ghahremani
# Apache 2.0

#Run supervised and semisupervised BNF training
#This yields approx 70 hours of data

set -e           #Exit on non-zero return code from any command
set -o pipefail  #Exit if any of the commands in the pipeline will
                 #return non-zero return code
. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;

set -u           #Fail on an undefined variable
semisupervised=false

do_lda_first_nn=true
first_nn_splice=0
first_nn_lda_dim=200
do_lda_first_bn=true
first_bn_splice=4 # (2*4+1)*42=378
first_bn_lda_dim=200
do_lda_second_nn=true
second_nn_splice=0
second_nn_lda_dim=200

## LDA Config of v1 ----------
#do_lda_first_nn=false
#first_nn_splice=0
#first_nn_lda_dim=
#do_lda_first_bn=false
#first_bn_splice=2
#first_bn_lda_dim=
#do_lda_second_nn=false
#second_nn_splice=0
#second_nn_lda_dim=
# ----------------------------

unsup_string="_semisup"
suffix=
bnf_train_stage=-100
bnf_weight_threshold=0.35
ali_dir=
ali_model=exp/tri6b_nnet/
weights_dir=exp_bnf${unsup_string}/best_path_weights/unsup.seg/decode_unsup.seg/

. ./utils/parse_options.sh

if [ $babel_type == "full" ] && $semisupervised; then
  echo "Error: Using unsupervised training for fullLP is meaningless, use semisupervised=false "
  exit 1
fi


if $semisupervised ; then
  echo "Not supported yet"
  exit 1;
  egs_string="--egs-dir exp_bnf${unsup_string}/tri6_bnf/egs"
  dirid=unsup.seg
else
  unsup_string=""  #" ": supervised training, _semi_supervised: unsupervised BNF training
  egs_string=""
  dirid=train
fi

datadir=data/${dirid}
exp_dir=exp_bnf_mrasta${unsup_string}${suffix}
data_bnf_dir=data_bnf_mrasta${unsup_string}${suffix}
param_bnf_dir=param_bnf_mrasta${unsup_string}${suffix}

if [ -z $ali_dir ] ; then
  # If alignment directory is not done, use exp/tri6_nnet_ali as alignment 
  # directory
  ali_dir=exp/tri6_nnet_ali
fi

if [ ! -f $ali_dir/.done ]; then
  echo "$0: Aligning supervised training data in exp/tri6_nnet_ali"

  [ ! -f $ali_model/final.mdl ] && echo -e "$ali_model/final.mdl not found!\nRun run-6-nnet.sh first!" && exit 1
  steps/nnet2/align.sh  --cmd "$train_cmd" \
    --use-gpu no --transform-dir exp/tri5_ali --nj $train_nj \
    data/train data/lang $ali_model $ali_dir || exit 1
  touch $ali_dir/.done
fi

###############################################################################
#
# 1st Semi-supervised BNF training
#
###############################################################################
hi_exp_dir=${exp_dir}.hi
hi_data_bnf_dir=${data_bnf_dir}.hi
hi_param_bnf_dir=${param_bnf_dir}.hi
mkdir -p $hi_exp_dir/tri6_bnf  
if [ ! -f $hi_exp_dir/tri6_bnf/.done ]; then    
  if $semisupervised ; then

    [ ! -d $datadir ] && echo "Error: $datadir is not available!" && exit 1;
    echo "$0: Generate examples using unsupervised data in $hi_exp_dir/tri6_nnet"
    if [ ! -f $hi_exp_dir/tri6_bnf/egs/.done ]; then
      ./czpScripts/nnet2/get_egs_semi_supervised.chenzp.sh \
        --cmd "$train_cmd" \
        "${dnn_update_egs_opts[@]}" \
        --transform-dir-sup exp/tri5_ali \
        --transform-dir-unsup exp/tri5/decode_${dirid} \
        --weight-threshold $bnf_weight_threshold \
        data/train $datadir data/lang \
        $ali_dir $weights_dir $hi_exp_dir/tri6_bnf || exit 1;
      touch $hi_exp_dir/tri6_bnf/egs/.done
    fi
   
  fi  

 echo "$0: Train 1st Bottleneck network"
  # --transform-dir exp/tri5_ali is only used when egs is not ready, which means fully-supervised case
  lda_opts="--feat-type raw"
  if [ ! -z "$first_nn_lda_dim" ]; then  # otherwise LDA would not reduce dimension.
    lda_opts="$lda_opts --lda-dim $first_nn_lda_dim"
  fi
  czpScripts/nnet2/train_tanh_bottleneck.chenzp.sh \
    --stage $bnf_train_stage --num-jobs-nnet $mrasta_bnf_num_jobs \
    --egs-opts " --feat-type raw " --splice-width $first_nn_splice --do-lda $do_lda_first_nn --lda-opts "$lda_opts" \
    --num-threads $mrasta_bnf_num_threads --mix-up $mrasta_bnf_mixup \
    --minibatch-size $mrasta_bnf_minibatch_size \
    --initial-learning-rate $mrasta_bnf_init_learning_rate \
    --final-learning-rate $mrasta_bnf_final_learning_rate \
    --num-hidden-layers $mrasta_bnf_num_hidden_layers \
    --bottleneck-dim $mrasta_bottleneck_dim --hidden-layer-dim $mrasta_bnf_hidden_layer_dim \
    --cmd "$train_cmd" $egs_string  \
    "${dnn_gpu_parallel_opts[@]}" \
    data_mrasta.hi/train data/lang $ali_dir $hi_exp_dir/tri6_bnf || exit 1

  touch $hi_exp_dir/tri6_bnf/.done
fi

[ ! -d $hi_param_bnf_dir ] && mkdir -p $hi_param_bnf_dir
if [ ! -f $hi_data_bnf_dir/train_bnf/.done ]; then
  mkdir -p $hi_data_bnf_dir
  echo mrasta > $hi_data_bnf_dir/input_feats
  # put the archives in ${hi_param_bnf_dir}/.
  czpScripts/nnet2/dump_bottleneck_features.chenzp.sh --nj $train_nj --cmd "$train_cmd" \
    --feat-type raw \
    data_mrasta.hi/train $hi_data_bnf_dir/train_bnf \
    $hi_exp_dir/tri6_bnf $hi_param_bnf_dir $hi_exp_dir/dump_bnf
  touch $hi_data_bnf_dir/train_bnf/.done
fi 

if [ ! $hi_data_bnf_dir/train/.done -nt $hi_data_bnf_dir/train_bnf/.done ]; then
  for data_src in $hi_data_bnf_dir/train_bnf data_mrasta.lo/train; do
    utils/split_data.sh $data_src $train_nj || exit 1;
  done
  mkdir -p $hi_data_bnf_dir/train
  for f in segments spk2utt utt2spk wav.scp text reco2file_and_channel stm; do
    if [ -f $hi_data_bnf_dir/train_bnf/$f ]; then
      cp $hi_data_bnf_dir/train_bnf/$f $hi_data_bnf_dir/train/
    fi
  done

  splice_opts=" --left-context=$first_bn_splice --right-context=$first_bn_splice "
  hi_feats="ark,s,cs:splice-feats $splice_opts scp:$hi_data_bnf_dir/train_bnf/split${train_nj}/JOB/feats.scp ark:- |"
  echo $splice_opts > $hi_data_bnf_dir/bnf1_splice_opts
  if $do_lda_first_bn; then
    lda_opts="--feat-type raw"
    if [ ! -z "$first_bn_lda_dim" ]; then  # otherwise LDA would not reduce dimension.
      lda_opts="$lda_opts --lda-dim $first_bn_lda_dim"
    fi
    # LDA/PCA
    mkdir -p $hi_data_bnf_dir/train/hi_bn_lda
    echo "$0: calling get_lda.sh for BN features of 1st NN"
    steps/nnet2/get_lda.sh $lda_opts --splice-width $first_bn_splice --cmd "$train_cmd"  $hi_data_bnf_dir/train_bnf data/lang $ali_dir $hi_data_bnf_dir/train/hi_bn_lda
    hi_feats="$hi_feats transform-feats $hi_data_bnf_dir/train/hi_bn_lda/lda.mat ark:- ark:- |" 
  fi

  czpScripts/steps/append_feats_ext.sh --cmd "$train_cmd" --nj $train_nj \
    "$hi_feats" "scp:data_mrasta.lo/train/split${train_nj}/JOB/feats.scp" $hi_data_bnf_dir/train \
    $hi_exp_dir/append_feats/log $hi_param_bnf_dir/ 
  steps/compute_cmvn_stats.sh --fake $hi_data_bnf_dir/train \
  $hi_exp_dir/append_feats_cmvn $hi_param_bnf_dir
  touch $hi_data_bnf_dir/train/.done
fi
###############################################################################
#
# 2nd Semi-supervised BNF training
#
###############################################################################
mkdir -p $exp_dir/tri6_bnf  
if [ ! -f $exp_dir/tri6_bnf/.done ]; then    
  if $semisupervised ; then

    [ ! -d $datadir ] && echo "Error: $datadir is not available!" && exit 1;
    echo "$0: Generate examples using unsupervised data in $exp_dir/tri6_nnet"
    if [ ! -f $exp_dir/tri6_bnf/egs/.done ]; then
      ./czpScripts/nnet2/get_egs_semi_supervised.chenzp.sh \
        --cmd "$train_cmd" \
        "${dnn_update_egs_opts[@]}" \
        --transform-dir-sup exp/tri5_ali \
        --transform-dir-unsup exp/tri5/decode_${dirid} \
        --weight-threshold $bnf_weight_threshold \
        data/train $datadir data/lang \
        $ali_dir $weights_dir $exp_dir/tri6_bnf || exit 1;
      touch $exp_dir/tri6_bnf/egs/.done
    fi
   
  fi  

 echo "$0: Train 2nd Bottleneck network"
  # --transform-dir exp/tri5_ali is only used when egs is not ready, which means fully-supervised case
  lda_opts="--feat-type raw"
  if [ ! -z "$second_nn_lda_dim" ]; then  # otherwise LDA would not reduce dimension.
    lda_opts="$lda_opts --lda-dim $second_nn_lda_dim"
  fi
  czpScripts/nnet2/train_tanh_bottleneck.chenzp.sh \
    --stage $bnf_train_stage --num-jobs-nnet $mrasta_bnf_num_jobs \
    --egs-opts " --feat-type raw " --splice-width $second_nn_splice --do-lda $do_lda_second_nn --lda-opts "$lda_opts" \
    --num-threads $mrasta_bnf_num_threads --mix-up $mrasta_bnf_mixup \
    --minibatch-size $mrasta_bnf_minibatch_size \
    --initial-learning-rate $mrasta_bnf_init_learning_rate \
    --final-learning-rate $mrasta_bnf_final_learning_rate \
    --num-hidden-layers $mrasta_bnf_num_hidden_layers \
    --bottleneck-dim $mrasta_bottleneck_dim --hidden-layer-dim $mrasta_bnf_hidden_layer_dim \
    --cmd "$train_cmd" $egs_string  \
    "${dnn_gpu_parallel_opts[@]}" \
    $hi_data_bnf_dir/train data/lang $ali_dir $exp_dir/tri6_bnf || exit 1

  touch $exp_dir/tri6_bnf/.done
fi

[ ! -d $param_bnf_dir ] && mkdir -p $param_bnf_dir
if [ ! -f $data_bnf_dir/train_bnf/.done ]; then
  mkdir -p $data_bnf_dir
  echo mrasta > $data_bnf_dir/input_feats
  # put the archives in ${param_bnf_dir}/.
  czpScripts/nnet2/dump_bottleneck_features.chenzp.sh --nj $train_nj --cmd "$train_cmd" \
    --feat-type raw \
    $hi_data_bnf_dir/train $data_bnf_dir/train_bnf \
    $exp_dir/tri6_bnf $param_bnf_dir $exp_dir/dump_bnf
  touch $data_bnf_dir/train_bnf/.done
fi 

if [ ! $data_bnf_dir/train/.done -nt $data_bnf_dir/train_bnf/.done ]; then
  czpScripts/nnet/make_fmllr_feats.chenzp.sh --cmd "$train_cmd -tc 10" \
    --nj $train_nj --transform-dir exp/tri5_ali  $data_bnf_dir/train_sat data/train \
    exp/tri5_ali $exp_dir/make_fmllr_feats/log $param_bnf_dir  

  # TODO Set length tolerance very large, since frames with mrasta features are often fewer than those with fMLLR.
  # There may be something configurable in RASR to avoid this problem.
  steps/append_feats.sh --cmd "$train_cmd" --nj $train_nj \
    --length_tolerance 999 \
    $data_bnf_dir/train_bnf $data_bnf_dir/train_sat $data_bnf_dir/train \
    $exp_dir/append_feats/log $param_bnf_dir/ 
  steps/compute_cmvn_stats.sh --fake $data_bnf_dir/train \
  $exp_dir/make_fmllr_feats $param_bnf_dir
  rm -r $data_bnf_dir/train_sat
  utils/fix_data_dir.sh $data_bnf_dir/train

  touch $data_bnf_dir/train/.done
fi

if [ ! $exp_dir/tri5/.done -nt $data_bnf_dir/train/.done ]; then
  steps/train_lda_mllt.sh --splice-opts "--left-context=1 --right-context=1" \
    --dim 60 --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesMLLT $numGaussMLLT $data_bnf_dir/train data/lang exp/tri5_ali $exp_dir/tri5 ;
  touch $exp_dir/tri5/.done
fi

if [ ! $exp_dir/tri6/.done -nt $exp_dir/tri5/.done ]; then
  steps/train_sat.sh --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesSAT $numGaussSAT $data_bnf_dir/train data/lang \
    $exp_dir/tri5 $exp_dir/tri6
  touch $exp_dir/tri6/.done
fi

echo ---------------------------------------------------------------------
echo "$0: next, run run-6-bnf-sgmm-semisupervised.sh"
echo ---------------------------------------------------------------------

exit 0;
