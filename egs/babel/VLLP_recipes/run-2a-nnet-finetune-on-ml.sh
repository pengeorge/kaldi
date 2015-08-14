#!/bin/bash
# The input feature can be raw or lda (set by feat_type).
# If raw, set splice_width to 5 or 6

train_stage=-100
mldir=../204VLLP.new/exp/dnn_scratch_6langFLPNN.raw

semisupervised=false
unsupid=unsup.seg
suffix=

ali_dir=exp/tri6_nnet_ali
ali_model=exp/tri6b_nnet/
ali_model_transform_dir=exp/tri5_ali

finetune_type=whole # whole/softmax/ensemble
bnf_weight_threshold=0.7
weights_dir=exp_bnf_semisup/best_path_weights/unsup.seg/decode_unsup.seg/
## Options for get_egs2 ########
get_egs_stage=-10
io_opts="-tc 5" # for jobs with a lot of I/O, limits the number running at one time.   These don't
################################

. conf/common_vars.sh
. ./lang.conf

# This parameter will be used when the training dies at a certain point.
. ./utils/parse_options.sh

set -e
set -o pipefail
set -u

input_model=$mldir/0/final.mdl
dir=exp/`basename $mldir`_cont  # Working directory
case $finetune_type in
  ensemble)
    dir=${dir}_en
    ;;
  last)
    dir=${dir}_last
    ;;
esac

if $semisupervised ; then
  dir=${dir}_semisup${bnf_weight_threshold}
fi
dir=${dir}${suffix}
if $semisupervised ; then
  egs_string="--egs-dir $dir/egs"
else
  egs_string=""
fi

if [ ! -f $ali_dir/.done ]; then
  echo "$0: Aligning supervised training data in $ali_dir"

  [ ! -f $ali_model/final.mdl ] && echo -e "$ali_model/final.mdl not found!\nRun run-6-nnet.sh first!" && exit 1
  steps/nnet2/align.sh  --cmd "$train_cmd" \
    --use-gpu no --transform-dir "$ali_model_transform_dir" --nj $train_nj \
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
      --transform-dir-unsup exp/tri5/decode_${unsupid} \
      --weight-threshold $bnf_weight_threshold \
      data/train data/${unsupid} data/lang \
      $ali_dir $weights_dir $dir || exit 1;
    touch $dir/egs/.done
  fi
fi  

# Use target language data alone to tune again
if [ -f $dir/.done ]; then
  echo "$dir is already done. Remove $dir/.done to re-run."
  exit 0;
else
  # initialize model for non-ensemble training type
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
      czpScripts/nnet2/train_pnorm_fast_continue.sh \
        --feat-type $feat_type --splice-width $splice_width \
        --transform-dir exp/tri5_ali \
        --stage $train_stage --mix-up $dnn_mixup \
        --initial-learning-rate $dnn_init_learning_rate \
        --final-learning-rate $dnn_final_learning_rate \
        --cmd "$train_cmd" $egs_string \
        "${dnn_gpu_parallel_opts[@]}" \
        data/train data/lang $ali_dir $dir/input.mdl $dir || exit 1
      ;;
    ensemble)
      # Unlike non-ensemble training , here reinitialization will be done in the training script
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
