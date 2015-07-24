#!/bin/bash

ml=false
dir=
every=100

. utils/parse_options.sh 

if [ -z "$dir" ]; then
  exit 1;
fi

if ! $ml; then
  pushd $dir
  num_iters=`ls | sed 's/\.mdl//' | grep -P '^\d+$' | sort -r -n|head -n 1`
  for x in `seq 0 $num_iters`; do
    if [ $[$x%$every] -ne 0 ] && [ $x -ne $num_iters ] && [ -f $x.mdl ]; then
      # delete all but every 100th model; don't delete the ones which combine to form t
      echo $dir/$x.mdl
      rm $x.mdl
    fi
  done
  popd
else
  pushd $dir
  for lang in `ls | grep -P '^\d+$' | sort -n`; do
    pushd $lang
    num_iters=`ls | sed 's/\.mdl//' | grep -P '^\d+$' | sort -r -n|head -n 1`
    for x in `seq 0 $num_iters`; do
      if [ $[$x%$every] -ne 0 ] && [ $x -ne $num_iters ] && [ -f $x.mdl ]; then
        # delete all but every 100th model; don't delete the ones which combine to form t
        echo $dir/$lang/$x.mdl
        rm $x.mdl
      fi
    done
    popd
  done
  popd
fi
