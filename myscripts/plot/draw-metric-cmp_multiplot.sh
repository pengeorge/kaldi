#!/bin/bash

set -e;
#set -x;

x=p
. utils/parse_options.sh

outfile=$1
col1=$2
col2=$3
f1=$4
f2=$5
if [ -z $x ] || [ $x == p ]; then
  param='Number of Proxies'
elif [ $x == l ]; then
  param='{/Symbol l}'
fi


if [ $# -ne 5 ]; then
  echo "Usage: $(basename $0) <outfile> <col-num1> <col-num2> <dat file 1> <dat file 2>"
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
for k in 1 2; do
  eval col=\$col$k
  if [ "$col" == 4 ]; then
    eval ymin$k=0.50  #0.39
    eval ymax$k=0.56  #0.50
    #eval key_y$k=0.51     #0.485
    eval ylabel$k=OTWV
  elif [ "$col" == 2 ]; then
    eval ymin$k=0.39
    eval ymax$k=0.47
    #eval key_y$k=0.483
    eval ylabel$k=ATWV
  fi
done

f1_filt=`tempfile`
f2_filt=`tempfile`
tmp=`tempfile`
grep -f <(cut $f2 -f 1 | sed 's:^:\^:' | sed 's:$:	:') $f1 > $f1_filt
grep -f <(cut $f1_filt -f 1 | sed 's:^:\^:' | sed 's:$:	:') $f2 > $f2_filt
cut -f 1,$col1,$col2 $f1_filt | paste - <(cut -f $col1,$col2 $f2_filt) > $tmp

cat $tmp

gnuplot << EOF
set terminal postscript eps size 3.5,2.6 solid color linewidth 2 enh\
  font 'Arial,16'
set output '$outfile'
set xrange [$xmin:$xmax];
set multiplot
set size 1.0,0.5;
set origin 0.0,0.5;
set nokey
set xlabel "$param";
set ylabel "$ylabel1";
set yrange [$ymin1:$ymax1];
#set key box spacing 1.2 center at $key_x,$key_y height 1
#set key box spacing 1.2 center right bottom height 1;
#plot for[col=2:$colnum] "$tmp" using 1:col title columnheader(col) with linespoints linewidth 2 pointsize 2 pt col
plot "$tmp" using 1:2 title "Prob" with linespoints pt 82 linewidth 2 pointsize 1, \
     "$tmp" using 1:4 title "Non-prob" with linespoints pt 8 linewidth 2 pointsize 1;
set origin 0.0,0.0;
set xlabel "$param";
set ylabel "$ylabel2";
set yrange [$ymin2:$ymax2];
set key nobox spacing 1.2 right bottom height 1;
plot "$tmp" using 1:3 title "Prob" with linespoints pt 82 linewidth 2 pointsize 1, \
     "$tmp" using 1:5 title "Non-prob" with linespoints pt 8 linewidth 2 pointsize 1
unset multiplot
EOF
 
rm $f1_filt
rm $f2_filt
rm $tmp
#echo "$out" | gnuplot czpScripts/plot/all_metrics.lmwt.p > ${dir}.png

