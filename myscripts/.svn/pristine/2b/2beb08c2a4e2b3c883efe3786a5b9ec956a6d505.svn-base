#!/bin/bash

extra=
. ./utils/parse_options.sh 
dir=$1

if [ ! -z "$extra" ]; then
  extra_flag="--extra $extra"
fi

getScoreCSV.sh --kws-only true $extra_flag $dir -  all
for m in {,W_}{p,}{SUM,MNZ}; do
  if [ ! -d $dir/comb-$m ]; then
    continue;
  fi
  if [[ $m =~ p ]]; then
    param=all
  else
    param=1
  fi
  getScoreCSV.sh --kws-only true $extra_flag $dir comb-$m $param
done
