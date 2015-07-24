#!/bin/bash

set -e
dir=$1
data=$2
param=$3
if [ -z $param ]; then
  param='Phone Count'
fi
lex=data/$data/kws_ive/L2_from_L1.lex
if [ ! -f $lex ]; then
  echo "$lex does not exist. Please run ive first"
  exit 1;
fi
if [ ! -f data/$data/kws_ive/kw_phone_count.txt ]; then
  cat data/$data/kws_ive/keywords_to_proc.txt | perl -e '
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
    }' > data/$data/kws_ive/kw_phone_count.txt 
fi
tmp=`tempfile`
cat $dir/bsum.txt | sed '1,18d' | sed '$d' | sed '$d' |\
  grep -f <(cut -f 1 data/$data/kws_ive/kw_phone_count.txt) |\
  grep -P '\.' | sed 's: *| *:	:g' | sed 's:^ *::' |\
  cut -f 1,7,9 | perl -e '
  open(CNT,"data/'$data'/kws_ive/kw_phone_count.txt") || die "cannot open phone count file\n";
  my %cnt;
  while (<CNT>) {
    chomp;
    my @col = split();
    $cnt{$col[0]} = $col[1];
  }
  my @s_r;
  my @s2_r;
  my @s_t;
  my @s2_t;
  my @num;
  my $totnum = 0;
  while (<STDIN>) {
    chomp;
    my @col = split();
    if (!defined($cnt{$col[0]})) {
      die "$col[0] not defined in phone count file\n"
    }
    my $c = $cnt{$col[0]};
    if (!defined($s_r[$c])) {
      $s_r[$c] = 0;
      $s2_r[$c] = 0;
      $s_t[$c] = 0;
      $s2_t[$c] = 0;
      $num[$c] = 0;
    }
    $s_r[$c] += 1 - $col[2];
    $s2_r[$c] += (1 - $col[2]) ** 2;
    $s_t[$c] += $col[1];
    $s2_t[$c] += $col[1] ** 2;
    $num[$c] ++;
    $totnum ++;
  }
  printf "%s\t%s\t%s\t%s\n", 
    "Phone_Count", "Num_of_kw", "mean_Recall", "mean_TWV";
  for (my $i=1; $i<@num; $i++) {
    if ($num[$i] > 0) {
      printf "%d\t%f", $i, $num[$i] / $totnum;
      my $mean_r = $s_r[$i] / $num[$i];
      my $stderr_r = ($s2_r[$i] / $num[$i] - ($mean_r) ** 2) ** 0.5;
      printf "\t%f", $mean_r; 
      my $mean_t = $s_t[$i] / $num[$i];
      my $stderr_t = ($s2_t[$i] / $num[$i] - ($mean_t) ** 2) ** 0.5;
      printf "\t%f", $mean_t;
      printf "\n";
    }
  }' > $tmp
cat $tmp
outfile=plots/avg_metrics-len-`echo $dir | sed 's:/:-:g'`.png
gnuplot << EOF
set terminal png size 600,400 enhanced 20
set xlabel columnheader(1)
set ylabel 'Metric'
set output '$outfile'
plot for[col=2:4] "$tmp" using 1:col title columnheader(col) with linespoints
EOF
 
rm $tmp
#echo "$out" | gnuplot czpScripts/plot/all_metrics.lmwt.p > ${dir}.png

