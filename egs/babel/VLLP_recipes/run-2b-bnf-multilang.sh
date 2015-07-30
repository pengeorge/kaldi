#!/bin/bash
# The input feature can be raw or lda (set by feat_type).
# If raw, set splice_width to 5 or 6

server=x33   # the host where exp, data and param are stored.
mlsuffix=6langFLPNN.raw
borrow_from=
langres='101N 104N 105N 106N 107N 204N'
num_jobs_nnet='2 2 2 2 2 2'
ml_mixup='10000 10000 10000 10000 10000 10000'
ml_num_epochs=15

train_stage=-5

## Options for get_egs2 ########
get_egs_stage=0
io_opts="-tc 5" # for jobs with a lot of I/O, limits the number running at one time.   These don't
feat_type=raw  # Can be used to force "raw" features.
cmvn_opts=  # will be passed to get_lda.sh and get_egs.sh, if supplied.  
            # only relevant for "raw" features, not lda.
splice_width=6
################################

. conf/common_vars.sh
. ./lang.conf
. conf/multilang_resource.conf

# This parameter will be used when the training dies at a certain point.
train_stage=-100
. ./utils/parse_options.sh

set -e
set -o pipefail
set -u

exp_dir=exp_bnf_${mlsuffix}
dir=$exp_dir/tri6_bnf  # Working directory
data_bnf_dir=data_bnf_${mlsuffix}
param_bnf_dir=param_bnf_${mlsuffix}

for d in $exp_dir $data_bnf_dir $param_bnf_dir; do
  if [ ! -d $exp_dir ]; then
    remote_d=~/kaldi_exp_${server}/$(basename `pwd`)/$d
    mkdir -p $remote_d
    ln -s $remote_d
  fi
done

if [ ! -z $borrow_from ]; then
  if [ ! -d $dir ]; then
    ln -s `readlink -f $borrow_from/$dir` $dir
  fi
fi

if [ ! -z $feat_type ]; then
  egs_suffix=_${feat_type}${splice_width}
  feat_opts="--feat-type $feat_type"
else
  egs_suffix=
  feat_opts=
fi

get_egs_extra_opts=(--left-context $splice_width)
get_egs_extra_opts+=(--right-context $splice_width)
[ ! -z "$cmvn_opts" ] && get_egs_extra_opts+=(--cmvn-opts "$cmvn_opts")
[ ! -z "$feat_type" ] && get_egs_extra_opts+=($feat_opts)

set +u
# Get egs for all background languages
multilang_opt=
for l in $langres; do
  egs_dir=${mlresource[$l]}${egs_suffix}
  lroot=$(dirname `dirname $egs_dir`)
  alidir=$lroot/exp/tri6b_nnet_ali
  if [ ! -f $egs_dir/.done ]; then
    if [ ! -f $alidir/.done ]; then
      echo "$alidir is not ready"
      exit 1;
    fi
    echo "$0: calling get_egs2.sh for $l"
    steps/nnet2/get_egs2.sh "${get_egs_extra_opts[@]}" --transform-dir $alidir \
        --stage $get_egs_stage --cmd "$train_cmd" --io-opts "$io_opts" \
        $lroot/data/train $alidir $egs_dir || exit 1;
    touch $egs_dir/.done
  fi
  multilang_opt="$multilang_opt $alidir $egs_dir"
done

set -u
if [ ! -f $dir/.done ]; then
  mkdir -p $dir
  echo $langres > $dir/langres
  echo $num_jobs_nnet > $dir/num_jobs_nnet
  echo $ml_mixup > $dir/ml_mixup
  echo $multilang_opt > $dir/multilang_opt
  echo $feat_type > $dir/feat_type
  echo $splice_width > $dir/splice_width
  res_keys=($langres)
  czpScripts/nnet2/train_tanh_bottleneck_multilang.sh \
    --stage $train_stage --mix-up "$ml_mixup" --num-epochs $ml_num_epochs \
    --splice-width $splice_width \
    --initial-learning-rate $bnf_init_learning_rate \
    --final-learning-rate $bnf_final_learning_rate \
    --num-hidden-layers $bnf_multilang_num_hidden_layers \
    --bottleneck-dim $bottleneck_dim --hidden-layer-dim $bnf_hidden_layer_dim \
    --cmd "$train_cmd" --num-jobs-nnet "$num_jobs_nnet" \
    "${dnn_ml_gpu_parallel_opts[@]}" \
    $multilang_opt $(dirname `dirname ${mlresource[${res_keys[0]}]}`)/data/lang $dir || exit 1
  touch $dir/.done
fi

[ ! -d $param_bnf_dir ] && mkdir -p $param_bnf_dir
if [ ! -f $data_bnf_dir/train_bnf/.done ]; then
  mkdir -p $data_bnf_dir
  # put the archives in ${param_bnf_dir}/.
  czpScripts/nnet2/dump_bottleneck_features.chenzp.sh --nj $train_nj --cmd "$train_cmd" \
    --feat-type $feat_type \
    data/train $data_bnf_dir/train_bnf \
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

echo ---------------------------------------------------------------------
echo "$0: next, run run-3b-bnf-nnet-multilang.sh, run-3b-bnf-sgmm-multilang.sh"
echo ---------------------------------------------------------------------
