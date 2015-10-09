#!/bin/bash


. conf/common_vars.sh
. ./lang.conf
. ./cmd.sh

datadir=dev10h.pem
sys_set='word_plp_en_ce word_plp_smbr word_plp_sgmm word_plp_cnn_dnn_smbr word_bnf_sgmm word_bnf_ce'
subset_kws=true
skip_scoring=false
norm_method=
comb_method=W_pSUM   # Methods Supported: [W_][p]{SUM,MNZ}[_t]
extraid= # extraid for KWS comb
sep=true  # whether or not combine IV and OOV separately
use_unnorm=false # almost making no differences, use kwslist.xml seems a bit better overall.
stt_comb=true
kws_comb=true
iv_comb=true
oov_comb=true
Ntrue_scale='1.64'

. ./utils/parse_options.sh
set -e
set -o pipefail
set -u

# check if the options are legal
if ! $sep; then
  if ! $iv_comb || ! $oov_comb; then
    echo "Illegal options, both iv_comb and oov_comb should be true if sep is set to false."
  fi
fi
# Systems' definition
. ./syslist.conf

# Variables for KWS comb
if [ ! -z "$extraid" ]; then
  extra_pre=${extraid}_
else
  extra_pre=
fi
if [ -z "$norm_method" ]; then
  norm_subdir=
else
  norm_subdir=norm-$norm_method
fi
if [ -z "$comb_method" ]; then
  comb_subdir=
  comb_method=pSUM # If not specified, use kaldi's default method: p-power CombSUM
else
  comb_subdir=comb-$comb_method
fi

# Functions
function best_system_path_stt {
  path_to_outputs=$1
  best_out=` (find $path_to_outputs -name *.ctm.sys | xargs grep Avg)  | sed 's/|//g' | column -t | sort -n -k 9 | head -n 1|  awk '{print $1}' `
  echo `dirname $best_out`
}
function best_system_path_kws {
  path_to_decode=$1
  suffix=$2
#  best_out=`grep "^| *Occ" $path_to_outputs/sum.txt | cut -f 1,13,17 -d '|' | sed 's/|//g'  |  sort -r -n -k 3 | head -n 1| awk '{print $1}' | sed 's/:$//'`
  best_out=`grep -H "^| *Occ" $path_to_decode/$norm_subdir/${extra_pre}kws${suffix}_[0-9]*/sum.txt | cut -f 1,13,17 -d '|' |\
    paste - <(grep -H "^| *Occ" $path_to_decode/$norm_subdir/${extra_pre}oov_kws${suffix}_[0-9]*/sum.txt | cut -f 13,17 -d "|") |\
    sed 's/|//g'  |  awk 'BEGIN{max=-1;best=-1;} {
      if ($3+$5 > max) {
        max = $3 + $5;
        best = $1;
      } } END { print best }' | sed 's/:$//'`
  echo `dirname $best_out`
}
function best_iv_system_path_kws {
  path_to_decode=$1
  suffix=$2
#  best_out=`grep "^| *Occ" $path_to_outputs/sum.txt | cut -f 1,13,17 -d '|' | sed 's/|//g'  |  sort -r -n -k 3 | head -n 1| awk '{print $1}' | sed 's/:$//'`
  best_out=`grep -H "^| *Occ" $path_to_decode/$norm_subdir/${extra_pre}kws${suffix}_[0-9]*/sum.txt | cut -f 1,13,17 -d '|' |\
    sed 's/|//g'  |  awk 'BEGIN{max=-1;best=-1;} {
      if ($3 > max) {
        max = $3;
        best = $1;
      } } END { print best }' | sed 's/:$//'`
  echo `dirname $best_out`
}
function best_oov_system_path_kws {
  path_to_decode=$1
  suffix=$2
#  best_out=`grep "^| *Occ" $path_to_outputs/sum.txt | cut -f 1,13,17 -d '|' | sed 's/|//g'  |  sort -r -n -k 3 | head -n 1| awk '{print $1}' | sed 's/:$//'`
  best_out=`grep -H "^| *Occ" $path_to_decode/$norm_subdir/${extra_pre}oov_kws${suffix}_[0-9]*/sum.txt | cut -f 1,13,17 -d '|' |\
    sed 's/|//g'  |  awk 'BEGIN{max=-1;best=-1;} {
      if ($3 > max) {
        max = $3;
        best = $1;
      } } END { print best }' | sed 's/:$//'`
  echo `dirname $best_out`
}


# Wait till the main run.sh gets to the stage where's it's 
# finished aligning the tri5 model.

function lm_offsets {
  min=999
  for dir in "$@" ; do  
    lmw=${dir##*score_}

    [ $lmw -le $min ] && min=$lmw
  done

  lat_offset_str=""
  for dir in "$@" ; do  
    latdir_dir=`dirname $dir`
    lmw=${dir##*score_}
  
    offset=$(( $lmw - $min ))
    if [ $offset -gt 0 ] ; then
      lat_offset_str="$lat_offset_str ${latdir_dir}:$offset "
    else
      lat_offset_str="$lat_offset_str ${latdir_dir} "
    fi
  done

  echo $lat_offset_str

}

combname=`echo $sys_set | awk '{name=NF; for(i=1;i<=NF;i++) {name=name"-"$i}} END {print name}'`

# Combination of STT results
sttdir=exp/stt/$combname/$datadir
if $stt_comb && [ ! -f $sttdir/.done ]; then
  echo =====================================
  echo " Combining STT results: $sttdir"
  echo =====================================
  stt_sys_string=
  for sys in $sys_set ; do
    echo "Reading system: $sys"
    sys_val=${systems[$sys]}
    echo "----------------------------------------------------------------"
    echo "[$sys] = $sys_val"
    if [[ $sys_val =~ : ]]; then
      decode_dir=`echo "$sys_val" | awk -F ":" '{print $1}'`
    else
      decode_dir=$sys_val
    fi
    echo "$decode_dir"
    stt_sys_string="$stt_sys_string "`best_system_path_stt $decode_dir`
  done
  echo
  echo `lm_offsets $stt_sys_string`
  echo
  local/score_combine.sh --cmd "$decode_cmd" data/$datadir data/lang `lm_offsets $stt_sys_string` $sttdir
  touch $sttdir/.done
fi
exit 0


# Combination of KWS results
if ! $sep; then
  combroot=combine
else
  combroot=combine-sep
fi
if $use_unnorm; then
  combroot=${combroot}-unnorm
  unnorm_flag=.unnormalized
else
  unnorm_flag=
fi
if [ $Ntrue_scale != "1.1" ]; then
  combroot=${combroot}-${Ntrue_scale}
fi
odir=exp/$combroot/$combname/$datadir/$norm_subdir/$comb_subdir
mkdir -p $odir

if $kws_comb && [ ! -f $odir/.done ]; then
  echo =====================================
  echo " Combining KWS results: $odir"
  echo =====================================
  if ! $sep; then
    echo ',weight,name,ATWV,MTWV,path' > $odir/${extra_pre}sys_info.csv
  else
    if $iv_comb; then 
      echo ',weight,name,ATWV,MTWV,path' > $odir/${extra_pre}iv_sys_info.csv
    fi
    if $oov_comb; then 
      echo ',weight,name,ATWV,MTWV,path' > $odir/${extra_pre}oov_sys_info.csv
    fi
  fi
  iv_kwslists=
  oov_kwslists=
  for sys in $sys_set ; do
    echo "Reading system: $sys"
    sys_val=${systems[$sys]}
    echo "----------------------------------------------------------------"
    echo "[$sys] = $sys_val"
    if [[ $sys_val =~ : ]]; then
      decode_dir=`echo "$sys_val" | awk -F ":" '{print $1}'`
      suffix=_`echo "$sys_val" | awk -F ":" '{print $2}'`
    else
      decode_dir=$sys_val
      suffix=
    fi
    echo "$decode_dir"
    `ls $decode_dir 2>&1 > /dev/null` || (echo "System [$sys]: $decode_dir does not exist." && exit 1;)
    if ! $sep; then  # combine according to the overall performance of IV and OOV
      bestpath_iv=`best_system_path_kws "$decode_dir" "$suffix"`
      bestpath_oov=`echo $bestpath_iv | sed 's:kws_:oov_kws_:'`
      echo "Path of best IV result is: $bestpath_iv"
      bestATWV=`grep -Po '(?<=ATWV = )[\d\.]+' $bestpath_iv/metrics.txt`+`grep -Po '(?<=ATWV = )[\d\.]+' $bestpath_oov/metrics.txt`
      bestMTWV=`grep -Po '(?<=MTWV = )[\d\.]+' $bestpath_iv/metrics.txt`+`grep -Po '(?<=MTWV = )[\d\.]+' $bestpath_oov/metrics.txt`
      bestATWV_val=`perl -e "print $bestATWV;"`
      bestMTWV_val=`perl -e "print $bestMTWV;"`
      echo "$bestATWV_val $bestMTWV_val"
      echo ",$bestMTWV_val,$sys,$bestATWV,$bestMTWV,$bestpath_iv" >> $odir/${extra_pre}sys_info.csv

      if [[ $comb_method =~ ^W[e]?_ ]]; then
        if [[ $comb_method =~ ^W_ ]]; then  # weight in IBM's WCombMNZ: MTWV
          weight=$bestMTWV_val
        elif [[ $comb_method =~ ^We_ ]]; then    # weight in BABELON's initial weight: 2^MTWV
          weight=`perl -e "print 2**($bestMTWV_val-0.5);"`
        fi
        iv_kwslists=$iv_kwslists" "$bestpath_iv/kwslist${unnorm_flag}.xml":$weight"
        oov_kwslists=$oov_kwslists" "$bestpath_oov/kwslist${unnorm_flag}.xml":$weight"
      else
        iv_kwslists=$iv_kwslists" "$bestpath_iv/kwslist${unnorm_flag}.xml
        oov_kwslists=$oov_kwslists" "$bestpath_oov/kwslist${unnorm_flag}.xml
      fi
    else  # combine IV and OOV separately
      if $iv_comb; then
        bestpath_iv=`best_iv_system_path_kws "$decode_dir" "$suffix"`
      fi
      if $oov_comb; then
        bestpath_oov=`best_oov_system_path_kws "$decode_dir" "$suffix"`
      fi
      for v in {iv,oov}; do
        eval combOrNot=\$${v}_comb
        ! $combOrNot && continue;
        eval bestpath=\$bestpath_${v}
        echo "Path of best $v result is: $bestpath"
        bestATWV=`grep -Po '(?<=ATWV = )[\d\.]+' $bestpath/metrics.txt`
        bestMTWV=`grep -Po '(?<=MTWV = )[\d\.]+' $bestpath/metrics.txt`
        bestATWV_val=`perl -e "print $bestATWV;"`
        bestMTWV_val=`perl -e "print $bestMTWV;"`
        echo "$bestATWV_val $bestMTWV_val"
        echo ",$bestMTWV_val,$sys,$bestATWV,$bestMTWV,$bestpath" >> $odir/${extra_pre}${v}_sys_info.csv

        if [[ $comb_method =~ ^W[e]?_ ]]; then
          if [[ $comb_method =~ ^W_ ]]; then  # weight in IBM's WCombMNZ: MTWV
            weight=$bestMTWV_val
          elif [[ $comb_method =~ ^We_ ]]; then    # weight in BABELON's initial weight: 2^MTWV
            weight=`perl -e "print 2**($bestMTWV_val-0.5);"`
          fi
          kwslist=$bestpath/kwslist${unnorm_flag}.xml":$weight"
        else
          kwslist=$bestpath/kwslist${unnorm_flag}.xml
        fi
        eval ${v}_kwslists=\$${v}_kwslists\" \"\$kwslist
      done
    fi
  done
  if $iv_comb; then
    echo $iv_kwslists
  fi
  if $oov_comb; then
    echo $oov_kwslists
  fi

  method2comb=`echo $comb_method | sed 's/^W[e]\?_//'`  # W_ has been processed here.
  echo "Method name to kws_combine: $method2comb"
  if [[ $comb_method =~ ^pq || $comb_method =~ ^qp ]]; then
    echo "Currently we can't support methods with both p and q parameters."
    exit 1;
  fi
  if [[ $method2comb =~ ^p ]]; then
    min_param=1
    max_param=9
  elif [[ $method2comb =~ ^q ]]; then
    min_param=1
    max_param=10
  fi
  if $iv_comb; then
    czpScripts/local/kws_combine.chenzp.sh --cmd "$decode_cmd" --extraid "$extraid" \
      --method $method2comb --skip-scoring $skip_scoring --Ntrue-scale ${Ntrue_scale} \
      --min-param $min_param --max-param $max_param \
      data/${datadir} data/lang  $iv_kwslists  $odir
  fi
  if $oov_comb; then
    czpScripts/local/kws_combine.chenzp.sh --cmd "$decode_cmd" --extraid "${extra_pre}oov" \
      --method $method2comb --skip-scoring $skip_scoring --Ntrue-scale ${Ntrue_scale} \
      --min-param $min_param --max-param $max_param \
      data/${datadir} data/lang  $oov_kwslists  $odir
  fi
  touch $odir/.done
  #   if [ ! -f $odir/.done.kws_comb-$comb_method ]; then
  # #   echo local/kws_combine.sh --cmd "$decode_cmd" data/${datadir} data/lang $plp_kws $dnn_kws $bnf_kws 
  #     for extra in {iv,oov}; do
  #       eval kwslists="\${${extra}_kwslists}"
  #       if [ "$extra" == "iv" ]; then
  #         extra_flag=
  #       else
  #         extra_flag="--extraid $extra"
  #       fi
  #       czpScripts/local/kws_combine.chenzp.sh --cmd "$decode_cmd" $extra_flag --method $comb_method \
  #         data/${datadir} data/lang \
  #         $kwslists  $odir
  #     done
  #     touch $odir/.done.kws_comb-$comb_method
  #   fi
fi
    

exit 0
