#!/bin/bash
set -e
set -o pipefail

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;


dir=tun3h.pem

force_score=false # By default, eval data would not be scored due to lack of 
                  # references. If you really want to score, set it true.
                  # chenzp   Mar 2,2014

dev2shadow=dev10h.uem
eval2shadow=eval.uem
kind=

data_only=false
tri5_only=false
final_only=false
fast_path=true
multilang_test=false # This is for exploring effective multilingual training
cnn_test=false # This is for exploring effective CNN training
lstm_test=false

skip_kws=false
skip_stt=false
skip_scoring=false

subset_kws=false
basic_kws=true
extra_kws=true
oov_kws=true
vocab_kws=false
ive_kws=false   # whether to do IV expansion

self_prior=true
lm_in_expansion=false
use_total_weight=$use_total_weight  # this will override lang.conf

model4cm=tri6_nnet # the model we use for confusion matrix training. MUST have _ali and _denlats generated
                # e.g. sgmm5 /  tri6_nnet

### This parameters is used for IV expansion experiment
nbest_set="1000"
lambda_set="0.5"
#lambda_set="0.0 0.2 0.4 0.5 0.6 0.8 1.0"
### End of IV exp configuration

max_states=150000
wip=0.5
shadow_set_extra_opts=( --wip $wip )

echo "run-4-test.sh $@"

. utils/parse_options.sh

if [ $# -ne 0 ]; then
  echo "Usage: $(basename $0) --type (dev10h|dev2h|eval|shadow)"
  exit 1
fi

lockfile=.lock.decode.$dir
if [ -f $lockfile ]; then
  echo "Cannot run decoding because $lockfile exists."
  exit 1;
fi
touch $lockfile

#This seems to be the only functioning way how to ensure the comple
#set of scripts will exit when sourcing several of them together
#Otherwise, the CTRL-C just terminates the deepest sourced script ?
# Let shell functions inherit ERR trap.  Same as `set -E'.
set -o errtrace 
trap "echo Exited!; exit;" SIGINT SIGTERM

dataset_segments=${dir##*.}
dataset_dir=data/$dir
dataset_fb_dir=data-fbank/$dir
dataset_id=$dir
dataset_type=${dir%%.*}
#By default, we want the script to accept how the dataset should be handled,
#i.e. of  what kind is the dataset
if [ -z ${kind} ] ; then
  if [ "$dataset_type" == "dev2h" ] || [ "$dataset_type" == "dev10h" ] || [ "$dataset_type" == "tun3h" ]; then
    dataset_kind=supervised
  elif [ "$dataset_type" == "shadow" ] ; then
    dataset_kind=shadow
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

# Has been moved (chenzp Mar 4,2014)
#if [ "$dataset_kind" == "unsupervised" ]; then
#  skip_scoring=true
#fi

#The $dataset_type value will be the dataset name without any extrension
eval my_data_dir=( "\${${dataset_type}_data_dir[@]}" )
eval my_data_list=( "\${${dataset_type}_data_list[@]}" )
eval my_ecf_file=\$${dataset_type}_ecf_file 
if [ -z $my_data_dir ]; then
  eval my_data_audio_dir=( "\${${dataset_type}_data_audio_dir[@]}" )
  # Multiple audio directories
  if [[ $my_data_audio_dir =~ : ]]; then
    first=true
    for d in `echo $my_data_audio_dir | sed 's/:/ /g'`; do
      if $first; then
        target_dir=$d
        first=false
      else
        cp -sn $d/* $target_dir/
      fi
    done
    my_data_audio_dir=$target_dir
  fi
  eval my_data_trans_dir=( "\${${dataset_type}_data_trans_dir[@]}" )
  if [ -z $my_data_trans_dir ]; then # for eval/unsup
    my_data_dir=`dirname $my_ecf_file`
  else
    my_data_dir=`dirname $my_data_trans_dir`
  fi
fi
if [ -z $my_data_list ]; then
  if [ -f $my_data_dir/${dataset_type}.list ]; then
    my_data_list=$my_data_dir/${dataset_type}.list
  elif [ ! -z $my_ecf_file ]; then
    grep -Po '(?<=audio_filename=")[^"]*(?=")' $my_ecf_file |sort -u > $my_data_dir/${dataset_type}.list
    my_data_list=$my_data_dir/${dataset_type}.list
  fi
fi
if [ -z $my_data_dir ] || [ -z $my_data_list ] ; then
  echo "Error: The dir you specified ($dataset_id) does not have existing config";
  exit 1
fi

eval my_stm_file=\$${dataset_type}_stm_file
eval my_kwlist_file=\$${dataset_type}_kwlist_file 
eval my_rttm_file=\$${dataset_type}_rttm_file
eval my_nj=\$${dataset_type}_nj  #for shadow, this will be re-set when appropriate

my_subset_ecf=false
eval ind=\${${dataset_type}_subset_ecf+x}
if [ "$ind" == "x" ] ; then
  eval my_subset_ecf=\$${dataset_type}_subset_ecf
fi

declare -A my_more_kwlists
eval my_more_kwlist_keys="\${!${dataset_type}_more_kwlists[@]}"
for key in $my_more_kwlist_keys  # make sure you include the quotes there
do
  eval my_more_kwlist_val="\${${dataset_type}_more_kwlists[$key]}"
  my_more_kwlists["$key"]="${my_more_kwlist_val}"
done

declare -A my_subset_kwlists
eval my_subset_kwlist_keys="\${!${dataset_type}_subset_kwlists[@]}"
for key in $my_subset_kwlist_keys  # make sure you include the quotes there
do
  eval my_subset_kwlist_val="\${${dataset_type}_subset_kwlists[$key]}"
  my_subset_kwlists["$key"]="${my_subset_kwlist_val}"
done

#Just a minor safety precaution to prevent using incorrect settings
#The dataset_* variables should be used.
set -e
set -o pipefail
#set -u # cause unbouded variables error (chenzp Mar 1,2014)
unset dir
unset kind

function make_plp {
  target=$1
  logdir=$2
  output=$3
  if $use_pitch; then
    steps/make_plp_pitch.sh --cmd "$decode_cmd" --nj $my_nj $target $logdir $output
  else
    steps/make_plp.sh --cmd "$decode_cmd" --nj $my_nj $target $logdir $output
  fi
  utils/fix_data_dir.sh $target
  steps/compute_cmvn_stats.sh $target $logdir $output
  utils/fix_data_dir.sh $target
}

function check_variables_are_set {
  for variable in $mandatory_variables ; do
    eval my_variable=\$${variable}
    if [ -z $my_variable ] ; then
      echo "Mandatory variable ${variable/my/$dataset_type} is not set! " \
           "You should probably set the variable in the config file "
      exit 1
    else
      echo "$variable=$my_variable"
    fi
  done

  if [ ! -z ${optional_variables+x} ] ; then
    for variable in $optional_variables ; do
      eval my_variable=\$${variable}
      echo "$variable=$my_variable"
    done
  fi
}


if  [ "$dataset_kind" == "shadow" ] ; then
  # we expect that the ${dev2shadow} as well as ${eval2shadow} already exist
  if [ ! -f data/${dev2shadow}/.done ]; then
    echo "Error: data/${dev2shadow}/.done does not exist."
    echo "Create the directory data/${dev2shadow} first"
    echo "e.g. by calling $0 --type $dev2shadow --dataonly"
    exit 1
  fi
  if [ ! -f data/${eval2shadow}/.done ]; then
    echo "Error: data/${eval2shadow}/.done does not exist."
    echo "Create the directory data/${eval2shadow} first."
    echo "e.g. by calling $0 --type $eval2shadow --dataonly"
    exit 1
  fi
  
  local/create_shadow_dataset.sh ${dataset_dir} \
    data/${dev2shadow} data/${eval2shadow}
  utils/fix_data_dir.sh ${datadir}
  nj_max=`cat $dataset_dir/wav.scp | wc -l`
  my_nj=64
else
  if [ ! -f data/raw_${dataset_type}_data/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Subsetting the ${dataset_type} set"
    echo ---------------------------------------------------------------------
   
    l1=${#my_data_dir[*]}
    l2=${#my_data_list[*]}
    if [ "$l1" -ne "$l2" ]; then
      echo "Error, the number of source files lists is not the same as the number of source dirs!"
      exit 1
    fi
    
    resource_string=""
    if [ "$dataset_kind" == "unsupervised" ]; then
      resource_string+=" --ignore-missing-txt true"
    fi

    for i in `seq 0 $(($l1 - 1))`; do
      resource_string+=" ${my_data_dir[$i]} "
      resource_string+=" ${my_data_list[$i]} "
    done
    local/make_corpus_subset.sh $resource_string ./data/raw_${dataset_type}_data
    touch data/raw_${dataset_type}_data/.done
  fi
  my_data_dir=`readlink -f ./data/raw_${dataset_type}_data`
  [ -f $my_data_dir/filelist.list ] && my_data_list=$my_data_dir/filelist.list
  nj_max=`cat $my_data_list | wc -l` || nj_max=`ls $my_data_dir/audio | wc -l`
fi
if [ "$nj_max" -lt "$my_nj" ] ; then
  echo "Number of jobs ($my_nj) is too big!"
  echo "The maximum reasonable number of jobs is $nj_max"
  my_nj=$nj_max
fi

#####################################################################
#
# Audio data directory preparation
#
#####################################################################
echo ---------------------------------------------------------------------
echo "Preparing ${dataset_kind} data files in ${dataset_dir} on" `date`
echo ---------------------------------------------------------------------
if [ ! -f  $dataset_dir/.done ] ; then
  if [ "$dataset_kind" == "supervised" ]  ; then
    if [ "$dataset_segments" == "seg" ] ; then
      . ./local/datasets/supervised_seg.sh
    elif [ "$dataset_segments" == "uem" ] ; then
      . ./local/datasets/supervised_uem.sh
    elif [ "$dataset_segments" == "pem" ] ; then
      . ./local/datasets/supervised_pem.sh
    else
      echo "Unknown type of the dataset: \"$dataset_segments\"!";
      echo "Valid dataset types are: seg, uem, pem";
      exit 1
    fi
  elif [ "$dataset_kind" == "unsupervised" ] ; then
    if [ "$dataset_segments" == "seg" ] ; then
      . ./local/datasets/unsupervised_seg.chenzp.sh 
    elif [ "$dataset_segments" == "uem" ] ; then
      . ./local/datasets/unsupervised_uem.sh
    elif [ "$dataset_segments" == "pem" ] ; then
      ##This combination does not really makes sense,
      ##Because the PEM is that we get the segmentation 
      ##and because of the format of the segment files
      ##the transcript as well
      echo "ERROR: $dataset_segments combined with $dataset_type"
      echo "does not really make any sense!"
      exit 1
      #. ./local/datasets/unsupervised_pem.sh
    else
      echo "Unknown type of the dataset: \"$dataset_segments\"!";
      echo "Valid dataset types are: seg, uem, pem";
      exit 1
    fi
  elif  [ "$dataset_kind" == "shadow" ] ; then
    #We don't actually have to do anything here
    #The shadow dir is already set...
    true  
  else
    echo "Unknown kind of the dataset: \"$dataset_kind\"!";
    echo "Valid dataset kinds are: supervised, unsupervised, shadow";
    exit 1
  fi

  if [ ! -f ${dataset_dir}/.plp.done ]; then
    echo ---------------------------------------------------------------------
    echo "Preparing ${dataset_kind} parametrization files in ${dataset_dir} on" `date`
    echo ---------------------------------------------------------------------
    make_plp ${dataset_dir} exp/make_plp/${dataset_id} plp
    touch ${dataset_dir}/.plp.done
  fi
  touch $dataset_dir/.done 
fi
if [ "$dataset_kind" == "unsupervised" ]; then
  if ! $force_score; then
    skip_scoring=true
  else
    echo ---------------------------------------------------------------------
    echo "Preparing ${dir} stm files in ${dataset_dir} on" `date`
    echo ---------------------------------------------------------------------
    if [ ! -z $my_stm_file ] ; then
      local/augment_original_stm.pl $my_stm_file ${dataset_dir}
    elif [[ $dataset_kind == shadow || $dataset_kind == eval ]]; then
      echo "Not doing anything for the STM file!"
    else
      local/prepare_stm.pl --fragmentMarkers \-\*\~ ${dataset_dir}
    fi
  fi
fi
#####################################################################
#
# KWS data directory preparation
#
#####################################################################
echo ---------------------------------------------------------------------
echo "Preparing kws data files in ${dataset_dir} on" `date`
echo ---------------------------------------------------------------------
if ! $skip_kws ; then
  lang_dir=data/lang
  . ./local/datasets/basic_kws.chenzp.sh
  if  $extra_kws ; then 
    . ./local/datasets/extra_kws.chenzp.sh
  fi
  if  $vocab_kws ; then 
    . ./local/datasets/vocab_kws.chenzp.sh
  fi
  if  $ive_kws ; then 
   #  . ./local/datasets/ive_kws.chenzp.sh
   # . ./local/datasets/ive2_kws.chenzp.sh
   # . ./local/datasets/ive3_kws.chenzp.sh
     for nbest in `echo "$nbest_set" | sed 's: \+:\n:g'`; do
       for lambda in `echo "$lambda_set" | sed 's: \+:\n:g'`; do
        . ./local/datasets/ive4_kws.chenzp.sh
       done
     done
  fi
  if [ ${#my_subset_kwlists[@]} -ne 0  ] ; then
    touch $dataset_dir/subset_kws_tasks
    mkdir -p $dataset_dir/subsets
    for subsetid in "${!my_subset_kwlists[@]}" ; do
      [ -f $dataset_dir/.done.kws.subset.$subsetid ] && continue;
      kwlist=${my_subset_kwlists[$subsetid]}
      echo $subsetid >> $dataset_dir/subset_kws_tasks
      cp $kwlist $dataset_dir/subsets/$subsetid.xml
      touch $dataset_dir/.done.kws.subset.$subsetid
    done
  fi
fi

if $data_only ; then
  echo "Exiting, as data-only was requested..."
  [ -e $lockfile ] && rm $lockfile
  exit 0;
fi


####################################################################
##
## FMLLR decoding 
##
####################################################################
decode=exp/tri5/decode_${dataset_id}
if [ ! -f ${decode}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning decoding with SAT models  on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang exp/tri5 exp/tri5/graph |tee exp/tri5/mkgraph.log

  mkdir -p $decode
  #By default, we do not care about the lattices for this step -- we just want the transforms
  #Therefore, we will reduce the beam sizes, to reduce the decoding times
  steps/decode_fmllr_extra.sh --skip-scoring true --beam 10 --lattice-beam 4 \
    --nj $my_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
    exp/tri5/graph ${dataset_dir} ${decode} |tee ${decode}/decode.log
  touch ${decode}/.done
fi

if ! $fast_path; then
  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
    --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
    --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt \
    "${shadow_set_extra_opts[@]}" "${lmwt_sat_extra_opts[@]}" \
    ${dataset_dir} data/lang ${decode}

  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
    --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
    --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
    "${shadow_set_extra_opts[@]}" "${lmwt_sat_extra_opts[@]}" \
    ${dataset_dir} data/lang ${decode}.si
fi
if $tri5_only; then
  echo "Exit because of tri5_only=true"
  [ -e $lockfile ] && rm $lockfile
  exit 0;
fi

if ! $final_only; then

####################################################################
## SGMM2 decoding 
## We Include the SGMM_MMI inside this, as we might only have the DNN systems
## trained and not PLP system. The DNN systems build only on the top of tri5 stage
####################################################################
if [ -f exp/sgmm5/.done ]; then
  decode=exp/sgmm5/decode_fmllr_${dataset_id}
  if [ ! -f $decode/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Spawning $decode on" `date`
    echo ---------------------------------------------------------------------
    utils/mkgraph.sh \
      data/lang exp/sgmm5 exp/sgmm5/graph |tee exp/sgmm5/mkgraph.log

    mkdir -p $decode
    steps/decode_sgmm2.sh --skip-scoring true --use-fmllr true --nj $my_nj \
      --cmd "$decode_cmd" --transform-dir exp/tri5/decode_${dataset_id} "${decode_extra_opts[@]}"\
      exp/sgmm5/graph ${dataset_dir} $decode |tee $decode/decode.log
    touch $decode/.done
  fi

  if ! $fast_path; then
    czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
      --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
      --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
      --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
      "${shadow_set_extra_opts[@]}" "${lmwt_sgmm_extra_opts[@]}" \
      ${dataset_dir} data/lang  $decode
  fi

  ####################################################################
  ##
  ## SGMM_MMI rescoring
  ##
  ####################################################################

  for iter in ; do
      # Decode SGMM+MMI (via rescoring).
    decode=exp/sgmm5_mmi_b0.1/decode_fmllr_${dataset_id}_it$iter
    if [ ! -f $decode/.done ]; then

      mkdir -p $decode
      steps/decode_sgmm2_rescore.sh  --skip-scoring true \
        --cmd "$decode_cmd" --iter $iter --transform-dir exp/tri5/decode_${dataset_id} \
        data/lang ${dataset_dir} exp/sgmm5/decode_fmllr_${dataset_id} $decode | tee ${decode}/decode.log

      touch $decode/.done
    fi
  done

  #We are done -- all lattices has been generated. We have to
  #a)Run MBR decoding
  #b)Run KW search
  for iter in ; do
    # Decode SGMM+MMI (via rescoring).
    decode=exp/sgmm5_mmi_b0.1/decode_fmllr_${dataset_id}_it$iter
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
      "${shadow_set_extra_opts[@]}" "${lmwt_sgmm_extra_opts[@]}" \
      ${dataset_dir} data/lang $decode
  done
fi

####################################################################
##
## DNN ("compatibility") decoding -- also, just decode the "default" net
##
####################################################################
if [ -f exp/tri6_nnet/.done ]; then
  decode=exp/tri6_nnet/decode_${dataset_id}
  if [ ! -f $decode/.done ]; then
    mkdir -p $decode
    steps/nnet2/decode.sh \
      --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
      --beam $dnn_beam --lattice-beam $dnn_lat_beam \
      --skip-scoring true "${decode_extra_opts[@]}" \
      --transform-dir exp/tri5/decode_${dataset_id} \
      exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

    touch $decode/.done
  fi
  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
    --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
    --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
    "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
    ${dataset_dir} data/lang $decode
fi
if [ -f exp/tri6_nnet/.done ]; then
  decode=exp/tri6_nnet/decode_${dataset_id}
  if [ ! -f $decode/.done ]; then
    mkdir -p $decode
    steps/nnet2/decode.sh \
      --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
      --beam $dnn_beam --lattice-beam $dnn_lat_beam \
      --skip-scoring true "${decode_extra_opts[@]}" \
      --transform-dir exp/tri5/decode_${dataset_id} \
      exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

    touch $decode/.done
  fi
  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
    --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
    --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
    "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
    ${dataset_dir} data/lang $decode
fi

if $multilang_test; then
  ####################################################################
  ##
  ## DNN ("Multi-lang", CE) initial model decoding (LDA feature)
  ##
  ####################################################################
  suffixes=
  #suffixes=".no_2nd_lda"
  for suffix in $suffixes; do
    if [ -f exp/dnn_init${suffix}/.done ]; then
      decode=exp/dnn_init${suffix}/decode_${dataset_id}
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet2/decode.sh \
          --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
          --beam $dnn_beam --lattice-beam $dnn_lat_beam \
          --skip-scoring true "${decode_extra_opts[@]}" \
          --transform-dir exp/tri5/decode_${dataset_id} \
          exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

        touch $decode/.done
      fi
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
        "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
        ${dataset_dir} data/lang $decode
      # Decode using 20.mdl
      decode=exp/dnn_init${suffix}/iter20_decode_${dataset_id}
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet2/decode.sh \
          --minimize $minimize --cmd "$decode_cmd" --nj $my_nj --iter 20 \
          --beam $dnn_beam --lattice-beam $dnn_lat_beam \
          --skip-scoring true "${decode_extra_opts[@]}" \
          --transform-dir exp/tri5/decode_${dataset_id} \
          exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

        touch $decode/.done
      fi
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
        "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
        ${dataset_dir} data/lang $decode
    fi
  done
  ####################################################################
  ##
  ## DNN ("Multi-lang", CE) initial model decoding (RAW feature)
  ##
  ####################################################################
  suffixes=
  #suffixes=".raw.no_2nd_lda .raw"
  for suffix in $suffixes; do
    if [ -f exp/dnn_init${suffix}/.done ]; then
      decode=exp/dnn_init${suffix}/decode_${dataset_id}
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet2/decode.sh --feat-type raw \
          --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
          --beam $dnn_beam --lattice-beam $dnn_lat_beam \
          --skip-scoring true "${decode_extra_opts[@]}" \
          exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

        touch $decode/.done
      fi
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
        "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
        ${dataset_dir} data/lang $decode
      # Decode using 20.mdl
      decode=exp/dnn_init${suffix}/iter20_decode_${dataset_id}
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet2/decode.sh --feat-type raw \
          --minimize $minimize --cmd "$decode_cmd" --nj $my_nj --iter 20 \
          --beam $dnn_beam --lattice-beam $dnn_lat_beam \
          --skip-scoring true "${decode_extra_opts[@]}" \
          exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

        touch $decode/.done
      fi
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
        "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
        ${dataset_dir} data/lang $decode
    fi
  done

  ####################################################################
  ##
  ## DNN ("Multi-lang", CE) decoding (LDA feature)
  ##
  ####################################################################
  suffixes=
  #suffixes='4lang10hr.no_2nd_lda'
  for suffix in $suffixes; do
    if [ -f exp/dnn_${suffix}/.done ]; then
      decode=exp/dnn_${suffix}/0/decode_${dataset_id}
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet2/decode.sh \
          --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
          --beam $dnn_beam --lattice-beam $dnn_lat_beam \
          --skip-scoring true "${decode_extra_opts[@]}" \
          --transform-dir exp/tri5/decode_${dataset_id} \
          exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

        touch $decode/.done
      fi
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
        "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
        ${dataset_dir} data/lang $decode
    fi
  done
  ####################################################################
  ##
  ## DNN ("Multi-lang", CE) decoding (RAW feature)
  ##
  ####################################################################
  #suffixes='4lang10hr.raw.no_2nd_lda 4lang10hr.raw 4lang80hr_27ep.raw 4lang80hr_27ep.raw.no_2nd_lda'
  suffixes=
  for suffix in $suffixes; do
    if [ -f exp/dnn_${suffix}/.done ]; then
      decode=exp/dnn_${suffix}/0/decode_${dataset_id}
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet2/decode.sh --feat-type raw \
          --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
          --beam $dnn_beam --lattice-beam $dnn_lat_beam \
          --skip-scoring true "${decode_extra_opts[@]}" \
          exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

        touch $decode/.done
      fi
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
        "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
        ${dataset_dir} data/lang $decode
    fi
  done
  ####################################################################
  ##
  ## DNN ("Multi-lang", CE) final tuning (*_cont) decoding (RAW feature)
  ##
  ####################################################################
#  suffixes='scratch_5lang10hr_5hid.raw_cont_en scratch_5lang80hr_5hid_mix10k_3k.raw_cont_en scratch_4lang80hr_5hid.raw_cont_en scratch_4lang80hr_5hid.raw_cont scratch_4lang10hr.raw_cont scratch_4lang10hr_4hid.raw_cont scratch_4lang10hr_5hid.raw_cont   4lang10hr.raw.no_2nd_lda_cont2 4lang10hr.raw_cont2 4lang80hr_43ep.raw.no_2nd_lda_cont2 4lang80hr_27ep.raw_cont2 4lang80hr_43ep.raw_cont2'
  suffixes='scratch_6langFLPNN.raw_cont scratch_5lang80hr_5hid_mix10k_3k.raw_cont scratch_5lang80hr_5hid_mix10k_3k.raw_cont_semisup0.7'
  for suffix in $suffixes; do
    if [ -f exp/dnn_${suffix}/.done ]; then
      decode=exp/dnn_${suffix}/decode_${dataset_id}
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet2/decode.sh --feat-type raw \
          --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
          --beam $dnn_beam --lattice-beam $dnn_lat_beam \
          --skip-scoring true "${decode_extra_opts[@]}" \
          exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

        touch $decode/.done
      fi
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
        "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
        ${dataset_dir} data/lang $decode
    fi
  done
  ####################################################################
  ##
  ## DNN ("Multi-lang", CE) final tuning (*_cont) decoding (LDA feature)
  ##
  ####################################################################
  #suffixes='scratch_5lang10hr_5hid_mix10k_3k_cont_en 4lang10hr.no_2nd_lda_cont2 4lang10hr_cont2' 
  suffixes=
  for suffix in $suffixes; do
    if [ -f exp/dnn_${suffix}/.done ]; then
      decode=exp/dnn_${suffix}/decode_${dataset_id}
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet2/decode.sh \
          --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
          --beam $dnn_beam --lattice-beam $dnn_lat_beam \
          --skip-scoring true "${decode_extra_opts[@]}" \
          --transform-dir exp/tri5/decode_${dataset_id} \
          exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

        touch $decode/.done
      fi
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
        "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
        ${dataset_dir} data/lang $decode
    fi
  done
fi

####################################################################
##
## DNN ("Data Augmentation", CE) decoding
##
####################################################################
if [ -f exp/tri6da_nnet/.done ]; then
  decode=exp/tri6da_nnet/decode_${dataset_id}
  if [ ! -f $decode/.done ]; then
    mkdir -p $decode
    steps/nnet2/decode.sh \
      --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
      --beam $dnn_beam --lattice-beam $dnn_lat_beam \
      --skip-scoring true "${decode_extra_opts[@]}" \
      --transform-dir exp/tri5/decode_${dataset_id} \
      exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

    touch $decode/.done
  fi
  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
    --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
    --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
    "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
    ${dataset_dir} data/lang $decode
fi

####################################################################
##
## DNN (nextgen DNN) decoding
##
####################################################################
if [ -f exp/tri6a_nnet/.done ]; then
  decode=exp/tri6a_nnet/decode_${dataset_id}
  if [ ! -f $decode/.done ]; then
    mkdir -p $decode
    steps/nnet2/decode.sh \
      --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
      --beam $dnn_beam --lattice-beam $dnn_lat_beam \
      --skip-scoring true "${decode_extra_opts[@]}" \
      --transform-dir exp/tri5/decode_${dataset_id} \
      exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

    touch $decode/.done
  fi
  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
    --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
    --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
    "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
    ${dataset_dir} data/lang $decode
fi


####################################################################
##
## DNN (ensemble) decoding
##
####################################################################
if [ -f exp/tri6b_nnet/.done ]; then
  decode=exp/tri6b_nnet/decode_${dataset_id}
  if [ ! -f $decode/.done ]; then
    mkdir -p $decode
    steps/nnet2/decode.sh \
      --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
      --beam $dnn_beam --lattice-beam $dnn_lat_beam \
      --skip-scoring true "${decode_extra_opts[@]}" \
      --transform-dir exp/tri5/decode_${dataset_id} \
      exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

    touch $decode/.done
  fi

  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
    --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
    --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
    "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
    ${dataset_dir} data/lang $decode
fi

if $cnn_test; then
  # Extract filter-bank features for CNN
  if [ ! -f $dataset_fb_dir/.fbank.done ]; then
    # Dev set
    mkdir -p $dataset_fb_dir && cp $dataset_dir/* $dataset_fb_dir && rm $dataset_fb_dir/{feats,cmvn}.scp
    steps/make_fbank_pitch.sh --nj $my_nj --cmd "$train_cmd" \
       $dataset_fb_dir $dataset_fb_dir/log $dataset_fb_dir/data || exit 1;
    steps/compute_cmvn_stats.sh $dataset_fb_dir $dataset_fb_dir/log $dataset_fb_dir/data || exit 1;
    touch $dataset_fb_dir/.fbank.done
  fi
  ####################################################################
  ##
  ## CNN decoding
  ##
  ####################################################################
  mdldir=exp/cnn4c
  if [ -f $mdldir/.done ]; then
    # decoding
    decode=$mdldir/decode_${dataset_id}
    if [ ! -f $decode/.done ]; then
      mkdir -p $decode
      steps/nnet/decode.sh --nj $my_nj --cmd "$decode_cmd" --config conf/decode_cnn.config \
        --skip-scoring true "${decode_extra_opts[@]}" \
        exp/tri5/graph $dataset_fb_dir $decode | tee $decode/decode.log
      touch $decode/.done
    fi

     for nbest in `echo "$nbest_set" | sed 's: \+:\n:g'`; do
       for lambda in `echo "$lambda_set" | sed 's: \+:\n:g'`; do
         ive_type=ive-$id-${model4cm}-${nbest}-${iv_phone_cutoff}-${lambda}
         if $use_total_weight; then 
           ive_type=${ive_type}-t
         fi
         if $self_prior; then 
           ive_type=${ive_type}-sp
         fi
         if $lm_in_expansion; then
           ive_type=${ive_type}-lm
           if [ ! -z $proxy_nbest0 ] && [ $proxy_nbest0 != '-1' ]; then
             ive_type=${ive_type}-${proxy_nbest0}
           fi
         fi
          czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
            --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --ive-type "$ive_type" \
            --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
            --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
            "${shadow_set_extra_opts[@]}" "${lmwt_cnn_extra_opts[@]}" \
            ${dataset_dir} data/lang $decode
       done
     done
  fi

  ####################################################################
  ##
  ## CNN RBM-DNN decoding
  ##
  ####################################################################
  mdldir=exp/cnn4c_pretrain-dbn_dnn
  if [ -f $mdldir/.done ]; then
    decode=$mdldir/decode_${dataset_id}
    if [ ! -f $decode/.done ]; then
      mkdir -p $decode
      steps/nnet/decode.sh --nj $my_nj --cmd "$decode_cmd" --config conf/decode_cnn.config \
        --skip-scoring true "${decode_extra_opts[@]}" \
        exp/tri5/graph $dataset_fb_dir $decode | tee $decode/decode.log
      touch $decode/.done
    fi

     for nbest in `echo "$nbest_set" | sed 's: \+:\n:g'`; do
       for lambda in `echo "$lambda_set" | sed 's: \+:\n:g'`; do
         ive_type=ive-$id-${model4cm}-${nbest}-${iv_phone_cutoff}-${lambda}
         if $use_total_weight; then 
           ive_type=${ive_type}-t
         fi
         if $self_prior; then 
           ive_type=${ive_type}-sp
         fi
         if $lm_in_expansion; then
           ive_type=${ive_type}-lm
           if [ ! -z $proxy_nbest0 ] && [ $proxy_nbest0 != '-1' ]; then
             ive_type=${ive_type}-${proxy_nbest0}
           fi
         fi
          czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
            --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --ive-type "$ive_type" \
            --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
            --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
            "${shadow_set_extra_opts[@]}" "${lmwt_cnn_extra_opts[@]}" \
            ${dataset_dir} data/lang $decode
       done
     done
  fi
fi
####################################################################
##
## LSTM decoding
##
####################################################################
if $lstm_test; then
  for d in lstm4f; do
    mdldir=exp/$d
    if [ -f $mdldir/.done ]; then
      # Extract filter-bank features for LSTM
      if [ ! -f $dataset_fb_dir/.fbank.done ]; then
        # Dev set
        utils/copy_data_dir.sh $dataset_dir $dataset_fb_dir || exit 1; rm $dataset_fb_dir/{cmvn,feats}.scp
        steps/make_fbank_pitch.sh --nj $my_nj --cmd "$train_cmd" \
           $dataset_fb_dir $dataset_fb_dir/log $dataset_fb_dir/data || exit 1;
        steps/compute_cmvn_stats.sh $dataset_fb_dir $dataset_fb_dir/log $dataset_fb_dir/data || exit 1;
        touch $dataset_fb_dir/.fbank.done
      fi
      # decoding
      decode=$mdldir/decode_${dataset_id}
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet/decode.sh --nj $my_nj --cmd "$decode_cmd" --config conf/decode_lstm.config \
          --skip-scoring true "${decode_extra_opts[@]}" \
          exp/tri5/graph $dataset_fb_dir $decode | tee $decode/decode.log
        touch $decode/.done
      fi

       for nbest in `echo "$nbest_set" | sed 's: \+:\n:g'`; do
         for lambda in `echo "$lambda_set" | sed 's: \+:\n:g'`; do
           ive_type=ive-$id-${model4cm}-${nbest}-${iv_phone_cutoff}-${lambda}
           if $use_total_weight; then 
             ive_type=${ive_type}-t
           fi
           if $self_prior; then 
             ive_type=${ive_type}-sp
           fi
           if $lm_in_expansion; then
             ive_type=${ive_type}-lm
             if [ ! -z $proxy_nbest0 ] && [ $proxy_nbest0 != '-1' ]; then
               ive_type=${ive_type}-${proxy_nbest0}
             fi
           fi
            czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
              --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --ive-type "$ive_type" \
              --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
              --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
              "${shadow_set_extra_opts[@]}" "${lmwt_cnn_extra_opts[@]}" \
              ${dataset_dir} data/lang $decode
         done
       done
    fi
  done
fi

fi   # end of if (!final_only)

####################################################################
##
## DNN_MPE decoding
##
####################################################################
if [ -f exp/tri6_nnet_mpe/.done ]; then
  for epoch in 1 2 3 4; do
# TODO warning! after choosing a best epoch, we should modify the following condition
    if [ $epoch -ne 1 ]; then
      continue
    fi
    decode=exp/tri6_nnet_mpe/decode_${dataset_id}_epoch$epoch
    if [ ! -f $decode/.done ]; then
      mkdir -p $decode
      steps/nnet2/decode.sh --minimize $minimize \
        --cmd "$decode_cmd" --nj $my_nj --iter epoch$epoch \
        --beam $dnn_beam --lattice-beam $dnn_lat_beam \
        --skip-scoring true "${decode_extra_opts[@]}" \
        --transform-dir exp/tri5/decode_${dataset_id} \
        exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

      touch $decode/.done
    fi

    czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
      --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
      --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
      --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
      "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
      ${dataset_dir} data/lang $decode
    if $ive_kws; then
     for nbest in `echo "$nbest_set" | sed 's: \+:\n:g'`; do
       for lambda in `echo "$lambda_set" | sed 's: \+:\n:g'`; do
         ive_type=ive-$id-${model4cm}-${nbest}-${iv_phone_cutoff}-${lambda}
         if $use_total_weight; then 
           ive_type=${ive_type}-t
         fi
         if $self_prior; then 
           ive_type=${ive_type}-sp
         fi
         if $lm_in_expansion; then
           ive_type=${ive_type}-lm
           if [ ! -z $proxy_nbest0 ] && [ $proxy_nbest0 != '-1' ]; then
             ive_type=${ive_type}-${proxy_nbest0}
           fi
         fi
          czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
            --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --ive-type "$ive_type" \
            --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
            --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
            "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
            ${dataset_dir} data/lang $decode
       done
     done
    fi
  done
fi

if $cnn_test; then
  ####################################################################
  ##
  ## CNN_MPE decoding
  ##
  ####################################################################
  mdldir=exp/cnn4c_pretrain-dbn_dnn_smbr
  if [ -f $mdldir/.done ]; then
    for iter in 2; do
  # TODO warning! after choosing a best epoch, we should modify the following condition
      if $final_only && [ $iter -ne 2 ]; then
        continue
      fi
      decode=$mdldir/decode_${dataset_id}_it$iter
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet/decode.sh --nj $my_nj --cmd "$decode_cmd" --config conf/decode_cnn.config \
          --nnet $mdldir/${iter}.nnet \
          --skip-scoring true "${decode_extra_opts[@]}" \
          exp/tri5/graph $dataset_fb_dir $decode | tee $decode/decode.log
        # Note: in CNN recipe, "--acwt 0.2", here we use default 0.1 and see what happened. (chenzp, Jan 23,2015)
        touch $decode/.done
      fi

       for nbest in `echo "$nbest_set" | sed 's: \+:\n:g'`; do
         for lambda in `echo "$lambda_set" | sed 's: \+:\n:g'`; do
           ive_type=ive-$id-${model4cm}-${nbest}-${iv_phone_cutoff}-${lambda}
           if $use_total_weight; then 
             ive_type=${ive_type}-t
           fi
           if $self_prior; then 
             ive_type=${ive_type}-sp
           fi
           if $lm_in_expansion; then
             ive_type=${ive_type}-lm
             if [ ! -z $proxy_nbest0 ] && [ $proxy_nbest0 != '-1' ]; then
               ive_type=${ive_type}-${proxy_nbest0}
             fi
           fi
            czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
              --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --ive-type "$ive_type" \
              --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
              --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
              "${shadow_set_extra_opts[@]}" "${lmwt_cnn_extra_opts[@]}" \
              ${dataset_dir} data/lang $decode
         done
       done
    done
  fi
fi

if ! $final_only; then
####################################################################
##
## DNN semi-supervised training decoding
##
####################################################################
for dnn in tri6_nnet_semi_supervised tri6_nnet_semi_supervised2 \
          tri6_nnet_supervised_tuning tri6_nnet_supervised_tuning2 ; do
  if [ -f exp/$dnn/.done ]; then
    decode=exp/$dnn/decode_${dataset_id}
    if [ ! -f $decode/.done ]; then
      mkdir -p $decode
      steps/nnet2/decode.sh \
        --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
        --beam $dnn_beam --lattice-beam $dnn_lat_beam \
        --skip-scoring true "${decode_extra_opts[@]}" \
        --transform-dir exp/tri5/decode_${dataset_id} \
        exp/tri5/graph ${dataset_dir} $decode | tee $decode/decode.log

      touch $decode/.done
    fi
    czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
      --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws \
      --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
      --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt  \
      "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
      ${dataset_dir} data/lang $decode
  fi
done
fi

[ -f $lockfile ] && rm $lockfile
echo "Everything looking good...." 
exit 0
