#!/bin/bash

set -e;
#set -x;

type=am  # am/os/all
x=p  # p/l
xmin=
xmax=
key_x=
key_y=

. utils/parse_options.sh

dir=$1
param=$2
if [ -z $param ]; then
  if [ -z $x ] || [ $x == p ]; then
    param='Number of Proxies'
  elif [ $x == l ]; then
    param='{/Symbol l}'
  fi
fi 


if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: $(basename $0) <kws-dir> <X-axix param>"
  exit 1
fi

id=`basename $dir`
remain=`dirname $dir`
while [[ ! $id =~ kws ]]; do
  id=`basename $remain`-$id
  remain=`dirname $remain`
done
if [[ $id =~ oov ]]; then
  scale=`perl -e 'print 1309/19;'`
else
  scale=`perl -e 'print 1309/1290;'`
fi

outfile=plots/metrics-nbest_${id}_${type}.eps

former=`echo $dir | grep -Po '^.*(?=PARAM)'`
latter=`echo $dir | grep -Po '(?<=PARAM).*$'`

echo "outfile is $outfile"
echo "former is $former"
echo "latter is $latter"

tmp=`tempfile`
if [ $type == "am" ]; then
  echo "x	ATWV	MTWV" >> $tmp
  colnum=3
elif [ $type == "os" ]; then
  echo "x	OTWV	STWV" >> $tmp
  colnum=3
elif [ $type == "ao" ]; then
  echo "x	ATWV	OTWV" >> $tmp
  colnum=3
elif [ $type == "all" ]; then
  echo "x	ATWV	MTWV	OTWV	STWV" >> $tmp
  colnum=5
fi
for d in ${former}*${latter}; do
  if [ ! -f $d/metrics.txt ]; then
    echo "[WARNING] metrics.txt not found for $d, still in scoring?"
    continue;
  fi
  p=`echo $d | grep -Po "(?<=${former}).*(?=${latter})"`
  if [ $x == 'l' ]; then
    p=`echo $p | sed 's:-t$::'`
    if [ $p == '0.0' ]; then
      p=0.0001
      #continue
    elif [ $p == '1.0' ]; then
      p=0.9999
      #continue
    fi
  fi
  a=`cat $d/metrics.txt | grep -Po '(?<=ATWV \= )[\d\.]+$' | perl -e '$s=<>; print $s*'$scale'; '`
  m=`cat $d/metrics.txt | grep -Po '(?<=MTWV \= )[\d\.]+(?=,)' | perl -e '$s=<>; print $s*'$scale'; '`
  o=`cat $d/metrics.txt | grep -Po '(?<=OTWV \= )[\d\.]+$' | perl -e '$s=<>; print $s*'$scale'; '`
  s=`cat $d/metrics.txt | grep -Po '(?<=STWV \= )[\d\.]+$' | perl -e '$s=<>; print $s*'$scale'; '`
  if [ $type == "am" ]; then
    echo "$p	$a	$m" >> $tmp
  elif [ $type == "ao" ]; then
    echo "$p	$a	$o" >> $tmp
  elif [ $type == "os" ]; then
    echo "$p	$o	$s" >> $tmp
  elif [ $type == "all" ]; then
    echo "$p	$a	$m	$o	$s" >> $tmp
  fi
done

tmp2=`tempfile`
head -n 1 $tmp > $tmp2
cat $tmp | sed '1d' | sort -n -k 1 >> $tmp2

cat $tmp2

if [ $x == 'l' ]; then
  xmax=1.03
  xmin=-0.03
elif [ $x == 'p' ]; then
  xmin=1
  xmax=`tail -n 1 $tmp2 | cut -f 1`
fi

if [ ! -z $xmin ] && [ ! -z $xmax ]; then
  xrange_line="set xrange [$xmin:$xmax]"
fi
if [ ! -z $key_x ] && [ ! -z $key_y ]; then
  key_line="set key box spacing 1.2 center at $key_x,$key_y width 2.8 height 1"
fi
gnuplot << EOF
set terminal postscript eps size 3.5,2.1 solid color linewidth 2 enh\
  font 'Helvetica,16'
set xlabel "$param"
set ylabel "TWV"
#set logscale x
#set logscale y
$xrange_line
$key_line
set output '$outfile'
#plot for[col=2:$colnum] "$tmp2" using 1:col title columnheader(col) with linespoints linewidth 2 pointsize 2 pt col
plot "$tmp2" using 1:2 title columnheader(2) with linespoints pt 82 linewidth 2 pointsize 1, \
     "$tmp2" using 1:3 title columnheader(3) with linespoints pt 8 linewidth 2 pointsize 1
EOF
 
rm $tmp2
rm $tmp
#echo "$out" | gnuplot czpScripts/plot/all_metrics.lmwt.p > ${dir}.png

