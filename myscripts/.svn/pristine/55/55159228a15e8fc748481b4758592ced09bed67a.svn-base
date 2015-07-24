#!/bin/bash

# Copyright 2014  Brno University of Technology (Author: Karel Vesely)
# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0
# This script appends the features in two or more data directories.

# To be run from .. (one directory up from here)
# see ../run.sh for example

# Begin configuration section.
cmd=run.pl
nj=4
length_tolerance=10 # length tolerance in frames (trim to shortest)
compress=true
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# -lt 5 ]; then
   echo "usage: $0 [options] <src-data-dir1> <src-data-dir2> [<src-data-dirN>] <dest-data-dir> <log-dir> <path-to-storage-dir>";
   echo "e.g.: $0 data/train_mfcc data/train_bottleneck data/train_combined exp/append_mfcc_plp mfcc"
   echo "options: "
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   exit 1;
fi

declare -A data_src_arr
for ((i=0; i<$#-3; i++)); do
  eval data_src_arr[$i]=\$$[$i+1]
done
#data_src_arr=(${@:1:$(($#-3))}) #array of source data-dirs. (This would split by space)
data=${@: -3: 1}
logdir=${@: -2: 1}
ark_dir=${@: -1: 1} #last arg.

# make $ark_dir an absolute pathname.
ark_dir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $ark_dir ${PWD}`

mkdir -p $ark_dir $logdir

mkdir -p $data 
rm $data/cmvn.scp 2>/dev/null 
rm $data/feats.scp 2>/dev/null 

# use "name" as part of name of the archive.
name=`basename $data`

# get list of source scp's for pasting
data_src_args=
for ((i=0; i<$#-3; i++)); do
#for data_src in "${data_src_arr[@]}"; do
  echo "feat $i: ${data_src_arr[$i]}"
  data_src_args="$data_src_args \"${data_src_arr[$i]}\""
done

$cmd JOB=1:$nj $logdir/append.JOB.log \
   paste-feats --length-tolerance=$length_tolerance $data_src_args ark:- \| \
   copy-feats --compress=$compress ark:- \
    ark,scp:$ark_dir/pasted_$name.JOB.ark,$ark_dir/pasted_$name.JOB.scp || exit 1;
              
# concatenate the .scp files together.
for ((n=1; n<=nj; n++)); do
  cat $ark_dir/pasted_$name.$n.scp >> $data/feats.scp || exit 1;
done > $data/feats.scp || exit 1;


nf=`cat $data/feats.scp | wc -l` 
nu=`cat $data/utt2spk | wc -l` 
if [ $nf -ne $nu ]; then
  echo "It seems not all of the feature files were successfully processed ($nf != $nu);"
  echo "consider using utils/fix_data_dir.sh $data"
fi

echo "Succeeded pasting features for $name into $data"
