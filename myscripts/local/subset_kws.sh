#!/bin/bash

set -e
set -o pipefail

outdir=
use_raw=true

. utils/parse_options.sh

if [ $# -ne 3 ]; then
  echo "Usage: `basename $0` <subset-id> <data-dir> <kws-dir>"
  exit 1;
fi

subsetid=$1
datadir=$2
kwsdir=$3

subsettype=${subsetid##*.}
if [ -z $outdir ]; then
  outdir=$kwsdir/$subsettype
fi

if [ ! -d $outdir ]; then
  mkdir -p $outdir
fi

echo "$subsetid: Filtering subset"

#if [ ! -f $datadir/subsets/$subsettype.txt ]; then
#  grep -Po '(?<=<kw kwid=")[^"]+(?=">)' $datadir/subsets/$subsettype.xml > $datadir/subsets/$subsettype.txt
#fi
#grep -h -f <(cat $datadir/subsets/$subsettype.txt) $kwsdir/result.*  > $kwsdir/$subsettype/result
  
if $use_raw; then
  if [ ! -f $kwsdir/result.1 ]; then
    echo "[ERROR] $kwsdir/result.* should exist when 'use_raw' is set to true."
    exit 1;
  fi
  grep -h -f <(grep -Po '(?<=<kw kwid=")[^"]+(?=">)' $datadir/subsets/$subsetid.xml) $kwsdir/result.*  > $outdir/result
  line=`cat $outdir/result|wc -l`
  echo "grep return $?. result has $line lines."
  if [ $line -eq 0 ]; then
    exit 1;
  else
    exit 0;
  fi
else
  for kws in {'','.unnormalized'}; do
    if [ ! -f $kwsdir/kwslist$kws.xml ]; then
      echo "[WARNING] $kwsdir/kwslist$kws.xml doesn't exist, skip."
      continue
    fi
    grep -Po '(?<=<kw kwid=")[^"]+(?=">)' $datadir/subsets/$subsetid.xml |\
    perl -e '
      %insubset = ();
      while (<STDIN>) {
        chomp;
        $insubset{$_} = 1;
      }
      $kw = "";
      $insubset{$kw} = 1;
      open(KWS, "'$kwsdir/kwslist$kws.xml'") or die "cannot open kwslist file\n";
      while (my $line = <KWS>) {
        chomp($line);
        if ($line =~ m/detected_kwlist.*kwid="([^"]+)"/) {
          $kw = $1;
        }
        if ($insubset{$kw} == 1) {
          print "$line\n";
        }
        if ($line =~ /<\/detected_kwlist>/) {
          $kw = "";
        }
      }' > $outdir/kwslist$kws.xml
  done
fi
if [ ! -f $outdir/kwslist.xml ] && [ ! -f $outdir/kwslist.unnormalized.xml ]; then
  echo "[ERROR] Both kwslist.xml and kwslist.unnormalized.xml not exist"
  exit 1;
fi
#grep -Pf <(grep -Po '(?<=<kw kwid=")[^"]+(?=">)' $datadir/subsets/$subsettype.xml | awk '{print "^"$0}') $kwsdir/result.*  > $kwsdir/$subsettype/result 
