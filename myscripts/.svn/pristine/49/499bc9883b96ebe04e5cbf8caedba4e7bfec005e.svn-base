#!/bin/bash

set -e
dir=$1
param=$2
if [ -z $param ]; then
  param=LMWT
fi
dirdir=`dirname $dir`
dirbase=`basename $dir`
min=`ls -l $dirdir | grep -Po "(?<= $dirbase)\d+" | sort | head -n 1`
max=`ls -l $dirdir | grep -Po "(?<= $dirbase)\d+" | sort | tail -n 1`
echo "min=$min"
echo "max=$max"
out=`czpScripts/plot/get-metric-points.sh $dir $min $max 'ATWV' | sed "1s/ARG_NAME/$param/"`
for m in {MTWV,OTWV,STWV,Recall}; do 
  out=`czpScripts/plot/get-metric-points.sh $dir $min $max $m | cut -f 2 | paste <(echo "$out") -`
#  out=`czpScripts/plot/get-metric-points.sh $dir $min $max $m`
done
tmp=`tempfile`
echo "$out" > $tmp
outfile=plots/all_metrics-`echo $dir | sed 's:/:-:g'`${min}_${max}.png
gnuplot << EOF
set terminal png size 400,300 enhanced 20
set xlabel '$param'
set ylabel 'Metric'
set output '$outfile'
plot for[col=2:4] "$tmp" using 1:col title columnheader(col) with linespoints
EOF
 
rm $tmp
#echo "$out" | gnuplot czpScripts/plot/all_metrics.lmwt.p > ${dir}.png

