#!/bin/bash

dir=$1
min=$2
max=$3
metric=$4

set -e

echo "ARG_NAME	$metric"
for i in `seq $min $max`; do
  d=${dir}$i
  if [ ! -d $d ]; then
    echo "Dir $d not exist"
    exit 1;
  fi
  echo $i"	"`cat $d/metrics.txt | grep -Po "(?<=$metric = )[\d\.]+"`
done

