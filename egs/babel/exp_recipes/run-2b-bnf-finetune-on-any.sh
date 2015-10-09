#!/bin/bash
# The input feature can be raw or lda (set by feat_type).
# If raw, set splice_width to 5 or 6

bnf_train_stage=-100

server=x32   # the host where exp, data and param are stored.
basedir=../101LLP/exp_bnf.raw_3hid/tri6_bnf
suffix=
unsupid=unsup.seg
ext_in_unsup_decode=_ext
ali_dir=exp/tri5_ali
ali_model=exp/tri5/

## Options for get_egs2 ########
get_egs_stage=-10
io_opts="-tc 5" # for jobs with a lot of I/O, limits the number running at one time.   These don't
################################

. conf/common_vars.sh
. ./lang.conf
. conf/multilang_resource.conf

. ./utils/parse_options.sh

input_model=$basedir/final.mdl

set -e
set -o pipefail
set -u

lang_pack=`basename $(dirname $(dirname $basedir))`
mdl=`basename $basedir`
exp_dir=${lang_pack}_`basename $(dirname $basedir)`_ft${suffix}
dir=$exp_dir/tri6_bnf  # Working directory
data_bnf_dir=`echo $exp_dir | sed 's/exp/data/'`
param_bnf_dir=`echo $exp_dir | sed 's/exp/param/'`

egs_string=""
echo $exp_dir
echo $dir

for d in $exp_dir $data_bnf_dir $param_bnf_dir; do
  if [ ! -d $d ]; then
    remote_d=~/kaldi_exp_${server}/$(basename `pwd`)/$d
    mkdir -p $remote_d
    ln -s $remote_d
  fi
done

if [ ! -f $ali_dir/.done ]; then
  echo "$0: Aligning supervised training data in exp/tri6_nnet_ali"

  [ ! -f $ali_model/final.mdl ] && echo -e "$ali_model/final.mdl not found!\nRun training first!" && exit 1
  steps/nnet2/align.sh  --cmd "$train_cmd" \
    --use-gpu no --transform-dir exp/tri5_ali --nj $train_nj \
    data/train data/lang $ali_model $ali_dir || exit 1
  touch $ali_dir/.done
fi

feat_type=`cat $basedir/feat_type`
splice_width=`cat $basedir/splice_width`
if [ ! -f $dir/.done ]; then
  mkdir -p $dir
  $train_cmd $dir/log/reinitialize.log \
    nnet-am-reinitialize $input_model $ali_dir/final.mdl $dir/input.mdl || exit 1;
  czpScripts/nnet2/train_tanh_bottleneck_continue.sh \
    --feat-type $feat_type --splice-width $splice_width \
    --stage $bnf_train_stage --num-jobs-nnet $bnf_num_jobs \
    --transform-dir exp/tri5_ali \
    --num-threads $bnf_num_threads --mix-up $bnf_mixup \
    --minibatch-size $bnf_minibatch_size \
    --initial-learning-rate $bnf_cont_init_learning_rate \
    --final-learning-rate $bnf_cont_final_learning_rate \
    --cmd "$train_cmd" $egs_string  \
    "${dnn_gpu_parallel_opts[@]}" \
    data/train data/lang $ali_dir $dir/input.mdl $dir || exit 1
  touch $dir/.done
fi

[ ! -d $param_bnf_dir ] && mkdir -p $param_bnf_dir
if [ ! -f $data_bnf_dir/train_bnf/.done ]; then
  mkdir -p $data_bnf_dir
  # put the archives in ${param_bnf_dir}/.
  czpScripts/nnet2/dump_bottleneck_features.chenzp.sh --nj $train_nj --cmd "$train_cmd" \
    --feat-type $feat_type --transform-dir "`cat $dir/transform_dir`" \
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
