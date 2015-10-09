#!/bin/bash

# (Author: chenzp, Mar 2,2014)

set -e

decodedir=$1

if [ ! -d "$decodedir" ]; then
    echo "[ERROR] `basename $0`: decode dir '$decodedir' doesn't exist."
    exit 1;
fi

bestlmwt=`grep Sum $decodedir/score_*/*.raw | grep -Po '(?<=/score_)\d+(?=/)' |\
  paste - <(grep Sum $decodedir/score_*/*.raw | grep -Po '\d+(?= +\d+ +\|[^\|]+\|$)') |\
  awk 'BEGIN{min=1000000000000;id=-1}{if ($2<min) {min=$2;id=$1}} END {print id}'`

echo ''
bestWER=`grep Sum $decodedir/score_$bestlmwt/*.sys | grep -Po '\d+\.\d+(?= +\d+\.\d+ +\|[^\|]+\|$)'`
echo "LMWT with best WER ($bestWER) = $bestlmwt"
echo '----------------------------------------------------------------'
grep Sum $decodedir/score_$bestlmwt/*.sys | sed 's: \+: :g' # for check
echo '----------------------------------------------------------------'
echo 'WER of each LMWT, check if the result is what you want:'
grep Sum $decodedir/score_*/*.sys | sed 's:  \+:  :g'  # for check

#grep Sum $decodedir/score_*/*.raw | grep -P -o '\d+  \d+ \| [^\|]+ \|$' | grep -P -o '^\d+'
#grep Sum exp/tri5/decode_evalpart1.seg/score_*/*.raw | grep -P -o '\d+  \d+ \| [^\|]+ \|$' | grep -P -o '^\d+'

