#!/bin/bash
# The input feature can be raw or lda (set by feat_type).
# If raw, set splice_width to 5 or 6

. conf/common_vars.sh
. ./lang.conf

train_stage=-100
basedir=../101LLP/exp/tri6_nnet.raw_5hid.no_lda

suffix=

ali_dir=exp/tri5_ali
ali_model=exp/tri5/
ali_model_transform_dir=exp/tri5_ali

finetune_type=whole # whole/last/ensemble
num_additional_hidden_layers=0
hidden_config=

## Options for get_egs2 ########
get_egs_stage=-10
io_opts="-tc 5" # for jobs with a lot of I/O, limits the number running at one time.   These don't
################################

echo "$0 $@"
. ./utils/parse_options.sh

set -e
set -o pipefail
set -u

input_model=$basedir/final.mdl
if [ ! -f $basedir/.done ] || [ ! -f $basedir/final.mdl ]; then
  echo "$basedir is not ready."
  exit 1;
fi
lang_pack=`basename $(dirname $(dirname $basedir))`
mdl=`basename $basedir`
dir=exp/dnn_scratch_${lang_pack}__${mdl}_cont # Working directory
case $finetune_type in
  ensemble)
    dir=${dir}_en
    ;;
  last)
    dir=${dir}_last
    ;;
esac

dir=${dir}${suffix}
egs_string=""

if [ ! -f $ali_dir/.done ]; then
  echo "$0: Aligning supervised training data in $ali_dir"

  [ ! -f $ali_model/final.mdl ] && echo -e "$ali_model/final.mdl not found!\nRun training first!" && exit 1
  steps/nnet2/align.sh  --cmd "$train_cmd" \
    --use-gpu no --transform-dir "$ali_model_transform_dir" --nj $train_nj \
    data/train data/lang $ali_model $ali_dir || exit 1
  touch $ali_dir/.done
fi
feat_type=`cat $basedir/feat_type`
splice_width=`cat $basedir/splice_width`


# Use target language data alone to tune again
if [ -f $dir/.done ]; then
  echo "$dir is already done. Remove $dir/.done to re-run."
  exit 0;
else
  # initialize model for non-ensemble training type
  echo "Initializing model ($finetune_type)"
  case $finetune_type in
    whole)
      $train_cmd $dir/log/reinitialize.log \
        nnet-am-reinitialize $input_model $ali_dir/final.mdl $dir/input.mdl || exit 1;
      ;;
    last)
      $train_cmd $dir/log/fix-shallow-and-reinitialize.log \
        nnet-am-fix-shallow-affines $input_model - \| \
        nnet-am-reinitialize - $ali_dir/final.mdl $dir/input.mdl || exit 1;
      ;;
  esac

  # do fine-tuning
  case $finetune_type in
    whole|last)
      # Options transform-dir is only relevant to "raw" features
      czpScripts/nnet2/train_pnorm_fast_continue.sh \
        --feat-type $feat_type --splice-width $splice_width \
        --transform-dir exp/tri5_ali \
        --stage $train_stage --mix-up $dnn_mixup \
        --initial-learning-rate $dnn_init_learning_rate \
        --final-learning-rate $dnn_final_learning_rate \
        --num-additional-hidden-layers $num_additional_hidden_layers \
        --hidden-config "$hidden_config" \
        --cmd "$train_cmd" $egs_string \
        "${dnn_gpu_parallel_opts[@]}" \
        data/train data/lang $ali_dir $dir/input.mdl $dir || exit 1
      ;;
    ensemble)
      # Unlike non-ensemble training , here reinitialization will be done in the training script
      if [ $num_additional_hidden_layers -gt 0 ]; then
        echo "Ensemble fine tuning with additional hidden layers is not supported yet."
        exit 1;
      fi
      # Options transform-dir is only relevant to "raw" features
      czpScripts/nnet2/train_pnorm_ensemble_continue.sh \
        --feat-type $feat_type --splice-width $splice_width \
        --transform-dir exp/tri5_ali \
        --stage $train_stage --mix-up $dnn_mixup \
        --initial-learning-rate $ensemble_dnn_init_learning_rate \
        --final-learning-rate $ensemble_dnn_final_learning_rate \
        --cmd "$train_cmd" $egs_string \
        "${dnn_gpu_parallel_opts[@]}" \
        --ensemble-size $ensemble_size --initial-beta $ensemble_initial_beta --final-beta $ensemble_final_beta \
        data/train data/lang $ali_dir $input_model $dir || exit 1
      ;;
    *)
      echo "Unknown finetune type: $finetune_type"
      exit 1
      ;;
  esac
  cp $ali_dir/cmvn_opts $dir/
  touch $dir/.done
fi
