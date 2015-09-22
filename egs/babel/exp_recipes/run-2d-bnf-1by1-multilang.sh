#!/bin/bash
# The input feature can be raw or lda (set by feat_type).
# If raw, set splice_width to 5 or 6

server=x33   # the host where exp, data and param are stored.
langres='101LLP 104LLP 105LLP 106LLP'
num_epochs=15

## Options for get_egs2 ########
get_egs_stage=0
io_opts="-tc 5" # for jobs with a lot of I/O, limits the number running at one time.   These don't
cmvn_opts=  # will be passed to get_lda.sh and get_egs.sh, if supplied.  
            # only relevant for "raw" features, not lda.
do_lda=true
splice_width=6
samples_per_iter=200000
################################

. conf/common_vars.sh
. ./lang.conf
. conf/multilang_resource.conf

unit_type=tanh # tanh/pnorm
bottleneck_dim=42
# This parameter will be used when the training dies at a certain point.
train_lang_stage=0
train_stage=-100
. ./utils/parse_options.sh

set -e
set -o pipefail
set -u

feat_type=raw  # force "raw" features.
if [ ! -z $feat_type ]; then
  lda_suffix=_${feat_type}${splice_width}
  feat_opts="--feat-type $feat_type"
else
  lda_suffix=
  feat_opts=
fi

get_lda_extra_opts=(--left-context $splice_width)
get_lda_extra_opts+=(--right-context $splice_width)
[ ! -z "$cmvn_opts" ] && get_lda_extra_opts+=(--cmvn-opts "$cmvn_opts")
[ ! -z "$feat_type" ] && get_lda_extra_opts+=($feat_opts)

exp_dir_root=exp_bnf.${feat_type}_1by1
data_bnf_dir_root=data_bnf.${feat_type}_1by1
param_bnf_dir_root=param_bnf.${feat_type}_1by1

if [ ! -z "$unit_type" ] && [ $unit_type != tanh ]; then
  exp_dir_root=${exp_dir_root}.$unit_type
  data_bnf_dir_root=${data_bnf_dir_root}.$unit_type
  param_bnf_dir_root=${param_bnf_dir_root}.$unit_type
fi

arr_langid=($langres)
dir_suffix=()
num_lang=${#arr_langid[@]}
echo "running $0 for $num_lang languages"
langs_so_far=
for l in `seq 0 $[num_lang-1]`; do
  langid=${arr_langid[$l]}
  langs_so_far="${langs_so_far} $langid"
  if [ $l -gt 0 ]; then
    dir_suffix[$l]=${dir_suffix[$[l-1]]}_$langid
  else
    dir_suffix[$l]=_$langid
  fi
  if [ $train_lang_stage -gt $l ]; then # this will skip a lang, but dir must be set correctly
    exp_dir=${exp_dir_root}${dir_suffix[$l]}
    data_bnf_dir=${data_bnf_dir_root}${dir_suffix[$l]}
    param_bnf_dir=${param_bnf_dir_root}${dir_suffix[$l]}
    continue
  fi
  egs_dir=${mlresource[$langid]}1   # will use get_egs, not get_egs2
  lda_dir=`echo $egs_dir | sed 's/egs/lda/'`
  egs_dir=${egs_dir}${lda_suffix}
  lda_dir=${lda_dir}${lda_suffix}
  lroot=$(dirname `dirname $lda_dir`)
  alidir=$lroot/exp/tri5_ali

  if [ $l -eq 0 ]; then
    bnf_dim_opts=" --feat-const-dim 0"
    train_data_dir=$lroot/data/train
  else
    bnf_dim_opts=" --feat-const-dim $[$l*$bottleneck_dim]"
    [ ! -d $param_bnf_dir ] && mkdir -p $param_bnf_dir
    for k in `seq $l $[num_lang-1]`; do
      this_langid=${arr_langid[$k]}
      this_lroot=$(dirname `dirname ${mlresource[$this_langid]}`)
      this_dump_out_dir=$data_bnf_dir/${this_langid}_train_bnf
      if [ ! -f $this_dump_out_dir/.done ]; then
        mkdir -p $this_dump_out_dir
        # put the archives in ${param_bnf_dir}/.
        czpScripts/nnet2/dump_bottleneck_features.chenzp.sh --nj $train_nj --cmd "$train_cmd" \
          --feat-type $feat_type --name-prefix $this_langid \
          $this_lroot/data/train $this_dump_out_dir \
          $dir $param_bnf_dir $exp_dir/${this_langid}_dump_bnf
        touch $this_dump_out_dir/.done
      fi
    done
    train_data_dir=$data_bnf_dir/${langid}_train_concat
    if [ ! -f $train_data_dir/.done ]; then
      bnf_dir_list=
      for k in `seq 0 $[l-1]`; do
        bnf_dir_list="$bnf_dir_list ${data_bnf_dir_root}${dir_suffix[$k]}/${langid}_train_bnf"
      done
      steps/append_feats.sh --cmd "$train_cmd" --nj $train_nj \
        $bnf_dir_list $lroot/data/train \
        $train_data_dir $exp_dir/${langid}_append_feats/log $param_bnf_dir
      steps/compute_cmvn_stats.sh --fake $train_data_dir $exp_dir/${langid}_compute_cmvn_stats $param_bnf_dir
      touch $train_data_dir/.done
    fi
  fi

  # Begin new NN training
  exp_dir=${exp_dir_root}${dir_suffix[$l]}
  data_bnf_dir=${data_bnf_dir_root}${dir_suffix[$l]}
  param_bnf_dir=${param_bnf_dir_root}${dir_suffix[$l]}
  for d in $exp_dir $data_bnf_dir $param_bnf_dir; do
    if [ ! -d $d ]; then
      remote_d=~/kaldi_exp_${server}/$(basename `pwd`)/$d
      mkdir -p $remote_d
      ln -s $remote_d
    fi
  done
  echo $langs_so_far > $data_bnf_dir/langs
  echo $feat_type > $data_bnf_dir/feat_type
  echo $splice_width > $data_bnf_dir/splice_width
  dir=$exp_dir/tri6_bnf  # Working directory

  if $do_lda; then
    # Get LDA for $langid
    if [ ! -f $lda_dir/.done ]; then
      echo "$langid: calling get_lda.sh, saving in $lda_dir"
      steps/nnet2/get_lda.sh "${get_lda_extra_opts[@]}" --cmd "$train_cmd" $lroot/data/train $lroot/data/lang $alidir $lda_dir || exit 1;
      touch $lda_dir/.done
    fi
    lda_opts=" --lda-mat $lda_dir/lda.mat "
  else
    lda_opts=
  fi

  # Get single lang egs
  if [ ! -f $egs_dir/.done ]; then
    if [ ! -f $alidir/.done ]; then
      echo "$alidir is not ready"
      exit 1;
    fi
    echo "$langid: calling get_egs.sh"
    czpScripts/nnet2/get_egs.get_feat_dim.sh "${get_lda_extra_opts[@]}" \
      --transform-dir $alidir --samples-per-iter $samples_per_iter \
      --num-jobs-nnet $bnf_num_jobs --stage $get_egs_stage \
      --cmd "$train_cmd" --io-opts "$io_opts" \
      $lroot/data/train $lroot/data/lang $alidir $egs_dir || exit 1;
    #steps/nnet2/get_egs2.sh "${get_lda_extra_opts[@]}" --transform-dir $alidir \
    #    --stage $get_egs_stage --cmd "$train_cmd" --io-opts "$io_opts" \
    #    $lroot/data/train $alidir $egs_dir || exit 1;
    touch $egs_dir/.done
  fi

  if [[ $langid =~ VLLP ]]; then
    this_mixup=3000
    this_num_hidden_layers=4
  elif [[ $langid =~ LLP ]]; then
    this_mixup=5000
    this_num_hidden_layers=5
  else # fullLP
    this_mixup=10000
    this_num_hidden_layers=6
  fi

  if [ ! -f $dir/.done ]; then
    mkdir -p $dir
    czpScripts/nnet2/train_bottleneck.for1by1.sh \
      --unit-type "$unit_type" \
      --feat-type $feat_type --splice-width $splice_width \
      $lda_opts --unilingual-egs-dir $egs_dir $bnf_dim_opts \
      --stage $train_stage --num-jobs-nnet $bnf_num_jobs \
      --num-threads $bnf_num_threads --mix-up $this_mixup \
      --minibatch-size $bnf_minibatch_size \
      --initial-learning-rate $bnf_init_learning_rate \
      --final-learning-rate $bnf_final_learning_rate \
      --num-hidden-layers $this_num_hidden_layers \
      --bottleneck-dim $bottleneck_dim --hidden-layer-dim $bnf_hidden_layer_dim \
      --cmd "$train_cmd" \
      "${dnn_gpu_parallel_opts[@]}" \
      $train_data_dir $lroot/data/lang $alidir $dir|| exit 1
    touch $dir/.done
  fi
  train_stage=-100
done

echo "Done"

