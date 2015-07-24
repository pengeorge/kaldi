#!/bin/bash

set -e

if [ $# != 3 ]; then
  echo "Usage: $0 <word-list> <phone-lm> <outfile>"
  exit 1
fi
wlist=$1
phonelm=$2
out=$3

./czpScripts/ext_lex/calc_word_ppl.sh $wlist $phonelm |\
  cut -f 1,3 > $out
