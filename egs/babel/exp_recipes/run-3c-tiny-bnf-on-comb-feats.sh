#!/bin/bash
data_dir=data_concat_4lang10hr.raw_3hid
exp_dir=
splice_width=0
feat_type=raw
do_lda=true  # LDA in NN
feat_mix= # vector_mix/scalar_mix
feat_mix_block_dim=42
feat_mix_const_dim=0
feat_mix_num_blocks=4 
train_stage=-10

. conf/common_vars.sh
. ./lang.conf

# This parameter will be used when the training dies at a certain point.
train_stage=-100
. ./utils/parse_options.sh

set -e
set -o pipefail
set -u

if [ -z "$data_dir" ]; then
  echo "data_dir is empty"
  exit 1;
fi
if [ -z "$exp_dir" ]; then
  exp_dir=`echo $data_dir | sed 's/data/exp_bnf/'`
fi

data_bnf_dir=`echo $exp_dir | sed 's/exp/data/'`
param_bnf_dir=`echo $exp_dir | sed 's/exp/param/'`

exp_dir=${exp_dir}/tri6_bnf

# Wait till the main run.sh gets to the stage where's it's 
# finished aligning the tri5 model.
echo "Waiting till exp/tri5_ali/.done exists...."
while [ ! -f exp/tri5_ali/.done ]; do sleep 30; done
echo "...done waiting for exp/tri5_ali/.done"

feat_mix_opts=
if $do_lda; then
  if [ ! -z "$feat_mix" ]; then
    echo "do_lda=true and feat_mix=true, not supported"
    exit 1;
  fi
  train_script=??  #czpScripts/nnet2/train_pnorm_fast_ext.sh
else
  train_script=czpScripts/nnet2/train_single_layer_bottleneck.sh
  exp_dir=${exp_dir}.no_lda
  if [ ! -z "$feat_mix" ]; then
    feat_mix_opts=" --feat-mix $feat_mix --feat-mix-block-dim $feat_mix_block_dim --feat-mix-const-dim $feat_mix_const_dim "
    exp_dir=${exp_dir}.${feat_mix}
  fi
fi

if [ ! -f $exp_dir/.done ]; then
  $train_script $feat_mix_opts \
    --feat-type $feat_type \
    --stage $train_stage --mix-up $dnn_mixup \
    --initial-learning-rate $dnn_init_learning_rate \
    --final-learning-rate $dnn_final_learning_rate \
    --pnorm-input-dim $dnn_input_dim \
    --pnorm-output-dim $dnn_output_dim \
    --cmd "$train_cmd" \
    "${dnn_gpu_parallel_opts[@]}" \
    $data_dir/train data/lang exp/tri5_ali $exp_dir || exit 1

  touch $exp_dir/.done
fi

# some variables are inconsistent with the followed code
dir=$exp_dir
exp_dir=`dirname $exp_dir`

[ ! -d $param_bnf_dir ] && mkdir -p $param_bnf_dir
if [ ! -f $data_bnf_dir/train_bnf/.done ]; then
  mkdir -p $data_bnf_dir
  # put the archives in ${param_bnf_dir}/.
  czpScripts/nnet2/dump_bottleneck_features.chenzp.sh --nj $train_nj --cmd "$train_cmd" \
    --feat-type $feat_type --transform-dir "`cat $dir/transform_dir`" \
    $data_dir/train $data_bnf_dir/train_bnf \
    $dir $param_bnf_dir $exp_dir/dump_bnf
  touch $data_bnf_dir/train_bnf/.done
fi 

if [ ! $data_bnf_dir/train/.done -nt $data_bnf_dir/train_bnf/.done ]; then
  czpScripts/nnet/make_fmllr_feats.chenzp.sh --cmd "$train_cmd -tc 10" \
    --nj $train_nj --transform-dir exp/tri5_ali  $data_bnf_dir/train_sat data/train \
    exp/tri5_ali $exp_dir/make_fmllr_feats/log $param_bnf_dir  

  steps/append_feats.sh --cmd "$train_cmd" --nj $train_nj \
    $data_bnf_dir/train_bnf $data_bnf_dir/train_sat $data_bnf_dir/train \
    $exp_dir/append_feats/log $param_bnf_dir/ 
  steps/compute_cmvn_stats.sh --fake $data_bnf_dir/train \
  $exp_dir/make_fmllr_feats $param_bnf_dir
  rm -r $data_bnf_dir/train_sat

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

