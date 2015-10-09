#!/bin/bash

decodedir=$1

time=0
nj=0
for f in $decodedir/log/decode.*.log; do
  nj=$[nj+1]
  time=$[$time + `tail -n 2 $f | head -n 1 | cut -d' ' -f 3 | sed 's/time=//'`]
done
echo "Total time is $time seconds. $nj jobs."
