#!/bin/bash
# Copyright 2014  Pegah Ghahremani
# Apache 2.0

# decode BNF + sgmm_mmi system 
set -e
set -o pipefail

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;


dir=tun3h.pem #dev10h.pem
mlsuffix=6langFLPNN.raw
kind=
data_only=false
fast_path=true

skip_kws=true
skip_stt=false
skip_scoring=false

subset_kws=true
extra_kws=true
oov_kws=true
vocab_kws=false
ive_kws=false   # whether to do IV expansion

tmpdir=`pwd`
suffix=
input_feats=   # input feats of BNF NN

transform_feats=false
. utils/parse_options.sh

type=$dir

if [ $# -ne 0 ]; then
  echo "Usage: $(basename $0) --type (dev10h|dev2h|eval|shadow)"
  exit 1
fi

if ! echo {dev10h,dev2h,eval,unsup,shadow,tun3h}{.pem,.uem,.seg} | grep -w "$type" >/dev/null; then
  # note: echo dev10.uem | grep -w dev10h will produce a match, but this
  # doesn't matter because dev10h is also a valid value.
  echo "Invalid variable type=${type}, valid values are " {dev10h,dev2h,eval,unsup}{,.uem,.seg}
  exit 1;
fi

dataset_segments=${dir##*.}
dataset_dir=data/$dir
dataset_id=$dir
dataset_type=${dir%%.*}
#By default, we want the script to accept how the dataset should be handled,
#i.e. of  what kind is the dataset
if [ -z ${kind} ] ; then
  if [ "$dataset_type" == "dev2h" ] || [ "$dataset_type" == "dev10h" ] || [ "$dataset_type" == "tun3h" ]; then
    dataset_kind=supervised
  else
    dataset_kind=unsupervised
  fi
else
  dataset_kind=$kind
fi

if [ -z $dataset_segments ]; then
  echo "You have to specify the segmentation type as well"
  echo "If you are trying to decode the PEM segmentation dir"
  echo "such as data/dev10h, specify dev10h.pem"
  echo "The valid segmentations types are:"
  echo "\tpem   #PEM segmentation"
  echo "\tuem   #UEM segmentation in the CMU database format"
  echo "\tseg   #UEM segmentation (kaldi-native)"
fi

if [ "$dataset_kind" == "unsupervised" ]; then
  skip_scoring=true
fi

dirid=${type}
exp_dir=exp_bnf_${mlsuffix}${suffix}
data_bnf_dir=data_bnf_${mlsuffix}${suffix}
param_bnf_dir=param_bnf_${mlsuffix}${suffix}
datadir=$data_bnf_dir/${dirid}    

lockfile=.lock.decode.${exp_dir}.$dir
if [ -f $lockfile ]; then
  echo "Cannot run decoding because $lockfile exists."
  exit 1;
fi
touch $lockfile

if [ -f $data_bnf_dir/input_feats ]; then
  recorded_input_feats=`cat $data_bnf_dir/input_feats`
  if [ -z "$input_feats" ]; then
    input_feats=$recorded_input_feats
  elif [ "$input_feats" != "$recorded_input_feats" ]; then
    echo "Input feats type does not match: $recorded_input_feats (You specify $input_feats)"
    exit 1;
  fi
fi
echo "input_feats is $input_feats"
if [ "$input_feats" == "mrasta" ]; then
  . ./czpScripts/clips/decode/anydecode_bnf_data_prep.mrasta.sh
else
  . ./czpScripts/clips/decode/anydecode_bnf_data_prep.sh
fi


if $data_only ; then
  echo "Exiting, as data-only was requested... "
fi

####################################################################
##
## FMLLR decoding 
##
####################################################################
decode=$exp_dir/tri6/decode_${dirid}
if [ ! -f ${decode}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Decoding with SAT models on top of bottleneck features on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang $exp_dir/tri6 $exp_dir/tri6/graph |tee $exp_dir/tri6/mkgraph.log

  mkdir -p $decode
  #By default, we do not care about the lattices for this step -- we just want the transforms
  #Therefore, we will reduce the beam sizes, to reduce the decoding times
  steps/decode_fmllr_extra.sh --skip-scoring true --beam 10 --lattice-beam 4 \
    --acwt $bnf_decode_acwt \
    --nj $my_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
    $exp_dir/tri6/graph ${datadir} ${decode} |tee ${decode}/decode.log
  touch ${decode}/.done
fi

if ! $fast_path ; then
  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states --skip-scoring $skip_scoring\
    --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --extra-kws $extra_kws --wip $wip\
    "${shadow_set_extra_opts[@]}" "${lmwt_bnf_extra_opts[@]}" \
    ${datadir} data/lang ${decode}

  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states --skip-scoring $skip_scoring\
    --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --extra-kws $extra_kws --wip $wip \
    "${shadow_set_extra_opts[@]}" "${lmwt_bnf_extra_opts[@]}" \
    ${datadir} data/lang  ${decode}.si
fi

####################################################################
## SGMM2 decoding 
####################################################################
decode=$exp_dir/sgmm7/decode_fmllr_${dirid}
if [ ! -f $decode/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning $decode on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang $exp_dir/sgmm7 $exp_dir/sgmm7/graph |tee $exp_dir/sgmm7/mkgraph.log

  mkdir -p $decode
  steps/decode_sgmm2.sh --skip-scoring true --use-fmllr true --nj $my_nj \
    --acwt $bnf_decode_acwt \
    --cmd "$decode_cmd" --transform-dir $exp_dir/tri6/decode_${dirid} "${decode_extra_opts[@]}"\
    $exp_dir/sgmm7/graph ${datadir} $decode |tee $decode/decode.log
  touch $decode/.done
fi

if ! $fast_path ; then
  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states --skip-scoring $skip_scoring \
    --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --extra-kws $extra_kws --wip $wip \
    "${shadow_set_extra_opts[@]}" "${lmwt_bnf_extra_opts[@]}" \
    ${datadir} data/lang  $exp_dir/sgmm7/decode_fmllr_${dirid}
fi

####################################################################
##
## SGMM_MMI rescoring
##
####################################################################

for iter in 1      ; do
  # Decode SGMM+MMI (via rescoring).
  decode=$exp_dir/sgmm7_mmi_b0.1/decode_fmllr_${dirid}_it$iter
  if [ ! -f $decode/.done ]; then

    mkdir -p $decode
    steps/decode_sgmm2_rescore.sh  --skip-scoring true \
      --cmd "$decode_cmd" --iter $iter --transform-dir $exp_dir/tri6/decode_${dirid} \
      data/lang ${datadir} $exp_dir/sgmm7/decode_fmllr_${dirid} $decode | tee ${decode}/decode.log

    touch $decode/.done
  fi
done

#We are done -- all lattices has been generated. We have to
#a)Run MBR decoding
#b)Run KW search
for iter in 1      ; do
  # Decode SGMM+MMI (via rescoring).
  decode=$exp_dir/sgmm7_mmi_b0.1/decode_fmllr_${dirid}_it$iter
  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states --skip-scoring $skip_scoring\
    --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --extra-kws $extra_kws --wip $wip \
    "${shadow_set_extra_opts[@]}" "${lmwt_bnf_extra_opts[@]}" \
    ${datadir} data/lang $decode
done


if [ -f $exp_dir/tri7_nnet/.done ]; then
#    [[ ( ! $exp_dir/tri7_nnet/decode_${dirid}/.done -nt $datadir/.done)  || \
#       (! $exp_dir/tri7_nnet/decode_${dirid}/.done -nt $exp_dir/tri7_nnet/.done ) ]]; then
  
  echo ---------------------------------------------------------------------
  echo "Decoding hybrid system on top of bottleneck features on" `date`
  echo ---------------------------------------------------------------------

  # We use the graph from tri6.
  utils/mkgraph.sh \
    data/lang $exp_dir/tri6 $exp_dir/tri6/graph |tee $exp_dir/tri6/mkgraph.log

  decode=$exp_dir/tri7_nnet/decode_${dirid}
  if [ ! -f $decode/.done ]; then
    mkdir -p $decode
    steps/nnet2/decode.sh --cmd "$decode_cmd" --nj $my_nj \
      --acwt $bnf_decode_acwt \
      --beam $dnn_beam --lattice-beam $dnn_lat_beam \
      --skip-scoring true "${decode_extra_opts[@]}" \
      --feat-type raw \
      $exp_dir/tri6/graph ${datadir} $decode | tee $decode/decode.log

    touch $decode/.done
  fi

  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states --skip-scoring $skip_scoring\
    --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --extra-kws $extra_kws --wip $wip \
    "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
    ${datadir} data/lang $decode
fi

[ -e $lockfile ] && rm $lockfile
echo "$0: Everything looking good...." 
exit 0
