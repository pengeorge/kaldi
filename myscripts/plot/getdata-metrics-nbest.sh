#!/bin/bash

set -e;
#set -x;

x=p  # p/l

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

outfile=paperfigure/metrics-nbest_${id}_${type}.txt

former=`echo $dir | grep -Po '^.*(?=PARAM)'`
latter=`echo $dir | grep -Po '(?<=PARAM).*$'`

echo "outfile is $outfile"
echo "former is $former"
echo "latter is $latter"

tmp=`tempfile`
echo "$x	ATWV	MTWV	OTWV	STWV" >> $tmp
colnum=5
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
  echo "$p	$a	$m	$o	$s" >> $tmp
done

tmp2=`tempfile`
head -n 1 $tmp > $outfile
cat $tmp | sed '1d' | sort -n -k 1 >> $outfile

