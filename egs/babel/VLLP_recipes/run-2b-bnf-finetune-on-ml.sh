#!/bin/bash
# The input feature can be raw or lda (set by feat_type).
# If raw, set splice_width to 5 or 6

bnf_train_stage=-100

server=x32   # the host where exp, data and param are stored.
mldir=../204VLLP.new/exp_bnf_6langFLPNN.raw/tri6_bnf
semisupervised=true
unsup_string="_semisup"
suffix=
unsupid=unsup.seg
ext_in_unsup_decode=_ext
ali_dir=exp/tri5_ali
ali_model=exp/tri5/
bnf_weight_threshold=0.35 
weights_dir=exp_bnf_semisup/best_path_weights/unsup.seg_ext/decode_unsup.seg_ext_epoch1/

## Options for get_egs2 ########
get_egs_stage=-10
io_opts="-tc 5" # for jobs with a lot of I/O, limits the number running at one time.   These don't
################################

. conf/common_vars.sh
. ./lang.conf
. conf/multilang_resource.conf

. ./utils/parse_options.sh

input_model=$mldir/0/final.mdl

set -e
set -o pipefail
set -u

if [ $babel_type == "full" ] && $semisupervised; then
  echo "Error: Using unsupervised training for fullLP is meaningless, use semisupervised=false "
  exit 1
fi

if ! $semisupervised ; then
  unsup_string=""  #" ": supervised training, _semi_supervised: unsupervised BNF training
fi

exp_dir=`basename $(dirname $mldir)`_ft${unsup_string}${suffix}
dir=$exp_dir/tri6_bnf  # Working directory
data_bnf_dir=`echo $exp_dir | sed 's/exp/data/'`
param_bnf_dir=`echo $exp_dir | sed 's/exp/param/'`

if $semisupervised ; then
  egs_string="--egs-dir $dir/egs"
else
  egs_string=""
fi

for d in $exp_dir $data_bnf_dir $param_bnf_dir; do
  if [ ! -d $d ]; then
    remote_d=~/kaldi_exp_${server}/$(basename `pwd`)/$d
    mkdir -p $remote_d
    ln -s $remote_d
  fi
done

if [ ! -f $ali_dir/.done ]; then
  echo "$0: Aligning supervised training data in exp/tri6_nnet_ali"

  [ ! -f $ali_model/final.mdl ] && echo -e "$ali_model/final.mdl not found!\nRun run-6-nnet.sh first!" && exit 1
  steps/nnet2/align.sh  --cmd "$train_cmd" \
    --use-gpu no --transform-dir exp/tri5_ali --nj $train_nj \
    data/train data/lang $ali_model $ali_dir || exit 1
  touch $ali_dir/.done
fi

feat_type=`cat $mldir/feat_type`
splice_width=`cat $mldir/splice_width`
if $semisupervised ; then
  [ ! -d data/${unsupid} ] && echo "Error: data/${unsupid} is not available!" && exit 1;
  echo "$0: Generate examples using unsupervised data in $dir"
  if [ ! -f $dir/egs/.done ]; then
    ./czpScripts/nnet2/get_egs_semi_supervised.chenzp.sh \
      --cmd "$train_cmd" --stage $get_egs_stage \
      "${dnn_update_egs_opts[@]}" \
      --feat-type $feat_type \
      --splice-width $splice_width \
      --transform-dir-sup exp/tri5_ali \
      --transform-dir-unsup exp/tri5/decode_${unsupid}${ext_in_unsup_decode} \
      --weight-threshold $bnf_weight_threshold \
      data/train data/${unsupid} data/lang${ext_in_unsup_decode} \
      $ali_dir $weights_dir $dir || exit 1;
    touch $dir/egs/.done
  fi
fi  
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
