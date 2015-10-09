#!/bin/bash



echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 4 ]; then
   echo "usage: $0 [options] <rasr-cache-file> <utt-list-in-rasr-ark> <output-utt-list> <out-dir>";
fi
cache=$1
ulist_rasr=$2
out_ulist=$3
outdir=$4

for f in $cache $ulist_rasr; do
  if [ ! -f $f ]; then
    echo "File $f does not exist"
    exit 1;
  fi
done

if [ -f $out_ulist ]; then
  rm $out_ulist
fi

mkdir -p $outdir
for key in `cat $ulist_rasr`; do
  basename $key >> $out_ulist
  outfile=$outdir/`basename $key`
  archiver --mode show --type feat $cache $key |\
    sed '1,2d' | sed '$d' \
    > ${outfile}.raw
  if [ `awk '{print NF;}' ${outfile}.raw | sort -u | wc -l` -ne 1 ]; then
    echo "Find mismatch column number."
    exit 1;
  fi
  frame_dur=`head -n 1 ${outfile}.raw | awk '{print $2-$1}'`
  last_dur=`tail -n 1 ${outfile}.raw | awk '{print $2-$1}'`
  if [ $last_dur != $frame_dur ]; then
    sed '$d' ${outfile}.raw 
  else
    cat ${outfile}.raw
  fi | cut -d' ' -f 3- | sed '1s/^/[ /' | sed '$ a]' > ${outfile}
done

