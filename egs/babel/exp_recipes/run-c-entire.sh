#!/bin/bash

set -e           #Exit on non-zero return code from any command
set -u           #Fail on an undefined variable

# Options for run-2c (concat)
server=x33   # the host where exp, data and param are stored.
dirid=train
transform_dir=  # if empty, will automatically set as exp/tri5_ali ($dirid==train) or exp/tri5/decode_${dirid} ($dirid != train)

exp_dir=exp_bnf_anymodel
exp_concat_dir=exp_concat_4lang10hr.raw_3hid

append_fmllr=true
fmllr_splice_width=0 # useful only when append_fmllr=true
bnf_input_feat_type=

bnf_nnet_list=

#Options for run-3c (train)
splice_width=0
do_lda=true  # LDA in NN
feat_mix= # vector_mix/scalar_mix
feat_mix_block_dim=42
feat_mix_const_dim=40
feat_mix_num_blocks=4 

#Options for run-4c (decode)
decodedir=dev10h.pem


echo "$0 $@"

. ./utils/parse_options.sh

# Some options which may not be an option
feat_type=raw  # for run-3c (train)
# End

if [ "$feat_mix" == full_conn ]; then
  echo "full_conn is to transform concated feats to block_dim first and then transform again to next layer. This performance is bad. Don't run !"
  exit 1;
fi

# Concat feats
./run-2c-concate-bnf-feats.sh --server "$server" --dirid "$dirid" --transform-dir "$transform_dir" \
  --exp-dir "$exp_dir" --exp-concat-dir "$exp_concat_dir" \
  --append-fmllr $append_fmllr --fmllr-splice-width  $fmllr_splice_width \
  --bnf-input-feat-type "$bnf_input_feat_type" --bnf-nnet-list "$bnf_nnet_list"

# Generate actual exp_concat_dir, as is done in run-2c, 
# which has also been done in run-4c-decode, so we save it in expsuffix for run-4c
expsuffix=`echo $exp_concat_dir | sed 's/^exp_//'`
if $append_fmllr; then
  exp_concat_dir=${exp_concat_dir}_fmllr
  if [ $fmllr_splice_width -gt 0 ]; then
    exp_concat_dir=${exp_concat_dir}X$[2*$fmllr_splice_width+1]
  fi
fi

# Train nnet
./run-3c-nnet-on-comb-feats.sh --exp-dir "$exp_concat_dir/tri7_nnet" \
  --splice-width "$splice_width" --feat-type "$feat_type" \
  --do-lda $do_lda --feat-mix "$feat_mix" --feat-mix-block-dim "$feat_mix_block_dim" \
  --feat-mix-const-dim "$feat_mix_const_dim" --feat-mix-num-blocks "$feat_mix_num_blocks" 

# Decode
./run-4c-anydecode-nnet-on-comb-feats.sh --expsuffix "$expsuffix" --dir "$decodedir" \
  --append-fmllr $append_fmllr --fmllr-splice-width  $fmllr_splice_width \
  --bnf-input-feat-type "$bnf_input_feat_type"

grep Sum $exp_concat_dir/tri7_nnet/decode_${decodedir}/score_*/*.sys

echo "Done. This is the result for $exp_concat_dir/tri7_nnet."
echo "For other type of tri7_nnet (suffix of tri7_nnet), modify run-4c, run, and grep it manually."

