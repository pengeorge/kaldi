#!/bin/bash

lp=FullLP
lr=BaseLR
ar=NTAR
scase=BaEval
version=1
sysid=comb-all
prim=c
cer=0
dryrun=false
dir="./exp/combine-sep-1.64/7-word_plp_smbr_ive-word_plp_sgmm_ive-word_bnf_sgmm_ive-word_bnf_ce_ive-sub6_plp_smbr-syl_plp_smbr_ive-phone_plp_smbr"
subdir=
param='*'
final=false
dev2shadow=dev10h.pem
eval2shadow=eval.seg
team=MSIIP

no_suffix=false # if true, would only find results in 'kws_\d+'
extraid_dev=
extraid_eval=

release_kws=true
release_stt=true

release_conf=

#end of configuration

echo $0 " " "$@"

[ -f ./cmd.sh ] && . ./cmd.sh
[ -f ./path.sh ] && . ./path.sh
. ./utils/parse_options.sh

if [ $# -ne 2 ] ; then
  echo "Invalid number of parameters!"
  echo "Parameters " "$@"
  echo "$0 --ar <NTAR|TAR> --lr <BaseLR|BabelLR|OtherLR> --lp <FullLP|LimitedLP> --sysid <NAME> [--version <version-nr> ] <config> <output>"
  exit 1
fi


[ -z $lp ] && echo "Error -- you must specify --lp <FullLP|LimitedLP>" && exit 1
if [ "$lp" != "FullLP" ] && [ "$lp" != "LimitedLP" ] ; then
  echo "Error -- you must specify --lp <FullLP|LimitedLP>" && exit 1
fi

[ -z $lr ] && echo "Error -- you must specify --lr <BaseLR|BabelLR|OtherLR>" && exit 1
if [ "$lr" != "BaseLR" ] && [ "$lr" != "BabelLR" ]  && [ "$lr" != "OtherLR" ] ; then
  echo "Error -- you must specify --lr <BaseLR|BabelLR|OtherLR>" && exit 1
fi
[ -z $ar ] && echo "Error -- you must specify --ar <NTAR|TAR>" && exit 1
if [ "$ar" != "NTAR" ] && [ "$ar" != "TAR" ] ; then
  echo "Error -- you must specify --ar <NTAR|TAR>" && exit 1
fi
[ -z $sysid ] && echo "Error -- you must specify name" && exit 1

[ ! -f $1 ] && echo "Configuration $1 does not exist! " && exit 1
. $1
outputdir=$2

if [ ! -z "$release_conf" ]; then
  [ ! -f $release_conf ] && echo "Release configuration $release_conf does not exist! " && exit 1
  . $release_conf
fi

if [ ! -z "$extraid_dev" ]; then
  extra_pre_dev=${extraid_dev}_
else
  extra_pre_dev=
fi
if [ ! -z "$extraid_eval" ]; then
  extra_pre_eval=${extraid_eval}_
else
  extra_pre_eval=
fi
kwlistid=`echo $eval_kwlist_file | grep -Po '(?<=kwlist)\d+(?=\.xml)'`

function export_file {
  # set -x
  source_file=$1
  target_file=$2
  if [ ! -f $source_file ] ; then
    echo "The file $source_file does not exist!"
    exit 1
  else
    if [ ! -f $target_file ] ; then
      if ! $dryrun ; then
        ln -s `readlink -f $source_file` $target_file || exit 1
      fi
    else
      echo "The file is already there, not doing anything. Either change the version (using --version), or delete that file manually)"
      return 0
    fi
  fi
  return 0
}

function export_kws_file {
  source_xml=$1
  fixed_xml=$2
  kwlist=$3
  export_xml=$4
  
  echo "Exporting KWS $source_xml as `basename $export_xml`"
  if [ -f $source_xml ] ; then
    cp $source_xml $fixed_xml.bak
    fdate=`stat --printf='%y' $source_xml`
    echo "The source file $source_xml has timestamp of $fdate"
    echo "Authorizing empty terms from `basename $kwlist`..."
    if ! $dryrun ; then
      if [ ! -f $fixed_xml ] || [ $fixed_xml -ot $source_xml ]; then
        local/fix_kwslist.pl $kwlist $source_xml $fixed_xml || exit 1
      fi
    else
      fixed_xml=$source_xml
    fi
    echo "Exporting...export_file $fixed_xml $export_xml "
    export_file $fixed_xml $export_xml || exit 1
  else
    echo "The file $source_xml does not exist. Exiting..."
    exit 0
  fi
  echo "Export done successfully..."
  return 0
}

if [[ "$eval_kwlist_file" == *.kwlist.xml ]] ; then
  corpus=`basename $eval_kwlist_file .kwlist.xml`
elif [[ "$eval_kwlist_file" == *.kwlist2.xml ]] ; then
  corpus=`basename $eval_kwlist_file .kwlist2.xml`
elif [[ "$eval_kwlist_file" == *.kwlist3.xml ]] ; then
  corpus=`basename $eval_kwlist_file .kwlist3.xml`
elif [[ "$eval_kwlist_file" == *.kwlist4.xml ]] ; then
  corpus=`basename $eval_kwlist_file .kwlist4.xml`
elif [[ "$eval_kwlist_file" == *.kwlist5.xml ]] ; then
  corpus=`basename $eval_kwlist_file .kwlist5.xml`
else
  echo "Unknown naming pattern of the kwlist file $eval_kwlist_file"
  exit 1
fi
#REMOVE the IARPA- prefix, if present
#corpus=${corpora##IARPA-}

#scores=`find -L $dir  -name "sum.txt"  -path "*${dev2shadow}_${eval2shadow}*" | xargs grep "|   Occurrence" | cut -f 1,13 -d '|'| sed 's/:|//g' | column -t | sort -k 2 -n -r  `
#scores=`find -L $dir  -wholename "*kws*/sum.txt"  -path "*${dev2shadow}*" | xargs grep "|   Occurrence" | cut -f 1,13 -d '|'| sed 's/:|//g' | column -t | sort -k 2 -n -r  `
kws_root="$dir/*$dev2shadow*/$subdir"

dev_iv_exist=true
dev_oov_exist=true
dev_iv_cand_num=`echo $kws_root/${extra_pre_dev}kws_${param}/sum.txt` # | wc -w`
dev_oov_cand_num=`echo $kws_root/${extra_pre_dev}oov_kws_${param}/sum.txt` # | wc -w`
echo $dev_iv_cand_num
echo $dev_oov_cand_num
if [ `echo $dev_iv_cand_num | grep '*'|wc -l` -eq 1 ]; then
  echo "Error finding $kws_root/${extra_pre_dev}kws_${param}/sum.txt, file does not exist."
  dev_iv_exist=false
fi
if [ `echo $dev_oov_cand_num | grep '*'|wc -l` -eq 1 ]; then
  echo "Error finding $kws_root/${extra_pre_dev}oov_kws_${param}/sum.txt, file does not exist."
  dev_oov_exist=false
fi
set -e
set -o pipefail 
if $dev_iv_exist && $dev_oov_exist; then
  # Check whether IV and OOV columns match ==============
  grep -H "|   Occurrence" $kws_root/${extra_pre_dev}kws_${param}/sum.txt | cut -f 1,13 -d '|' |\
    paste - <(grep -H "^| *Occ" $kws_root/${extra_pre_dev}oov_kws_${param}/sum.txt | sed 's:oov_::' | cut -f 1,13 -d '|') |\
    awk 'BEGIN{e=0;} {if ($1 != $3){e=e+1}} END{exit e;}' # if not match, this would return non-match number.
  # End check ===========================================

  echo $param
  scores=`grep -H "|   Occurrence" $kws_root/${extra_pre_dev}kws_${param}/sum.txt | cut -f 1,13 -d '|' |\
            paste - <(grep -H "^| *Occ" $kws_root/${extra_pre_dev}oov_kws_${param}/sum.txt | cut -f 13 -d '|')`
  if $no_suffix; then
    scores=`echo "$scores" | grep -P 'kws_\d+/'`
  fi
  scores=`echo "$scores" | sed 's/:|//g' | column -t | awk '{print $0"	"($2+$3);}' | sort -k 4 -n -r  `

  [ -z "$scores" ] && echo "Nothing to export, exiting..." && exit 1

  echo  "$scores" | head
  count=`echo "$scores" | wc -l`
  echo "Total result files: $count"
  best_score=`echo "$scores" | head -n 1 | cut -f 1 -d ' '`

  lmwt=`echo $best_score | sed 's:.*/'$extra_pre_dev'kws_\([^/]*[0-9][0-9]*\)/.*:\1:g'`
  echo "Best scoring file of dev: $best_score"
  echo "lmwt (or other parameter) = $lmwt"
  #base_dir=`echo $best_score | sed "s:\\(.*\\)/${dev2shadow}_${eval2shadow}/.*:\\1:g"`
  best_eval_file=`echo $best_score | sed "s:${dev2shadow}:${eval2shadow}:g" | sed "s:${extra_pre_dev}kws_:${extra_pre_eval}kws_:"`
  iv_eval_dir=`dirname $best_eval_file`
  oov_eval_dir=`echo $iv_eval_dir | sed 's:kws_:oov_kws_:'`
else
  echo "No dev results found, will skip selecting the best on dev but using eval result directly."
  kws_root=`echo $kws_root | sed "s:${dev2shadow}:${eval2shadow}:g"` # | sed "s:${extra_pre_dev}kws_:${extra_pre_eval}kws_:"`
  eval_iv_cand_num=`echo $kws_root/${extra_pre_eval}kws_${param} | wc -w`
  eval_oov_cand_num=`echo $kws_root/${extra_pre_eval}oov_kws_${param} | wc -w`
  if [ $eval_iv_cand_num -gt 1 ]; then
    echo "No dev result is found and multiple IV eval result is found:"
    echo $kws_root/${extra_pre_eval}kws_${param}
    exit 1;
  fi
  if [ $eval_iv_cand_num -eq 0 ]; then
    echo "No IV eval result found"
    exit 1;
  fi
  if [ $eval_oov_cand_num -gt 1 ]; then
    echo "No dev result is found and multiple OOV eval result is found"
    exit 1;
  fi
  if [ $eval_oov_cand_num -eq 0 ]; then
    echo "No OOV eval result found"
    exit 1;
  fi
  iv_eval_dir=`echo $kws_root/${extra_pre_eval}kws_${param}`
  oov_eval_dir=`echo $kws_root/${extra_pre_eval}oov_kws_${param}`
fi
echo "Best iv eval dir: $iv_eval_dir"
echo "Best oov eval dir: $oov_eval_dir"

if $release_kws; then

eval_kwlist=$iv_eval_dir/kwslist.merged.xml
if [ ! -f $eval_kwlist ] || [ $eval_kwlist -ot $iv_eval_dir/kwslist.xml ] || [ $eval_kwlist -ot $oov_eval_dir/kwslist.xml ]; then
  echo "-------------------------------------"
  echo " Merging IV and OOV results"
  echo "-------------------------------------"
  if [ ! -f $iv_eval_dir/kwslist.filt.xml ]; then
    grep -v 'score="0\.0.."' $iv_eval_dir/kwslist.xml > $iv_eval_dir/kwslist.filt.xml
  fi
  if [ ! -f $oov_eval_dir/kwslist.filt.xml ]; then
    grep -v 'score="0\.0.."' $oov_eval_dir/kwslist.xml > $oov_eval_dir/kwslist.filt.xml
  fi
  czpScripts/local/merge_kwslist.pl $iv_eval_dir/kwslist.filt.xml $oov_eval_dir/kwslist.filt.xml $iv_eval_dir/kwslist.merged.xml
else
  echo "Merged kwslist exists and newer than both IV and OOV file. Skip merging."
fi

eval_fixed_kwlist=$iv_eval_dir/kwslist.merged.fixed.xml
eval_export_kwlist=$outputdir/KWS14_${team}_${corpus}_${scase}_KWS_${prim}-${sysid}_${version}.kwslist${kwlistid}.xml

echo "export_kws_file $eval_kwlist $eval_fixed_kwlist $eval_kwlist_file $eval_export_kwlist"
export_kws_file $eval_kwlist $eval_fixed_kwlist $eval_kwlist_file $eval_export_kwlist

fi # End of "if $release_kws"

if $release_stt; then

# TODO if we submit a file under norm-XX, the ctm would be in $kws_root/../score_$lmwt
echo $iv_eval_dir
eval_decode_dir=`dirname $iv_eval_dir`
while [ ! -z $eval_decode_dir ] && [ -z `echo $eval_decode_dir | grep $eval2shadow` ]; do
  eval_decode_dir=`basename $eval_decode_dir`
done
echo $eval_decode_dir
[ -z $eval_decode_dir ] && exit 1;
eval_ctm=$eval_decode_dir/score_$lmwt/${eval2shadow}.ctm
eval_export_ctm=$outputdir/KWS14_${team}_${corpus}_${scase}_STT_${prim}-${sysid}_${version}.ctm
cat $eval_ctm | sed 's: A : 1 :' > $eval_ctm.to_submit
echo "export_file $eval_ctm.to_submit $eval_export_ctm"
export_file $eval_ctm.to_submit $eval_export_ctm

fi # End of "if $release_stt"

echo "Everything looks fine, good luck!"
exit 0

