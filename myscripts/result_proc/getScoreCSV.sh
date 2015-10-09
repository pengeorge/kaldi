#!/bin/bash

# Generate a CSV format table containing STT and KWS scores.
# (Author: chenzp, Mar 2,2014)

kws_only=false
extra=
suffix=
type1=1gram
type2=mgram

. ./utils/parse_options.sh
set -e
if [ $# -lt 1 ]; then
  echo "Usage: `basename $0` <decode-dir> [<sub-dir> [<para-value/LM-weight>]]"
  echo "para-value/LM-weight can be set to \"all\" if you want all results of different parameter."
  exit 1;
fi

decodedir=$1
subdir=$2 # if no subdir, set empty
lmwt=$3

if [ "$subdir" == "-" ]; then
  subdir=
fi
echo "decodedir = $decodedir"
echo "subdir = $subdir"
echo "para-value = $lmwt"
if [ ! -d "$decodedir" ]; then
  echo "[ERROR] `basename $0`: decode dir '$decodedir' doesn't exist."
  exit 1;
fi

if $kws_only ; then
  if [ -z "$lmwt" ]; then
    echo "[ERROR] para-value/LM-weight should be specified when '--kws-only' option is set to true"
    echo "e.g. $0 --kws-only true exp/tri5/decode - 12"
    exit 0;
  fi
else
  echo '**********************************************************************************************'
  echo "*  Generating scores' CSV for \"$decodedir\", LMWT = $lmwt"
  echo '**********************************************************************************************'
  # Get the best WER
  bestlmwt=`grep Sum $decodedir/score_*/*.raw | grep -Po '(?<=/score_)\d+(?=/)' |\
    paste - <(grep Sum $decodedir/score_*/*.raw | grep -Po '\d+(?= +\d+ +\|[^\|]+\|$)') |\
    awk 'BEGIN{min=1000000000000;id=-1}{if ($2<min) {min=$2;id=$1}} END {print id}'`

  bestWER=`grep Sum $decodedir/score_$bestlmwt/*.sys | grep -Po '\d+\.\d+(?= +\d+\.\d+ +\|[^\|]+\|$)'`
  echo "LMWT with best WER ($bestWER) = $bestlmwt"
  echo '----------------------------------------------------------------'
  grep Sum $decodedir/score_$bestlmwt/*.sys | sed 's: \+: :g' # for check
  echo '----------------------------------------------------------------'

  echo 'WER of each LMWT, check if the result is what you want:' >&2
  grep Sum $decodedir/score_*/*.sys | sed 's:  \+:  :g' >&2  # for check

  echo '' >&2
  if [ -z $lmwt ]; then
      echo "[WARNING] No parameter/LMWT specified, will use the one with best WER in $decodedir" >&2
      lmwt=$bestlmwt
      echo '' >&2
  fi
fi

if [ ! -z $suffix ]; then
  basekwsdir=kws_$suffix
else
  basekwsdir=kws
fi
if [ ! -z $extra ]; then
  extraflag=${extra}_
fi
# Get the range of parameter
if [ "$lmwt" == 'all' ]; then
  if ! $kws_only ; then
    echo "[ERROR] Option para-value/LM-weight with value \"all\" when --kws-only is set to false has not been supported yet."
    exit 1;
  fi
  para_wc='*'
  para_range=`ls -l $decodedir/$subdir | grep -Po "(?<=${basekwsdir}_)\d+(?=\D|$)" | sort -u`
else
  para_wc=$lmwt
  para_range=$lmwt
fi
#echo "Range of parameter: $para_range"

# check
for oov in {'',oov_}; do
  for list in {$type1,$type2,''}; do
    for para in $para_range; do
      dir=$decodedir/$subdir/${extraflag}${oov}${basekwsdir}_$para/${list}
      if [ ! -f $dir/metrics.txt ]; then
        echo "[ERROR] Expected file $dir/metrics.txt to exist"
        #exit 1;
      fi
    done
  done
done

out=results/`echo ${decodedir}-${subdir}-${extra}-${suffix}-${lmwt} | sed 's:/:-:g'`.csv
echo "Output file: $out"
echo > $out
echo ",$decodedir" >> $out

# Output sys_info if existing
if [ -f $decodedir/${extraflag}sys_info ]; then
  cat $decodedir/${extraflag}sys_info >> $out
fi

# Output WER
if ! $kws_only ; then
  wer=`grep Sum $decodedir/score_$lmwt/*.sys | grep -Po '\d+\.\d+(?= +\d+\.\d+ +\|[^\|]+\|$)'`
  echo ",LMWT,$lmwt" >> $out
  echo ",WER,$wer" >> $out
  echo ",best WER,$bestWER" >> $out
  echo ",best LMWT,$bestlmwt" >> $out
  echo '' >> $out
fi

# Output KWS scores
echo ",$subdir" >> $out

for para in $para_range; do
  echo ",para:,$para" >> $out
  for oov in {'',oov_}; do
    line=
    for metric in {ATWV,MTWV,OTWV,STWV,'Lattice Recall'}; do
      for list in {$type1,$type2,''}; do
        dir=$decodedir/$subdir/${extraflag}${oov}${basekwsdir}_$para/${list}
        if [ ! -f $dir/metrics.txt ]; then
          line=$line",0"
        else
          line=$line","`grep -Po "(?<=^$metric = )\-?\d+\.\d+" $dir/metrics.txt`
        fi
      done
      line=$line","
    done
    echo $line >> $out
  done
  echo >> $out
done
echo 'Done.'
