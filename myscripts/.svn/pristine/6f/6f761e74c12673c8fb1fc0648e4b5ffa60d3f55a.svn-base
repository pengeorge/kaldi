#!/bin/bash

set -e;
type=base  # iv/ive/both
ive_type=ive

. utils/parse_options.sh

dir=$1
data=$2
param=$3
if [ -z $param ]; then
  param='Phone Count'
fi

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $(basename $0) <kws-dir> <data-type> <X-axix param>"
  exit 1
fi

if [ ! -z "`basename $dir | grep oov`" ]; then
  pre=oov_
fi
if [ -z "$pre" ]; then
  lex=data/$data/kws_${ive_type}/L2_from_L1.lex
else
  lex=data/$data/oov_kws/tmp/L2.lex
fi
if [ ! -f $lex ]; then
  echo "$lex does not exist."
  lex=`echo $lex | sed 's:kws:proxy:' | sed 's:ive\-::' | sed 's:\-[^\-]\+\-[^\-]\+/:/:'`
  if [ ! -f $lex ]; then
    echo "$lex does not exist either. Please run ive/oov first."
    exit 1;
  fi
fi
proxy_dir=`dirname $lex`

#pc_file=data/$data/${pre}kws_${ive_type}/kw_phone_count.txt
pc_file=$proxy_dir/kw_phone_count.txt
if [ ! -f $pc_file ]; then
  echo "Generating kw_phone_count.txt"
#  cat data/$data/${pre}kws_${ive_type}/keywords_to_proc.txt | perl -e '
  cat $proxy_dir/keywords_to_proc.txt | perl -e '
    open(W, "<'$lex'") || die "Fail to open lexicon: '$lex'\n";
    my %lexicon;
    while (<W>) {
      chomp;
      my @col = split();
      @col >= 2 || die "'$0': Bad line in lexicon: $_\n";
      $lexicon{$col[0]} = scalar(@col)-2;
    }
    while (<STDIN>) {
      chomp;
      my $line = $_;
      my @col = split();
      @col >= 2 || die "Bad line in keywords file: $_\n";
      my $len = 0;
      for (my $i = 1; $i < scalar(@col); $i ++) {
        if (defined($lexicon{$col[$i]})) {
          $len += $lexicon{$col[$i]};
        } else {
          die "'$0': No pronunciation found for word: $col[$i]\n";
        }
      }
      print "$col[0]\t$len\n"
    }' > $pc_file 
fi


if [ "$type" == "base" ] || [ "$type" == "both" ]; then
  tmp1=`tempfile`
  duration=`cat $dir/bsum.txt | sed -n '9p' | grep -Po '[\d\.]+'`
  echo "Calculating metrics..."
  cat $dir/bsum.txt | sed '1,18d' | sed '$d' | sed '$d' |\
    grep -f <(cut -f 1 $pc_file) |\
    grep -P '\.' | sed 's: *| *:	:g' | sed 's:^Keyword::' | sed 's:^ *::' |\
    cut -f 1,7,9 | perl czpScripts/plot/cal_metrics_by_len.pl $pc_file $dir/alignment.csv $duration |\
    cut -f 1-8 > $tmp1
fi
if [ "$type" == "expand" ] || [ "$type" == "both" ]; then
  tmp2=`tempfile`
  echo "Calculating IV expansion metrics..."
  ive_dir=`echo $dir | sed "s:kws_:kws_${ive_type}_:"`
  duration=`cat $ive_dir/bsum.txt | sed -n '9p' | grep -Po '[\d\.]+'`
  cat $ive_dir/bsum.txt | sed '1,18d' | sed '$d' | sed '$d' |\
    grep -f <(cut -f 1 $pc_file) |\
    grep -P '\.' | sed 's: *| *:	:g' | sed 's:^Keyword::' | sed 's:^ *::' |\
    cut -f 1,7,9 | perl czpScripts/plot/cal_metrics_by_len.pl $pc_file $ive_dir/alignment.csv $duration |\
    sed '1s:	:_ive	:g' | sed '1s:$:_ive:' |\
    cut -f 1-8 > $tmp2
fi
if [ "$type" == "both" ]; then
  tmp=`tempfile`
  cut -f 4-8 $tmp2 | paste $tmp1 - > $tmp
  cat $tmp
  outfile=plots/avg_metrics-len-`echo $dir | sed 's:/:-:g'`.png
  col=13
elif [ "$type" == "base" ]; then
  tmp=$tmp1
  cat $tmp
  outfile=plots/avg_metrics-len-`echo $dir | sed 's:/:-:g'`-base.png
  col=8
elif [ "$type" == "expand" ]; then
  tmp=$tmp2
  cat $tmp
  outfile=plots/avg_metrics-len-`echo $dir | sed 's:/:-:g'`-expand-${ive_type}.png
  col=8
fi

gnuplot << EOF
set terminal png size 640,480 enhanced 20
set xlabel 'Phone Count'
set xrange [2:20]
set yrange [0:1]
set ylabel 'Metric'
set output '$outfile'
plot for[col=2:$col] "$tmp" using 1:col title columnheader(col) with linespoints
EOF
 
rm $tmp
rm $tmp1
rm $tmp2
#echo "$out" | gnuplot czpScripts/plot/all_metrics.lmwt.p > ${dir}.png

