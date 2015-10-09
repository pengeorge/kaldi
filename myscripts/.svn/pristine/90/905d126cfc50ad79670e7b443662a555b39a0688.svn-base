#!/bin/bash

set -e;
#set -x;

x=p
. utils/parse_options.sh

outfile=$1
col=$2
f1=$3
f2=$4
if [ -z $x ] || [ $x == p ]; then
  param='Number of Proxies'
elif [ $x == l ]; then
  param='{/Symbol l}'
fi


if [ $# -ne 4 ]; then
  echo "Usage: $(basename $0) <outfile> <col-num> <dat file 1> <dat file 2>"
  exit 1
fi

if [[ $id =~ oov ]]; then
  scale=`perl -e 'print 1309/19;'`
else
  scale=`perl -e 'print 1309/1290;'`
fi


xmin=0
xmax=300
key_x=215
if [ "$col" == 4 ]; then
  ymin=0.50  #0.39
  ymax=0.56  #0.50
  key_y=0.51     #0.485
  ylabel=OTWV
elif [ "$col" == 2 ]; then
  ymin=0.39
  ymax=0.50
  key_y=0.483
  ylabel=ATWV
fi

f1_filt=`tempfile`
f2_filt=`tempfile`
tmp=`tempfile`
grep -f <(cut $f2 -f 1 | sed 's:^:\^:' | sed 's:$:	:') $f1 > $f1_filt
grep -f <(cut $f1_filt -f 1 | sed 's:^:\^:' | sed 's:$:	:') $f2 > $f2_filt
cut -f 1,$col $f1_filt | paste - <(cut -f $col $f2_filt) > $tmp

cat $tmp

gnuplot << EOF
set terminal postscript eps size 3.5,2.1 solid color linewidth 2 enh\
  font 'Helvetica,16'
set xlabel "$param"
set ylabel "$ylabel"
#set logscale x
set xrange [$xmin:$xmax]
set yrange [$ymin:$ymax]
#set key box spacing 1.2 center at $key_x,$key_y height 1
set key box spacing 1.2 center right bottom height 1
set output '$outfile'
#plot for[col=2:$colnum] "$tmp" using 1:col title columnheader(col) with linespoints linewidth 2 pointsize 2 pt col
plot "$tmp" using 1:2 title "Prob Model" with linespoints pt 82 linewidth 2 pointsize 1, \
     "$tmp" using 1:3 title "Non-prob Model" with linespoints pt 8 linewidth 2 pointsize 1
EOF
 
rm $f1_filt
rm $f2_filt
rm $tmp
#echo "$out" | gnuplot czpScripts/plot/all_metrics.lmwt.p > ${dir}.png

