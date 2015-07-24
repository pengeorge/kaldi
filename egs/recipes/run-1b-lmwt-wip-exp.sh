#!/bin/bash

# This is not necessarily the top-level run.sh as it is in other directories.   see README.txt first.

set -e
set -o pipefail

[ ! -f ./lang.conf ] && echo 'Language configuration does not exist! Use the configurations in conf/lang/* as a startup' && exit 1
[ ! -f ./conf/common_vars.sh ] && echo 'the file conf/common_vars.sh does not exist!' && exit 1

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;

[ -f local.conf ] && . ./local.conf

dir=dev10h.pem
min_lmwt=13
max_lmwt=17
base_lmwt=

force_score=true # By default, eval data would not be scored due to lack of 
                  # references. If you really want to score, set it true.
                  # chenzp   Mar 2,2014

dev2shadow=dev10h.uem
eval2shadow=eval.uem
kind=
data_only=false
final_only=false
fast_path=true
skip_kws=false
skip_stt=false
skip_scoring=false
max_states=150000
subset_kws=false
extra_kws=false
vocab_kws=false
ive_kws=false   # whether to do IV expansion


### End of IV exp configuration

wip=0.5

echo "run-1b-lmwt-wip-exp.sh $@"

. utils/parse_options.sh

if [ $# -ne 0 ]; then
  echo "Usage: $(basename $0) --type (dev10h|dev2h|eval|shadow)"
  exit 1
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

# Has been moved (chenzp Mar 4,2014)
#if [ "$dataset_kind" == "unsupervised" ]; then
#  skip_scoring=true
#fi

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

                 #return non-zero return code
#set -u           #Fail on an undefined variable


decode=exp/tri5/decode_${dataset_id}
#false &&
 {
# Test other LMWT
echo "Testing LMWT from $min_lmwt to $max_lmwt"
if [ -z $base_lmwt ]; then
  decode_lmwt=${decode}_lmwt${min_lmwt}-${max_lmwt}
  mkdir -p $decode_lmwt
  pushd ${decode_lmwt} >/dev/null
  for lat in ../`basename $decode`/{lat.*.gz,num_jobs}; do
    ln -sf $lat
  done
  popd >/dev/null
else
  decode_lmwt=${decode}_${base_lmwt}base_lmwt${min_lmwt}-${max_lmwt}
  if [ ! -f ${decode_lmwt}/.done ]; then
    acwt=`perl -e "print 1/$base_lmwt;"`
    steps/decode_fmllr_extra.sh --skip-scoring true --beam 10 --lattice-beam 4\
      --acwt $acwt \
      --nj $my_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
      exp/tri5/graph ${dataset_dir} ${decode_lmwt} |tee ${decode_lmwt}/decode.log
    touch ${decode_lmwt}/.done
  fi
fi

czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
  --subset-kws $subset_kws --ive-kws $ive_kws \
  --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
  --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt \
  "${shadow_set_extra_opts[@]}" --min-lmwt $min_lmwt --max-lmwt $max_lmwt \
  ${dataset_dir} data/lang ${decode_lmwt}

exit 0;
}

# Test lower Word Insertion Penalty
echo "Testing other wip"
for wip in 0; do # 0.1 0.3
  decode_wip=${decode}_wip$wip
  echo $decode_wip
  mkdir -p $decode_wip
  pushd ${decode_wip} >/dev/null
  for lat in ../`basename ${decode}`/{lat.*.gz,num_jobs}; do
    ln -sf $lat
  done
  popd >/dev/null
  czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
    --subset-kws $subset_kws --ive-kws $ive_kws \
    --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt \
    "${lmwt_plp_extra_opts[@]}" \
    ${dataset_dir} data/lang ${decode_wip}
done

exit 0
