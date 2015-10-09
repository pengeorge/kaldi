#!/bin/bash
set -e
set -o pipefail
set -u

# chenzp 2014
# Force alignment on the specified dataset with the specified model.

. conf/common_vars.sh
. ./lang.conf

dataset_id=
dataset_dir=
use_gpu_in_align=yes
ext=
model=tri6_nnet

. utils/parse_options.sh

if [ -z $dataset_id ]; then
  echo "\$dataset_id must be specified"
  exit 1;
fi
dataset_segments=${dataset_id##*.}
dataset_type=${dataset_id%%.*}
if [ -z $dataset_dir ]; then
  dataset_dir=data/$dataset_id
fi
if [ ! -f $dataset_dir/.done ]; then
  echo "\$dataset_dir $dataset_dir is not well prepared. Run run-4-anydecode.sh --data-only true first."
  exit 1;
fi
if [ ! -f $dataset_dir/text ]; then
  echo "$dataset_dir/text is not found."
  exit 1;
fi
eval my_nj=\$${dataset_type}_nj

if [ ! -z $ext ]; then
  ext=_$ext
fi

transform_dir=exp/anyalign/tri5_${dataset_id}$ext
# Generate tri5 alignment, to get transform dir
if [ ! -f $transform_dir/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting $transform_dir on" `date`
  echo ---------------------------------------------------------------------
  steps/align_fmllr.sh \
    --boost-silence $boost_sil --nj $my_nj --cmd "$train_cmd" \
    $dataset_dir data/lang$ext exp/tri5 $transform_dir
  touch $transform_dir/.done
fi

# Generate alignment for the specified model.
ali_dir=exp/anyalign/${model}_${dataset_id}$ext
if [ ! -f $ali_dir/.done ]; then
  if [ $use_gpu_in_align == no ]; then
    dnn_parallel_opts=  # remove "-l gpu=1"
  fi
  echo ---------------------------------------------------------------------
  echo "Starting $ali_dir on" `date`
  echo ---------------------------------------------------------------------
  steps/nnet2/align.sh --use-gpu $use_gpu_in_align \
    --cmd "$decode_cmd $dnn_parallel_opts" \
    --transform-dir $transform_dir --nj $my_nj \
    $dataset_dir data/lang$ext exp/${model} $ali_dir || exit 1
  touch $ali_dir/.done
fi

if [ ! -f $ali_dir/.done.show ]; then
  show-alignments data/lang$ext/phones.txt exp/$model/final.mdl "ark:gunzip -cdf $ali_dir/ali.*.gz |" > $ali_dir/align.show
  touch $ali_dir/.done.show
fi
echo ---------------------------------------------------------------------
echo Done. 
echo ---------------------------------------------------------------------
