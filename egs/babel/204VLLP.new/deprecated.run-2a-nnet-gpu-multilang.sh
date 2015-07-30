#!/bin/bash
initdir=exp/dnn_init
mlsuffix=4lang10hr
langres='101LLP 104LLP 105LLP 106LLP'
num_jobs_nnet='2 2 2 2 2'
ml_mixup='5000 5000 5000 5000 5000'

train_init_stage=-10
train_continue_stage=-10
train_stage=-4

## Options for get_egs2 ########
get_egs_stage=0
io_opts="-tc 5" # for jobs with a lot of I/O, limits the number running at one time.   These don't
feat_type=  # Can be used to force "raw" features.
cmvn_opts=  # will be passed to get_lda.sh and get_egs.sh, if supplied.  
            # only relevant for "raw" features, not lda.
online_ivector_dir=
splice_width=4
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

dir=exp/dnn_$mlsuffix
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

# Train initial nnet model
if [ ! -f $initdir/.done ]; then
  # Wait till the main run.sh gets to the stage where's it's 
  # finished aligning the tri5 model.
  echo "Waiting till exp/tri5_ali/.done exists...."
  while [ ! -f exp/tri5_ali/.done ]; do sleep 30; done
  echo "...done waiting for exp/tri5_ali/.done"
  steps/nnet2/train_pnorm_fast.sh \
    $feat_opts --splice-width $splice_width \
    --stage $train_init_stage --mix-up 0 --cleanup false \
    --initial-learning-rate $dnn_init_learning_rate \
    --final-learning-rate $dnn_final_learning_rate \
    --num-hidden-layers $dnn_num_hidden_layers \
    --pnorm-input-dim $dnn_multilang_input_dim \
    --pnorm-output-dim $dnn_multilang_output_dim \
    --cmd "$train_cmd" \
    "${dnn_gpu_parallel_opts[@]}" \
    data/train data/lang exp/tri5_ali $initdir || exit 1
  touch $initdir/.done
fi


set +u
# Get egs for target language
egs_dir=exp/tri5_egs${egs_suffix}
alidir=exp/tri5_ali
if [ ! -f $egs_dir/.done ]; then
  echo "$0: calling get_egs2.sh for target language"
  steps/nnet2/get_egs2.sh "${get_egs_extra_opts[@]}" --transform-dir $alidir \
      --stage $get_egs_stage --cmd "$train_cmd" --io-opts "$io_opts" \
      data/train $alidir $egs_dir || exit 1;
  touch $egs_dir/.done
fi
# Get egs for other languages
multilang_opt="$alidir $egs_dir"
for l in $langres; do
  egs_dir=${mlresource[$l]}${egs_suffix}
  lroot=$(dirname `dirname $egs_dir`)
  alidir=$lroot/exp/tri5_ali
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
  steps/nnet2/train_multilang2.sh \
    --stage $train_stage --mix-up "$ml_mixup" \
    --initial-learning-rate $dnn_init_learning_rate \
    --final-learning-rate $dnn_final_learning_rate \
    --cmd "$train_cmd" --num-jobs-nnet "$num_jobs_nnet" \
    "${dnn_ml_gpu_parallel_opts[@]}" \
     $multilang_opt $initdir/20.mdl $dir || exit 1
  touch $dir/.done
fi

# Use target language data alone to tune again
input_model=$dir/0/final.mdl
dir=${dir}_cont
if [ ! -f $dir/.done ]; then
  steps/nnet2/train_pnorm_fast_continue.sh \
    $feat_opts --splice-width $splice_width \
    --stage $train_continue_stage --mix-up $dnn_mixup \
    --initial-learning-rate $dnn_init_learning_rate \
    --final-learning-rate $dnn_final_learning_rate \
    --cmd "$train_cmd" \
    "${dnn_gpu_parallel_opts[@]}" \
    data/train data/lang exp/tri5_ali $input_model $dir || exit 1

  touch $dir/.done
fi
