#!/bin/bash
#set -e

#for d in `find ./data/ -name 'srilm_*'`; do
#  ext=`echo $d | sed 's/^.*_\([^_]*\)$/\1/'`
for f in data/extra_lexicon/*; do
  ext=`basename $f`
  if [[ $ext =~ OL$ ]]; then
    echo "Renaming $ext......................."
    new='+'`echo $ext | sed 's/OL$//'`
    ./rename_ext.sh $ext $new
  fi
done 



