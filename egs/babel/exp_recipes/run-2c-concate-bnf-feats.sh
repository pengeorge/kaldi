#!/bin/bash

set -e           #Exit on non-zero return code from any command
set -o pipefail  #Exit if any of the commands in the pipeline will
                 #return non-zero return code
. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;

set -u           #Fail on an undefined variable

server=x33   # the host where exp, data and param are stored.
dirid=train
transform_dir=  # if empty, will automatically set as exp/tri5_ali ($dirid==train) or exp/tri5/decode_${dirid} ($dirid != train)

exp_dir=exp_bnf_anymodel
exp_concat_dir=exp_concat_4lang10hr.raw_3hid

append_fmllr=false

bnf_nnet_list=

echo "$0 $@"

. ./utils/parse_options.sh

data_dir=`echo $exp_dir | sed 's/exp/data/'`
param_dir=`echo $exp_dir | sed 's/exp/param/'`

data_concat_dir=`echo $exp_concat_dir | sed 's/exp/data/'`
param_concat_dir=`echo $exp_concat_dir | sed 's/exp/param/'`

for d in $exp_dir $data_dir $param_dir $exp_concat_dir $data_concat_dir $param_concat_dir; do
  if [ ! -d $d ]; then
    remote_d=~/kaldi_exp_${server}/$(basename `pwd`)/$d
    mkdir -p $remote_d
    ln -s $remote_d
  fi
done

if [ -z "$bnf_nnet_list" ]; then
  echo "bnf_nnet_list is empty"
  exit 1;
fi

if [ -z "$transform_dir" ]; then
  if [ $dirid == train ]; then
    transform_dir=exp/tri5_ali
  else
    transform_dir=exp/tri5/decode_${dirid}
  fi
fi

if [ ! -f $data_concat_dir/bnf_nnet_list ]; then
  echo "$bnf_nnet_list" > $data_concat_dir/bnf_nnet_list
else
  if [ "`cat $data_concat_dir/bnf_nnet_list`" != "$bnf_nnet_list" ]; then
    echo "bnf_nnet_list not match"
    exit 1;
  fi
fi

# Extracting BNF for each bnf_nnet in list
data_dir_list=
for bn in $bnf_nnet_list; do
  if [ ! -f $bn/.done ]; then
    echo "BN $bn is not ready."
    exit 1;
  fi
  bnid=$(echo $bn | perl -e '$path=<>; $path =~ s:.*?([^/]+)/(exp_bnf[^/]*)/tri6_bnf.*:\1__\2:; print $path;')
  echo "Processing $bnid"
  if [ ! -f $data_dir/$bnid/${dirid}/.done ]; then
    mkdir -p $param_dir/$bnid
    czpScripts/nnet2/dump_bottleneck_features.chenzp.sh --nj $train_nj --cmd "$train_cmd" \
      data/${dirid} $data_dir/$bnid/${dirid} $bn $param_dir/$bnid $exp_dir/dump_bnf_$bnid
    echo $bn > $data_dir/$bnid/${dirid}/bnnet
    touch $data_dir/$bnid/${dirid}/.done
  fi
  data_dir_list="$data_dir_list $data_dir/$bnid/${dirid}"
done

if [ ! -f $data_concat_dir/${dirid}/.done ]; then
  if $append_fmllr; then
    if [ ! -f $data_concat_dir/${dirid}_sat/.done ]; then
      czpScripts/nnet/make_fmllr_feats.chenzp.sh --cmd "$train_cmd -tc 10" \
        --nj $train_nj --transform-dir $transform_dir $data_concat_dir/${dirid}_sat data/${dirid} \
        exp/tri5_ali $exp_concat_dir/make_fmllr_feats/log $param_concat_dir  
      touch $data_concat_dir/${dirid}_sat/.done
    fi
    data_dir_list="$data_dir_list $data_concat_dir/${dirid}_sat"
  fi
  steps/append_feats.sh --cmd "$train_cmd" --nj $train_nj \
    $data_dir_list $data_concat_dir/${dirid} $exp_concat_dir/append_feats/log $param_concat_dir
  steps/compute_cmvn_stats.sh --fake $data_concat_dir/${dirid} $exp_concat_dir/compute_cmvn_stats $param_concat_dir
  echo $data_dir_list > $data_concat_dir/${dirid}/data_dir_list
fi

echo "Done."
