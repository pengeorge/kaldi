#!/bin/bash

# Copyright 2012  Johns Hopkins University (Author: Guoguo Chen, Yenda Trmal)
# Apache 2.0.


help_message="$(basename $0): do keyword indexing and search.  data-dir is assumed to have
                 kws/ subdirectory that specifies the terms to search for.  Output is in
                 decode-dir/kws/
             Usage:
                 $(basename $0) <lang-dir> <data-dir> <decode-dir>"

# Begin configuration section.  
#acwt=0.0909091
min_lmwt=7
max_lmwt=17
cmd=run.pl
model=
skip_optimization=false # true can speed it up if #keywords is small.
max_states=150000
indices_dir=
word_ins_penalty=0
silence_word=  # specify this if you did to in kws_setup.sh, it's more accurate.
max_silence_frames=50


# End configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

set -u
set -e
set -o pipefail


if [[ "$#" -ne "3" ]] ; then
    echo -e "$0: FATAL: wrong number of script parameters!\n\n"
    printf "$help_message\n\n"
    exit 1;
fi

silence_opt=

langdir=$1
datadir=$2
decodedir=$3

if [ -z $indices_dir ]; then
  indices_dir=$decodedir/kws_indices
fi

for d in "$datadir" "$langdir" "$decodedir"; do
  if [ ! -d "$d" ]; then
    echo "$0: FATAL: expected directory $d to exist"
    exit 1;
  fi
done

if [ ! -z "$model" ]; then
    model_flags="--model $model"
else
    model_flags=
fi
  

if [ ! -f $indices_dir/.done.index ] ; then
  [ ! -d $indices_dir ] && mkdir  $indices_dir
  for lmwt in `seq $min_lmwt $max_lmwt` ; do
      indices=${indices_dir}_$lmwt
      mkdir -p $indices

      acwt=`perl -e "print (1.0/$lmwt);"` 
      [ ! -z $silence_word ] && silence_opt="--silence-word $silence_word"
      czpScripts/kws/make_index.chenzp.sh $silence_opt --cmd "$cmd" --acwt $acwt $model_flags\
        --skip-optimization $skip_optimization --max-states $max_states \
        --word-ins-penalty $word_ins_penalty --max-silence-frames $max_silence_frames\
        $datadir $langdir $decodedir $indices  || exit 1
  done
  touch $indices_dir/.done.index
else
  echo "Assuming indexing has been aready done. If you really need to re-run "
  echo "the indexing again, delete the file $indices_dir/.done.index"
fi

exit 0
