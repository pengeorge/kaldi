#!/bin/bash

subdir=$1
for dir in exp/*/decode*; do
  getScoreCSV.sh $dir 2>/dev/null || echo "[WARNING] Getting score CSV from $dir failed."
  echo ''
  if [ ! -z $subdir ]; then
    for sdir in $dir/$subdir; do
      getScoreCSV.sh `dirname $sdir` `basename $sdir` 2>/dev/null || echo "[WARNING] Getting score CSV from $sdir failed."
      echo ''
    done
  fi
done
