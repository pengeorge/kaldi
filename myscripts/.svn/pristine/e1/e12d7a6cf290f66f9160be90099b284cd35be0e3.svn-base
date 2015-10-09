#!/bin/bash 
set -e
set -o pipefail

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;


dir=dev10h.pem

force_score=false # By default, eval data would not be scored due to lack of 
                  # references. If you really want to score, set it true.
                  # chenzp   Mar 2,2014
final_only=false  # only do on the final model
method=kaldi
suffix=
dev2shadow=dev10h.uem
eval2shadow=eval.uem
kind=
fast_path=false
skip_kws=false
skip_scoring=false
max_states=150000
subset_kws=true
extra_kws=true
vocab_kws=false
wip=0.5
shadow_set_extra_opts=( --wip $wip )

echo "run-4-norm-test.sh $@"

. utils/parse_options.sh

if [ $# -ne 0 ]; then
  echo "Usage: $(basename $0) --dir (dev10h|dev2h|eval|shadow)"
  exit 1
fi

if [ ! -z $suffix ]; then
  suffix_flag=_${suffix}
fi

#This seems to be the only functioning way how to ensure the comple
#set of scripts will exit when sourcing several of them together
#Otherwise, the CTRL-C just terminates the deepest sourced script ?
# Let shell functions inherit ERR trap.  Same as `set -E'.
set -o errtrace 
trap "echo Exited!; exit;" SIGINT SIGTERM

dataset_segments=${dir##*.}
dataset_dir=data/$dir
dataset_id=$dir
dataset_type=${dir%%.*}
#By default, we want the script to accept how the dataset should be handled,
#i.e. of  what kind is the dataset
if [ -z ${kind} ] ; then
  if [ "$dataset_type" == "dev2h" ] || [ "$dataset_type" == "dev10h" ] ; then
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

#The $dataset_type value will be the dataset name without any extrension
eval my_data_dir=( "\${${dataset_type}_data_dir[@]}" )
eval my_data_list=( "\${${dataset_type}_data_list[@]}" )
if [ -z $my_data_dir ] || [ -z $my_data_list ] ; then
  echo "Error: The dir you specified ($dataset_id) does not have existing config";
  exit 1
fi

eval my_stm_file=\$${dataset_type}_stm_file
eval my_ecf_file=\$${dataset_type}_ecf_file 
eval my_kwlist_file=\$${dataset_type}_kwlist_file 
eval my_rttm_file=\$${dataset_type}_rttm_file
eval my_nj=\$${dataset_type}_nj  #for shadow, this will be re-set when appropriate

my_subset_ecf=false
eval ind=\${${dataset_type}_subset_ecf+x}
if [ "$ind" == "x" ] ; then
  my_subset_ecf=\$${dataset_type}_subset_ecf
fi

declare -A my_more_kwlists
eval my_more_kwlist_keys="\${!${dataset_type}_more_kwlists[@]}"
for key in $my_more_kwlist_keys  # make sure you include the quotes there
do
  eval my_more_kwlist_val="\${${dataset_type}_more_kwlists[$key]}"
  my_more_kwlists["$key"]="${my_more_kwlist_val}"
done

#Just a minor safety precaution to prevent using incorrect settings
#The dataset_* variables should be used.
set -e
set -o pipefail
#set -u # cause unbouded variables error (chenzp Mar 1,2014)
unset dir
unset kind

if [ "$final_only" == "false" ]; then
####################################################################
##
## FMLLR 
##
####################################################################
decode=exp/tri5/decode_${dataset_id}
lmwt_extra_opts="${lmwt_plp_extra_opts[@]}"
if ! $fast_path && [ -f ${decode}/.done ]; then
#  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
#    --subset-kws $subset_kws \
#    --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
#    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt \
#    "${shadow_set_extra_opts[@]}" "${lmwt_plp_extra_opts[@]}" \
#    ${dataset_dir} data/lang ${decode}
  . czpScripts/renorm_script.sh
fi

####################################################################
## SGMM2 
## We Include the SGMM_MMI inside this, as we might only have the DNN systems
## trained and not PLP system. The DNN systems build only on the top of tri5 stage
####################################################################
if [ -f exp/sgmm5/.done ]; then
  decode=exp/sgmm5/decode_fmllr_${dataset_id}
  lmwt_extra_opts=${lmwt_plp_extra_opts[@]}
  if [ -f $decode/.done ]; then
    if ! $fast_path ; then
      . czpScripts/renorm_script.sh
    fi
  fi

  #We are done -- all lattices has been generated. We have to
  #a)Run MBR decoding
  #b)Run KW search
  for iter in 1 2 3 4; do
    # Decode SGMM+MMI (via rescoring).
    decode=exp/sgmm5_mmi_b0.1/decode_fmllr_${dataset_id}_it$iter
    lmwt_extra_opts=${lmwt_plp_extra_opts[@]}
    if [ -f ${decode}/.done ]; then
      . czpScripts/renorm_script.sh
    fi
  done
fi
####################################################################
##
## DNN ("compatibility") decoding -- also, just decode the "default" net
##
####################################################################
if [ -f exp/tri6_nnet/.done ]; then
  decode=exp/tri6_nnet/decode_${dataset_id}
  lmwt_extra_opts=${lmwt_dnn_extra_opts[@]}
  if [ -f $decode/.done ]; then
    . czpScripts/renorm_script.sh
  fi
fi


####################################################################
##
## DNN (nextgen DNN) decoding
##
####################################################################
if [ -f exp/tri6a_nnet/.done ]; then
  decode=exp/tri6a_nnet/decode_${dataset_id}
  lmwt_extra_opts=${lmwt_dnn_extra_opts[@]}
  if [ -f $decode/.done ]; then
    . czpScripts/renorm_script.sh
  fi
fi


####################################################################
##
## DNN (ensemble) decoding
##
####################################################################
if [ -f exp/tri6b_nnet/.done ]; then
  decode=exp/tri6b_nnet/decode_${dataset_id}
  lmwt_extra_opts=${lmwt_dnn_extra_opts[@]}
  if [ -f $decode/.done ]; then
    . czpScripts/renorm_script.sh
  fi
fi

####################################################################
##
## DNN semi-supervised training decoding
##
####################################################################
for dnn in tri6_nnet_semi_supervised tri6_nnet_semi_supervised2 \
          tri6_nnet_supervised_tuning tri6_nnet_supervised_tuning2 ; do
  if [ -f exp/$dnn/.done ]; then
    decode=exp/$dnn/decode_${dataset_id}
    lmwt_extra_opts=${lmwt_dnn_extra_opts[@]}
    if [ -f $decode/.done ]; then
      . czpScripts/renorm_script.sh
    fi
  fi
done
fi # fi of ! $final_only

####################################################################
##
## DNN_MPE decoding
##
####################################################################
if [ -f exp/tri6_nnet_mpe/.done ]; then
  for epoch in 1 2 3 4; do
    if $final_only && [ $epoch -ne 4 ]; then
      continue
    fi
    decode=exp/tri6_nnet_mpe/decode_${dataset_id}_epoch$epoch
    lmwt_extra_opts=${lmwt_dnn_extra_opts[@]}
    if [ -f $decode/.done ]; then
      . czpScripts/renorm_script.sh
    fi
  done
fi

echo "Everything looking good...." 
exit 0
