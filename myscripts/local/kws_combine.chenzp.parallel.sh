#!/bin/bash

# Copyright 2013-2014  Johns Hopkins University (authors: Jan Trmal, Guoguo Chen, Dan Povey)

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


# Script for system combination using minimum Bayes risk decoding.
# This calls lattice-combine to create a union of lattices that have been 
# normalized by removing the total forward cost from them. The resulting lattice
# is used as input to lattice-mbr-decode. This should not be put in steps/ or 
# utils/ since the scores on the combined lattice must not be scaled.

# begin configuration section.
cmd=run.pl
stage=0
# Ntrue-scale
Ntrue_scale=1.1
extraid=
method=pSUM
min_param=1
max_param=9
skip_scoring=false
subset_kws=true
optimize_weights=false

parallel_thres_mem=5000  # if the estimated memory > this value, the work of
                         # combination would be run in parallel.
kwlist_nj=96  # number of jobs for generating kwslist

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

set -e;

datadir=$1
lang=$2
odir=${@: -1}  # last argument to the script
shift 2;
decode_dirs=( $@ )  # read the remaining arguments into an array
unset decode_dirs[${#decode_dirs[@]}-1]  # 'pop' the last argument which is odir
num_sys=${#decode_dirs[@]}  # number of systems to combine

if [ ! -z "$extraid" ]; then
  extra_pre=${extraid}_
fi

for f in $datadir/${extra_pre}kws/ecf.xml $datadir/${extra_pre}kws/kwlist.xml ; do
  [ ! -f $f ] && echo "$0: file $f does not exist" && exit 1;
done
kwsdatadir=$datadir/${extra_pre}kws
ecf=$kwsdatadir/ecf.xml
kwlist=$kwsdatadir/kwlist.xml

# Duration
duration=`head -1 $ecf |\
    grep -o -E "duration=\"[0-9]*[    \.]*[0-9]*\"" |\
    perl -e 'while($m=<>) {$m=~s/.*\"([0-9.]+)\".*/\1/; print $m/2;}'`

mkdir -p $odir/log

total_sum=0
for i in `seq 0 $[num_sys-1]`; do
  decode_dir=${decode_dirs[$i]}
  offset=`echo $decode_dir | cut -d: -s -f2` # add this to the lm-weight.
  [ -z "$offset" ] && offset=1
  #total_sum=$(($total_sum+$offset))
  total_sum=`perl -e "print $total_sum+$offset;"`
done

systems=""
for i in `seq 0 $[num_sys-1]`; do
  decode_dir=${decode_dirs[$i]}
  offset=`echo $decode_dir | cut -d: -s -f2` # add this to the lm-weight.
  decode_dir=`echo $decode_dir | cut -d: -f1`
  [ -z "$offset" ] && offset=1
  
  weight=$(perl -e "print ($offset/$total_sum);")
  if [ -f $decode_dir ] ; then
    systems+="$weight $decode_dir "
  else
    kwsfile=$decode_dir/kwslist.unnormalized.xml
    [ ! -f ${kwsfile} ] && echo "The file ${kwsfile} does not exist!" && exit 1
    systems+="$weight ${kwsfile} "
  fi
done

echo "Combining Systems:"
echo $systems | awk 'BEGIN{flag=0}
  {for(i=1;i<=NF;i++){
    printf "%s",$i;
    if(!flag){
      printf "\t";
    }else{
      printf "\n";
    }
    flag=1-flag;
  }}'

if [[ $method =~ _t$ ]]; then
  method_opt=" --best-time=true"
else
  method_opt=" --best-time=false"
fi
method2comb=`echo $method | sed 's/_t$//'`
if [[ $method2comb =~ ^pq || $method2comb =~ ^qp ]]; then
  echo "Currently we can't support methods with both p and q parameters."
  exit 1;
fi

use_q=false
if [[ $method2comb =~ ^q ]]; then
  method2comb=`echo $method2comb | sed 's:^q::'`
  use_q=true
elif [[ $method2comb =~ ^p ]]; then
  method_opt+=" --power=0.PARAM"
else
  min_param=1
  max_param=1
fi
# Combination of the weighted sum and power rule
  #systems_in_use=`echo $systems | sed "s:/kws_:/${extra_pre}kws_:g"`
  systems_in_use=$systems
  line=0;
  system_kwslists=`echo $systems_in_use | awk '{i=2; while(i<=NF) { print $i;i+=2;}}'`
  for s in $system_kwslists; do
    echo "greping $s"
    let line=line+`grep '<kw ' $s | wc -l`
  done
  mem_est=`echo $line | perl -e '$num=<>; chomp($num); printf "%d", $num/600;'`
  echo "($extraid): The estimated memory usage is $mem_est MB"

  if [ ! -f $odir/.done.${extra_pre}kws_comb ]; then
    if [ $mem_est -gt $parallel_thres_mem ]; then # Combine in parallel
      mem_per_job=`perl -e 'printf "%d", '$mem_est'/'$kwlist_nj';'`
      echo "will write kwslist file in parallel, average memory of each job is about $mem_per_job MB"
      cmd="`echo "$cmd" | sed 's:ram_free=[0-9]\+M:ram_free='$mem_per_job'M:' | sed 's:mem_free=[0-9]\+M:mem_free='$mem_per_job'M:'`"
      . czpScripts/local/datasets/split_kwlist.sh
      if [[ $system_kwslists =~ \.unnormalized\.xml ]]; then  # if use unnormalized kwslist
        norm_flag=.unnormalized
      else
        norm_flag=
      fi
      for s in $system_kwslists; do
        ressplitdir=`dirname $s`/split${kwlist_nj}
        # TODO These done files should be unified.
        if [ -z "$norm_flag" ]; then
          donefile=$ressplitdir/.done.kwslist.norm.split
        else
          donefile=$ressplitdir/.done.write_unnorm
        fi
        if [ ! -f $donefile ]; then
          echo "NOTE: $s "
          echo "      has not been splitted into $kwlist_nj parts. Now split it."
          mkdir -p $ressplitdir/log
          $cmd JOB=1:$kwlist_nj $ressplitdir/log/split_kwslist.JOB.log \
            set -e ';' set -o pipefail ';'\
            cat $splitdir/kwlist.JOB \| \
            czpScripts/local/subset_kws_result.pl $ressplitdir/../kwslist${norm_flag}.xml \
            '>' $ressplitdir/kwslist${norm_flag}.JOB.xml
          touch $donefile
        fi
      done

      # Re-estimated memory
      top_kwslist_info=`du -s $system_kwslists | sort -nr | head -n 1`
      du -sh $system_kwslists | sort -nr
      top_kwslist=`dirname $(echo $top_kwslist_info | cut -f 2 -d ' ')`
      top_kwslist_size=`echo $top_kwslist_info | cut -f 1 -d ' '`
      echo "The largest kwslist of all systems is $top_kwslist ($top_kwslist_size KB)"
      top_job_info=`du -s $top_kwslist/split${kwlist_nj}/kwslist${norm_flag}.[!.].xml | sort -nr | head -n 1`
      top_job=`basename $(echo $top_job_info | cut -f 2 -d ' ')`
      top_job_size=`echo $top_job_info | cut -f 1 -d ' '`
      echo "  The largest job in the largest kwslist is $top_job ($top_job_size KB)"
      job_line=0
      set +e; # in case grep find nothing
      for s in $system_kwslists; do
        top_job_kwslist=`dirname $s`/split${kwlist_nj}/$top_job
        echo "  greping $top_job_kwslist"
        let job_line=job_line+`grep '<kw ' $top_job_kwslist | wc -l`
      done
      set -e;
      mem_per_job=`echo $job_line | perl -e '$num=<>; chomp($num); printf "%d", $num/600;'`
      echo "The re-estimated maximum memory usage of one job is $mem_per_job MB"
      if [ $mem_per_job -gt 30000 ]; then
        echo "$mem_per_job MB > 30000 MB, we'll force the requested memory as 30000MB."
        echo "  Please monitor if the scoring is out of memory."
        mem_per_job=30000
      fi
      cmd="`echo "$cmd" | sed 's:ram_free=[0-9]\+M:ram_free='$mem_per_job'M:' | sed 's:mem_free=[0-9]\+M:mem_free='$mem_per_job'M:'`"
      for param in `seq $min_param $max_param`; do
        osplitdir=$odir/${extra_pre}kws_$param/split${kwlist_nj}
        mkdir -p $osplitdir
        if [ ! -f $osplitdir/.done.write_unnorm ]; then
          systems_one_job=`echo $systems_in_use | sed 's:/kwslist'${norm_flag}'\.xml:/split'${kwlist_nj}'/kwslist'${norm_flag}'.JOB.xml:g'`
          this_method_opt=`echo $method_opt | sed 's:PARAM:'${param}':g'`
          echo "Writing unnormalized splitted kwslists... --method-opt \"$this_method_opt\""
          if $use_q; then
            $cmd JOB=1:$kwlist_nj $odir/log/combine_${extra_pre}kws.${param}.JOB.log \
              czpScripts/local/comb_plus-weight-power.sh --method $method2comb --method-opt "$this_method_opt" --weight-power $param \
                "$systems_one_job" $osplitdir/kwslist.unnormalized.JOB.xml || exit 1
          else
            $cmd JOB=1:$kwlist_nj $odir/log/combine_${extra_pre}kws.${param}.JOB.log \
              czpScripts/local/comb.pl --method=$method2comb $this_method_opt \
                $systems_one_job $osplitdir/kwslist.unnormalized.JOB.xml || exit 1
          fi
          touch $osplitdir/.done.write_unnorm
        fi
        if [ ! -f $osplitdir/.done.kwslist.norm.split ]; then
          echo "Writing normalized splitted kwslists..."
          $cmd JOB=1:$kwlist_nj $odir/log/postprocess_${extra_pre}kws.${param}.JOB.log \
            utils/kwslist_post_process.chenzp.pl --duration=${duration} --digits=3 \
              --normalize=true --Ntrue-scale=${Ntrue_scale} --cutoff-thres 0 \
              $osplitdir/kwslist.unnormalized.JOB.xml \
              $osplitdir/kwslist.JOB.xml || exit 1
          touch $osplitdir/.done.kwslist.norm.split
        fi
        if [ ! -f $osplitdir/.done.write_norm ]; then
          echo "Merging normalized splitted kwslists..."
          merged_file=$osplitdir/../kwslist.xml
          sed '$d' $osplitdir/kwslist.1.xml > $merged_file
          for JOB in `seq 2 $((kwlist_nj-1))`; do
            sed '1d;$d' $osplitdir/kwslist.${JOB}.xml >> $merged_file
          done
          sed '1d' $osplitdir/kwslist.${kwlist_nj}.xml >> $merged_file
          touch $osplitdir/.done.write_norm
        fi
      done
    else # No parallel
      cmd="`echo "$cmd" | sed 's:ram_free=[0-9]\+M:ram_free='$mem_est'M:' | sed 's:mem_free=[0-9]\+M:mem_free='$mem_est'M:'`"
      if $use_q; then
        $cmd PARAM=$min_param:$max_param $odir/log/combine_${extra_pre}kws.PARAM.log \
          mkdir -p $odir/${extra_pre}kws_PARAM/ '&&' \
          czpScripts/local/comb_plus-weight-power.sh --method $method2comb --method-opt "$method_opt" --weight-power PARAM \
            "$systems_in_use" $odir/${extra_pre}kws_PARAM/kwslist.unnormalized.xml || exit 1
      else
        $cmd PARAM=$min_param:$max_param $odir/log/combine_${extra_pre}kws.PARAM.log \
          mkdir -p $odir/${extra_pre}kws_PARAM/ '&&' \
          czpScripts/local/comb.pl --method=$method2comb $method_opt \
            $systems_in_use $odir/${extra_pre}kws_PARAM/kwslist.unnormalized.xml || exit 1
      fi
      $cmd PARAM=$min_param:$max_param $odir/log/postprocess_${extra_pre}kws.PARAM.log \
        utils/kwslist_post_process.chenzp.pl --duration=${duration} --digits=3 \
          --normalize=true --Ntrue-scale=${Ntrue_scale} --cutoff-thres 0 \
          $odir/${extra_pre}kws_PARAM/kwslist.unnormalized.xml \
          $odir/${extra_pre}kws_PARAM/kwslist.xml || exit 1
    fi
    touch $odir/.done.${extra_pre}kws_comb
    touch $odir/.done.kws.${extraid}
    touch $odir/.please_score.${extraid}
  fi
  if [ -f $odir/.please_score.${extraid} ] && ! $skip_scoring ; then
    if [ ! -z "$extraid" ]; then
      extra_flag="--extraid $extraid"
    else
      extra_flag=
    fi
    echo "NOW scoring..."
    echo "The estimated memory usage is $mem_est MB"
    if [ $mem_est -gt 30000 ]; then
      echo "$mem_est MB > 30000 MB, we'll force the requested memory as 30000MB."
      echo "  Please monitor if the scoring is out of memory."
      mem_est=30000
    fi
    cmd="`echo "$cmd" | sed 's:ram_free=[0-9]\+M:ram_free='$mem_est'M:' | sed 's:mem_free=[0-9]\+M:mem_free='$mem_est'M:'`"
    $cmd PARAM=$min_param:$max_param $odir/log/score_${extra_pre}kws.PARAM.log \
      local/kws_score.sh $extra_flag $datadir $odir/${extra_pre}kws_PARAM || exit 1
    rm $odir/.please_score.${extraid}
  fi

  if $subset_kws && [ -f $datadir/subset_kws_tasks ]; then
    if [[ $extraid =~ oov$ ]]; then
      oov=true
      extra_kwlist=`echo $extraid | sed 's:_oov$::' | sed 's:oov$::' `
    else
      oov=false
      extra_kwlist=$extraid
    fi
    for subsetid in `cat $datadir/subset_kws_tasks` ; do
      if [[ $subsetid =~ \. ]]; then
        [ "$extra_kwlist" != "${subsetid%%.*}" ] && continue;
        subsettype=${subsetid##*.}
      else
        [ ! -z "$extra_kwlist" ] && continue;
        subsettype=$subsetid
      fi
      echo "$extra_kwlist ==== $subsettype"
      [ -f $odir/.done.${extra_pre}kws.subset.$subsettype ] && continue;
      {
      if [ ! -z "$extra_kwlist" ]; then
        extra_flag="--extraid $extra_kwlist"
      else
        extra_flag=
      fi
      czpScripts/kws/kws_subset_eval.chenzp.sh --cmd "$decode_cmd" $extra_flag --skip-scoring $skip_scoring \
        --min-param $min_param --max-param $max_param --oov $oov \
        $subsetid $datadir $odir
      if [ $? == 0 ]; then
        touch $odir/.done.${extra_pre}kws.subset.$subsettype
      fi
      } &
    done
    wait
  fi

echo 'Done.'
