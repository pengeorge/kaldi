#!/bin/bash


. conf/common_vars.sh
. ./lang.conf
. ./cmd.sh

datadir=eval.seg
sys_file=final_syslist.conf
#sys_set='word_plp_smbr sub_plp_smbr syl_plp_smbr phone_plp_smbr_1000_bbn2'
#sys_set='word_plp_smbr_ive word_plp_sgmm_ive word_bnf_sgmm_ive word_bnf_ce_ive'
#sys_set='word_plp_smbr word_bnf_ce syl_plp_smbr sub_plp_smbr'
#sys_set='word_plp_smbr word_bnf_ce'

#sys_set='word_plp_smbr word_bnf_ce sub_plp_smbr'
sys_set='word_plp_smbr sub_plp_smbr'

#sys_set='word_plp_smbr_ive sub_plp_smbr syl_plp_smbr_ive'
#sys_set='word_plp_smbr word_plp_sgmm word_bnf_sgmm word_bnf_ce'
subset_kws=false
skip_scoring=true
norm_method=
comb_method=W_pSUM   # Methods Supported: [W_][p]{SUM,MNZ}[_t]
extraid=
sep=true  # whether or not combine IV and OOV separately
use_unnorm=false # almost making no differences, use kwslist.xml seems a bit better overall.
iv_comb=true
oov_comb=true
Ntrue_scale='3.17'

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
if [ ! -f $sys_file ]; then
  echo "File $sys_file does not exist"
  exit 1;
fi
. $sys_file

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

combname=`echo $sys_set | awk '{name=NF; for(i=1;i<=NF;i++) {name=name"-"$i}} END {print name}'`
if ! $sep; then
  echo "[ERROR] we haven't support NON-separation combination (where weights are IV and OOV systems are equal)"
  exit 1;
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
if ! $sep; then
  echo ',raw_weight,weight,name,path' > $odir/${extra_pre}sys_info.csv
else
  if $iv_comb; then 
    echo 'raw_weight,weight,name,path' > $odir/${extra_pre}iv_sys_info.csv
  fi
  if $oov_comb; then 
    echo 'raw_weight,weight,name,path' > $odir/${extra_pre}oov_sys_info.csv
  fi
fi
iv_kwslists=
oov_kwslists=
for v in {iv,oov}; do
  eval combOrNot=\$${v}_comb
  ! $combOrNot && continue;
  echo "================================================================"
  echo "Processing $v systems"
  echo "================================================================"
  for sys in $sys_set ; do
    echo "Reading system: $sys"
    eval sys_val=\$\{${v}_systems\[\$sys\]\}
    echo "----------------------------------------------------------------"
    if [[ ! $sys_val =~ ' '[0-9\.]+$ ]]; then
      echo "[ERROR] Illegal value of system $sys: $sys_val"
      exit 1;
    fi
    if [ $v == iv ]; then
      sys_val=`echo $sys_val | sed 's:/kws_:/'$extra_pre'kws_:'`
    else
      sys_val=`echo $sys_val | sed 's:/oov_kws_:/'$extra_pre'oov_kws_:'`
    fi
    echo "[$sys] = $sys_val" # sys_val here includes kws_* directory, which is different from the non-final version
    kws_dir=`echo "$sys_val" | awk -F " " '{print $1}'`
    raw_weight=`echo "$sys_val" | awk -F " " '{print $2}'`
    [ ! -d $kws_dir ] && (echo "System [$sys]: $kws_dir does not exist." && exit 1;)
    if $sep; then  # combine IV and OOV separately
      echo "Path of system $v result is: $kws_dir"
      if [[ $comb_method =~ ^W[e]?_ ]]; then
        if [[ $comb_method =~ ^W_ ]]; then  # weight in IBM's WCombMNZ: MTWV
          weight=$raw_weight
        elif [[ $comb_method =~ ^We_ ]]; then    # weight in BABELON's initial weight: 2^MTWV
          weight=`perl -e "print 2**($raw_weight-0.5);"`
        fi
        kwslist=$kws_dir/kwslist${unnorm_flag}.xml":$weight"
      else
        kwslist=$kws_dir/kwslist${unnorm_flag}.xml
      fi
      echo ",$raw_weight,$weight,$sys,$kws_dir" >> $odir/${extra_pre}${v}_sys_info.csv
      eval ${v}_kwslists=\$${v}_kwslists\" \"\$kwslist
    fi
  done
done
if $iv_comb; then
  echo
  echo $iv_kwslists
fi
if $oov_comb; then
  echo
  echo $oov_kwslists
fi
echo

method2comb=`echo $comb_method | sed 's/^W[e]\?_//'`  # W_ has been processed here.
echo "Method name to kws_combine: $method2comb"
if [[ $comb_method =~ ^pq || $comb_method =~ ^qp ]]; then
  echo "Currently we can't support methods with both p and q parameters."
  exit 1;
fi
if [[ $method2comb =~ ^p ]]; then
  min_param=6
  max_param=6
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
    

exit 0
