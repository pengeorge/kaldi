#!/bin/bash
# The input feature can be raw or lda (set by feat_type).
# If raw, set splice_width to 5 or 6

mlsuffix=scratch_6langFLPNN.raw
langres='101N 104N 105N 106N 107N 204N'
num_jobs_nnet='2 2 2 2 2 2'
ml_mixup='5000 5000 5000 5000 5000 5000'
ml_num_epochs=10
ali_for_egs=exp/tri6b_nnet_ali

train_continue_stage=-10
train_stage=-5

finetune=false
ensemble_finetune=true
## Options for LDA ######
use_lda=    # existing lda.mat path
lda_type=   # all/allphone/cluster/none
lda_opts=
## Options for get_egs2 ########
get_egs_stage=0
io_opts="-tc 5" # for jobs with a lot of I/O, limits the number running at one time.   These don't
feat_type=raw  # Can be used to force "raw" features.
cmvn_opts=  # will be passed to get_lda.sh and get_egs.sh, if supplied.  
            # only relevant for "raw" features, not lda.
online_ivector_dir=
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

dir=exp/dnn_$mlsuffix  # Working directory

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
[ ! -z "$online_ivector_dir" ] && get_egs_extra_opts+=(--online-ivector-dir $online_ivector_dir)

mkdir -p $dir
if [ ! -z "$lda_type" ] && [ "$lda_type" != none ]; then
  do_lda=true
  if [ ! -f $dir/.done.lda ]; then
    if [ ! -z $use_lda ]; then
      echo "$0: use existing LDA file: $use_lda"
      if [ ! -f $use_lda ]; then
        echo "lda file '$use_lda' does not exist."
        exit 1;
      fi
      lda_dir=`dirname $use_lda`
      ln -sf $(readlink -f $use_lda) $dir/lda.mat
      ln -sf $(readlink -f $lda_dir)/lda_dim $dir/lda_dim
    else
      echo "$0: calling get_multilang_lda.sh"
      # TODO Train LDA
      lda_multilang_opt=
      for l in $langres; do
        egs_dir=${mlresource[$l]}${egs_suffix}
        lroot=$(dirname `dirname $egs_dir`)
        alidir=$lroot/$ali_for_egs
        lda_multilang_opt="$lda_multilang_opt $lroot $alidir"
      done 
      czpScripts/nnet2/get_multilang_lda.sh $lda_opts "${get_egs_extra_opts[@]}" \
        --lda-type $lda_type --transform-dir tri5_ali --cmd "$train_cmd" \
        $lda_multilang_opt $dir || exit 1;
    fi
    touch $dir/.done.lda
  fi
else
  do_lda=false
fi

set +u
# Get egs for all background languages
multilang_opt=
for l in $langres; do
  egs_dir=${mlresource[$l]}${egs_suffix}
  lroot=$(dirname `dirname $egs_dir`)
  alidir=$lroot/$ali_for_egs
  transdir=$lroot/exp/tri5_ali # will be useful in get_egs only when feat_type=lda
  if [ ! -f $egs_dir/.done ]; then
    if [ ! -f $alidir/.done ]; then
      echo "$alidir is not ready"
      exit 1;
    fi
    echo "$0: calling get_egs2.sh for $l"
    czpScripts/nnet2/get_egs2.get_feat_dim.sh "${get_egs_extra_opts[@]}" --transform-dir $transdir \
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
  echo $ali_for_egs > $dir/ali_for_egs
  echo $multilang_opt >$dir/multilang_opt
  echo $feat_type > $dir/feat_type
  echo $splice_width > $dir/splice_width
  res_keys=($langres)
  czpScripts/nnet2/train_pnorm_multilang_from_scratch.sh \
    --stage $train_stage --mix-up "$ml_mixup" --num-epochs $ml_num_epochs \
    --splice-width $splice_width \
    --do-lda $do_lda \
    --initial-learning-rate $dnn_init_learning_rate \
    --final-learning-rate $dnn_final_learning_rate \
    --num-hidden-layers $dnn_multilang_num_hidden_layers \
    --pnorm-input-dim $dnn_multilang_input_dim \
    --pnorm-output-dim $dnn_multilang_output_dim \
    --cmd "$train_cmd" --num-jobs-nnet "$num_jobs_nnet" \
    "${dnn_ml_gpu_parallel_opts[@]}" \
    $multilang_opt $(dirname `dirname ${mlresource[${res_keys[0]}]}`)/data/lang $dir || exit 1
  touch $dir/.done
fi

if $finetune; then
  # Use target language data alone to tune again
  input_model=$dir/0/final.mdl
  if ! $ensemble_finetune; then
    dir=${dir}_cont
    if [ ! -f $dir/.done ]; then
      $train_cmd $dir/log/reinitialize.log \
        nnet-am-reinitialize $input_model exp/tri6_nnet_ali/final.mdl $dir/input.mdl || exit 1;
      czpScripts/nnet2/train_pnorm_fast_continue.sh \
        $feat_opts --splice-width $splice_width \
        --transform-dir exp/tri5_ali \
        --stage $train_continue_stage --mix-up $dnn_mixup \
        --initial-learning-rate $dnn_init_learning_rate \
        --final-learning-rate $dnn_final_learning_rate \
        --cmd "$train_cmd" \
        "${dnn_gpu_parallel_opts[@]}" \
        data/train data/lang exp/tri6_nnet_ali $dir/input.mdl $dir || exit 1

      cp exp/tri6_nnet_ali/cmvn_opts $dir/
      touch $dir/.done
    fi
  else
    dir=${dir}_cont_en
    if [ ! -f $dir/.done ]; then
      # Initialization is done in the training script
      czpScripts/nnet2/train_pnorm_ensemble_continue.sh \
        $feat_opts --splice-width $splice_width \
        --transform-dir exp/tri5_ali \
        --stage $train_continue_stage --mix-up $dnn_mixup \
        --initial-learning-rate $ensemble_dnn_init_learning_rate \
        --final-learning-rate $ensemble_dnn_final_learning_rate \
        --cmd "$train_cmd" \
        "${dnn_gpu_parallel_opts[@]}" \
        --ensemble-size $ensemble_size --initial-beta $ensemble_initial_beta --final-beta $ensemble_final_beta \
        data/train data/lang exp/tri6_nnet_ali $input_model $dir || exit 1
      cp exp/tri6_nnet_ali/cmvn_opts $dir/
      touch $dir/.done
    fi
  fi
fi
