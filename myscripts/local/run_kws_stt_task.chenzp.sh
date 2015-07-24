#!/bin/bash 
# Copyright 2013  Johns Hopkins University (authors: Yenda Trmal)

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

#Simple BABEL-only script to be run on generated lattices (to produce the
#files for scoring and for NIST submission

set -e
set -o pipefail
set -u

#Begin options
min_lmwt=8
max_lmwt=12
cer=0
skip_kws=false
skip_stt=false
skip_scoring=false
subset_kws=true
basic_kws=false
extra_kws=true
oov_kws=true
ive_kws=false
ive_type=
cmd=run.pl
max_states=150000
dev2shadow=
eval2shadow=
wip=0.5 #Word insertion penalty

ext_lexicon=  # If lexicon is extended, use ${data_dir}_${ext_lexicon} as data dir in KWS. (chenzp, Feb 2,2015)
ext_pron=  # extended pronunciation, does not determine IV/OOV, is only used for L2 in phone confusion
#End of options

if [ $(basename $0) == score.sh ]; then
  skip_kws=true
fi

. utils/parse_options.sh     

if [ $# -ne 3 ]; then
  echo $0 "$@"
  echo "Usage: $0 [options] <data-dir> <lang-dir> <decode-dir>"
  echo " e.g.: $0 data/dev10h data/lang exp/tri6/decode_dev10h"
  exit 1;
fi

data_dir=$1; 
lang_dir=$2;
decode_dir=$3; 

type=normal
if [ ! -z ${dev2shadow}  ] && [ ! -z ${eval2shadow} ] ; then
  type=shadow
elif [ -z ${dev2shadow}  ] && [ -z ${eval2shadow} ] ; then
  type=normal
else
  echo "Switches --dev2shadow and --eval2shadow must be used simultaneously" > /dev/stderr
  exit 1
fi

host=`readlink -f $decode_dir | grep -Po '(?<=kaldi_exp_)x\d+(?=/)'`
local_cmd=`echo $cmd | sed "s:-q \+[^ ]\+:-q ${host}.q:"`
if [ -z "$local_cmd" ]; then
  local_cmd=$cmd
fi
##NB: The first ".done" files are used for backward compatibility only
##NB: should be removed in a near future...
{
if  ! $skip_stt && [ ! -f $decode_dir/.score.done ] && [ ! -f $decode_dir/.done.score ]; then 
  if [ ! -f $decode_dir/.done.ctm ]; then
    czpScripts/local/lattice_to_ctm.chenzp.sh --cmd "$local_cmd" --word-ins-penalty $wip \
      --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} \
      $data_dir $lang_dir $decode_dir
    touch $decode_dir/.done.ctm
  fi

  if [[ "$type" == shadow* ]]; then
    local/split_ctms.sh --cmd "$cmd" --cer $cer \
      --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt}\
      $data_dir $decode_dir ${dev2shadow} ${eval2shadow}
  elif ! $skip_scoring ; then
    # chenzp: replace ' A ' with ' 1 ' in 'empty_recognized_phrase' line
    for lmwt in `seq ${min_lmwt} ${max_lmwt}`; do
      ctmfile=$decode_dir/score_${lmwt}/`basename $data_dir`.ctm
      set +o pipefail
      empty_num=`grep -i 'empty_recognized_phrase' $ctmfile | grep -v '^;;' | wc -l`
      set -o pipefail
      if [ $empty_num -gt 0 ]; then
        echo "Warning: find $empty_num empty_recognized_phrase in $ctmfile"
        sed -i.chenzpbak '/empty_recognized_phrase/Is/ A / 1 /' $ctmfile
      fi
    done
    czpScripts/local/score_stm.chenzp.sh --cmd "$cmd"  --cer $cer \
      --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt}\
      $data_dir $lang_dir $decode_dir
    touch $decode_dir/.done.score
  fi
fi
} & # run stt scoring and kws in parallel

if ! $skip_kws ; then
  if [ ! -z ${ext_lexicon} ]; then
    data_dir=${data_dir}_${ext_lexicon}
  fi
  
  set +o pipefail
  actual_min_lmwt=`ls $decode_dir | grep -Po '(?<=kws_indices_)\d+' | sort -n | head -n 1`
  actual_max_lmwt=`ls $decode_dir | grep -Po '(?<=kws_indices_)\d+' | sort -n | tail -n 1`
  set -o pipefail
  echo "$decode_dir: actual_min_lmwt=$actual_min_lmwt"
  echo "$decode_dir: actual_max_lmwt=$actual_max_lmwt"
  if [ ! -z "$actual_min_lmwt" ]; then
    if [ $actual_min_lmwt -gt $min_lmwt ]; then
      echo "LMWT not match: $actual_min_lmwt (actual min) > $min_lmwt (requested min)"
      echo "Do extra making indices"
      if [ -f $decode_dir/kws_indices/.done.index ]; then
        rm $decode_dir/kws_indices/.done.index
      fi
      czpScripts/kws/kws_make_indices.chenzp.sh --cmd "$cmd" --max-states ${max_states} \
        --min-lmwt ${min_lmwt} --max-lmwt $(($actual_min_lmwt-1)) \
        --indices-dir $decode_dir/kws_indices $lang_dir $data_dir $decode_dir
    fi
    if [ $actual_max_lmwt -lt $max_lmwt ]; then
      echo "LMWT not match: $actual_max_lmwt (actual max) < $max_lmwt (requested max)"
      echo "Do extra making indices"
      if [ -f $decode_dir/kws_indices/.done.index ]; then
        rm $decode_dir/kws_indices/.done.index
      fi
      czpScripts/kws/kws_make_indices.chenzp.sh --cmd "$cmd" --max-states ${max_states} \
        --min-lmwt $(($actual_max_lmwt+1)) --max-lmwt $max_lmwt \
        --indices-dir $decode_dir/kws_indices $lang_dir $data_dir $decode_dir
    fi
  else
    echo "==== Making indices ================================="
    czpScripts/kws/kws_make_indices.chenzp.sh --cmd "$cmd" --max-states ${max_states} \
      --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} \
      --indices-dir $decode_dir/kws_indices $lang_dir $data_dir $decode_dir
  fi


  # Basic IV KWS
  if $basic_kws && [ ! -f $decode_dir/.kws.done ] && [ ! -f $decode_dir/.done.kws ]; then 
    if [[ "$type" == shadow* ]]; then
      local/shadow_set_kws_search.sh --cmd "$cmd" --max-states ${max_states} \
        --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt}\
        $data_dir $lang_dir $decode_dir ${dev2shadow} ${eval2shadow}
    else
      echo "==== Running basic KWS =============================="
      czpScripts/kws/kws_search.chenzp.sh --cmd "$cmd" --max-states ${max_states} \
        --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} --skip-scoring $skip_scoring\
        --indices-dir $decode_dir/kws_indices $lang_dir $data_dir $decode_dir
    fi
    touch $decode_dir/.done.kws
  fi
  # Basic OOV KWS
  if $basic_kws && $oov_kws && [ -z "$ext_pron" ] && [ ! -f $decode_dir/.done.kws.oov ]; then
    {
      echo "==== Running basic OOV KWS =========================="
      czpScripts/kws/kws_search.chenzp.sh --cmd "$cmd" --extraid oov  \
        --max-states ${max_states} --min-lmwt ${min_lmwt} --skip-scoring $skip_scoring\
         --max-lmwt ${max_lmwt} --indices-dir $decode_dir/kws_indices \
        $lang_dir $data_dir $decode_dir
      touch $decode_dir/.done.kws.oov
    } &
  fi
  # Extra IV/OOV KWS
  if $extra_kws && [ -f $data_dir/extra_kws_tasks ]; then
    for extraid in `cat $data_dir/extra_kws_tasks` ; do
      ! ($oov_kws && [ -z "$ext_pron" ]) && [[ $extraid =~ oov$ ]] && continue;
      [ $extraid == oov ] && continue;
      [ -f $decode_dir/.done.kws.$extraid ] && continue;
    {
      echo "==== Running extra KWS: $extraid ===================="
      czpScripts/kws/kws_search.chenzp.sh --cmd "$cmd" --extraid $extraid  \
        --max-states ${max_states} --min-lmwt ${min_lmwt} --skip-scoring $skip_scoring\
         --max-lmwt ${max_lmwt} --indices-dir $decode_dir/kws_indices \
        $lang_dir $data_dir $decode_dir
      touch $decode_dir/.done.kws.$extraid
    } &
    done
  fi
  wait;
  set +e;
  if $subset_kws && [ -f $data_dir/subset_kws_tasks ]; then
    for subsetid in `cat $data_dir/subset_kws_tasks` ; do
      if [[ $subsetid =~ \. ]]; then
        extraid=${subsetid%%.*}
        [ ! -f $decode_dir/.done.kws.$extraid ] && continue;
      else
        ! $basic_kws && continue;
        [ ! -f $decode_dir/.done.kws ] && continue;
      fi
      [ -f $decode_dir/.done.kws.subset.$subsetid ] && continue;
    #{ # 1gram and mgram of the same extraid share a common dir 'q', should not run parallelly?
      {
      if [ ! -f $decode_dir/.done.kws.subset.${subsetid}.iv ]; then
        echo "==== Running subset KWS: $subsetid (IV) ====================="
        czpScripts/kws/kws_subset_eval.chenzp.sh --cmd "$cmd" --oov false \
          --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} \
          $subsetid $data_dir $decode_dir && touch $decode_dir/.done.kws.subset.${subsetid}.iv
      fi
      } &
      {
      if $oov_kws && [ ! -f $decode_dir/.done.kws.subset.${subsetid}.oov ]; then
        echo "==== Running subset KWS: $subsetid (OOV) ===================="
        czpScripts/kws/kws_subset_eval.chenzp.sh --cmd "$cmd" --oov true \
          --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} \
          $subsetid $data_dir $decode_dir && touch $decode_dir/.done.kws.subset.${subsetid}.oov
      fi
      } &
      wait;
      if [ -f $decode_dir/.done.kws.subset.${subsetid}.iv ] && [ -f $decode_dir/.done.kws.subset.${subsetid}.oov ]; then
        touch $decode_dir/.done.kws.subset.$subsetid
      fi
    #} &
    done
  fi
  wait
  set -e;
  if $oov_kws && [ ! -z "${ext_pron}" ]; then
      pron_suffix=ep-`basename $ext_pron`
      if $basic_kws && [ ! -f $decode_dir/.done.kws.oov_${pron_suffix} ]; then
        {
          echo "==== Running exp_pron OOV KWS: $ext_pron ======================"
          czpScripts/kws/kws_search.chenzp.sh --cmd "$cmd" --suffix ${pron_suffix} --extraid oov  \
            --max-states ${max_states} --min-lmwt ${min_lmwt} --skip-scoring $skip_scoring\
             --max-lmwt ${max_lmwt} --indices-dir $decode_dir/kws_indices \
            $lang_dir $data_dir $decode_dir
          touch $decode_dir/.done.kws.oov_${pron_suffix}
        } &
      fi
      if $extra_kws && [ -f $data_dir/extra_kws_tasks ]; then
        for extraid in `cat $data_dir/extra_kws_tasks` ; do
          [[ ! $extraid =~ oov$ ]] && continue;
          [ $extraid == oov ] && continue;
          [ -f $decode_dir/.done.kws.${extraid}_${pron_suffix} ] && continue;
        {
          echo "==== Running exp_pron extra OOV KWS: $ext_pron, $extraid ============"
          czpScripts/kws/kws_search.chenzp.sh --cmd "$cmd" --suffix ${pron_suffix} --extraid $extraid  \
            --max-states ${max_states} --min-lmwt ${min_lmwt} --skip-scoring $skip_scoring\
             --max-lmwt ${max_lmwt} --indices-dir $decode_dir/kws_indices \
            $lang_dir $data_dir $decode_dir
          touch $decode_dir/.done.kws.${extraid}_${pron_suffix}
        } &
        done
      fi
      wait;
      set +e;
      if $subset_kws && [ -f $data_dir/subset_kws_tasks ]; then
        for subsetid in `cat $data_dir/subset_kws_tasks` ; do
          if [[ $subsetid =~ \. ]]; then
            extraid=${subsetid%%.*}
            [ ! -f $decode_dir/.done.kws.$extraid ] && continue;
          else
            ! $basic_kws && continue;
            [ ! -f $decode_dir/.done.kws ] && continue;
          fi
          [ -f $decode_dir/.done.kws.subset.${subsetid}.oov_${pront_suffix} ] && continue;
          {
          echo "==== Running ext_pron subset KWS: $ext_pron, $subsetid (OOV) ============"
          czpScripts/kws/kws_subset_eval.chenzp.sh --cmd "$cmd" --suffix ${pron_suffix} --oov true \
            --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} \
            $subsetid $data_dir $decode_dir && touch $decode_dir/.done.kws.subset.${subsetid}.oov_${pron_suffix}
          } &
          wait;
        done
      fi
      wait;
      set -e;
   # done
  fi
  if $ive_kws && [ ! -z "${ive_type}" ]; then
    #for ive_type in ive4; do
      if $basic_kws && [ ! -f $decode_dir/.done.kws_${ive_type} ]; then
        echo "==== Running IVE basic KWS: $ive_type ======================"
        czpScripts/kws/kws_search.chenzp.sh --cmd "$cmd" --suffix ${ive_type} --max-states ${max_states} \
            --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} --skip-scoring $skip_scoring\
            --indices-dir $decode_dir/kws_indices $lang_dir $data_dir $decode_dir
        touch $decode_dir/.done.kws_${ive_type}
      fi
      if $basic_kws && $oov_kws && [ ! -f $decode_dir/.done.kws_${ive_type}.oov ]; then
        {
          echo "==== Running IVE OOV KWS: $ive_type ======================"
          czpScripts/kws/kws_search.chenzp.sh --cmd "$cmd" --suffix ${ive_type} --extraid oov  \
            --max-states ${max_states} --min-lmwt ${min_lmwt} --skip-scoring $skip_scoring\
             --max-lmwt ${max_lmwt} --indices-dir $decode_dir/kws_indices \
            $lang_dir $data_dir $decode_dir
          touch $decode_dir/.done.kws_${ive_type}.oov
        } &
      fi
      if $extra_kws && [ -f $data_dir/extra_kws_tasks ]; then
        for extraid in `cat $data_dir/extra_kws_tasks` ; do
          ! $oov_kws && [[ $extraid =~ oov$ ]] && continue;
          [ $extraid == oov ] && continue;
          [ -f $decode_dir/.done.kws_${ive_type}.$extraid ] && continue;
        {
          echo "==== Running IVE extra KWS: $ive_type, $extraid ============"
          czpScripts/kws/kws_search.chenzp.sh --cmd "$cmd" --suffix ${ive_type} --extraid $extraid  \
            --max-states ${max_states} --min-lmwt ${min_lmwt} --skip-scoring $skip_scoring\
             --max-lmwt ${max_lmwt} --indices-dir $decode_dir/kws_indices \
            $lang_dir $data_dir $decode_dir
          touch $decode_dir/.done.kws_${ive_type}.$extraid
        } &
        done
      fi
      wait;
      set +e;
      if $subset_kws && [ -f $data_dir/subset_kws_tasks ]; then
        for subsetid in `cat $data_dir/subset_kws_tasks` ; do
          if [[ $subsetid =~ \. ]]; then
            extraid=${subsetid%%.*}
            [ ! -f $decode_dir/.done.kws_${ive_type}.$extraid ] && continue;
          else
            ! $basic_kws && continue;
            [ ! -f $decode_dir/.done.kws_${ive_type} ] && continue;
          fi
          [ -f $decode_dir/.done.kws_${ive_type}.subset.$subsetid ] && continue;
          {
          echo "==== Running IVE subset KWS: $ive_type, $subsetid (IV) =========="
          if [ ! -f $decode_dir/.done.kws_${ive_type}.subset.${subsetid}.iv ]; then
            czpScripts/kws/kws_subset_eval.chenzp.sh --cmd "$cmd" --suffix ${ive_type} --oov false \
              --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} \
              $subsetid $data_dir $decode_dir && touch $decode_dir/.done.kws_${ive_type}.subset.${subsetid}.iv
          fi
          } &
          {
          echo "==== Running IVE subset KWS: $ive_type, $subsetid (OOV) ============"
          if $oov_kws && [ ! -f $decode_dir/.done.kws_${ive_type}.subset.${subsetid}.oov ]; then
            czpScripts/kws/kws_subset_eval.chenzp.sh --cmd "$cmd" --suffix ${ive_type} --oov true \
              --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} \
              $subsetid $data_dir $decode_dir && touch $decode_dir/.done.kws_${ive_type}.subset.${subsetid}.oov
          fi
          } &
          wait;
          if   [ -f $decode_dir/.done.kws_${ive_type}.subset.${subsetid}.iv ] \
            && [ -f $decode_dir/.done.kws_${ive_type}.subset.${subsetid}.oov ]; then
            touch $decode_dir/.done.kws_${ive_type}.subset.$subsetid
          fi
        done
      fi
      wait;
      set -e;
   # done
  fi
fi
wait;
