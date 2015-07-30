#!/bin/bash
set -e;
old=$1
new=$2

if [ -z $old ] || [ -z $new ]; then
  echo "usage: $0 old new"
  exit 1;
fi

if [ -f data/extra_lexicon/$new ] || [ -f data/extra_text/$new ]; then
  echo "$new exist. Rename failed"
  exit 1;
fi

mv data/extra_lexicon/$old data/extra_lexicon/$new
mv data/extra_text/$old data/extra_text/$new

for t in srilm lang local; do
  if [ -d data/${t}_${old} ]; then
    mv data/${t}_${old} data/${t}_${new}
  fi
done
for t in mkgraph_EXT.log decode_dev10h.pem_EXT.si decode_dev10h.pem_EXT graph_EXT; do
  old_name=`echo $t | sed 's/EXT/'$old'/g'`
  new_name=`echo $t | sed 's/EXT/'$new'/g'`
  mv exp/tri5/$old_name exp/tri5/$new_name
done
echo Done
