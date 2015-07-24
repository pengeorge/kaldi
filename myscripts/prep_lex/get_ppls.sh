#!/bin/bash

for d in data/srilm*; do
  if sed -n '1p' $d/perp* | grep -P '^file' >/dev/null; then
    echo "$d/lm.gz "`sed -n '1p' $d/perp* | grep -Po '(\d+)\s+OOVs'`" "`sed -n '2p' $d/perp* | sed 's/  \+/ /g'`
  else
    cat $d/perp* | head -n 1 | sed 's/file .* words,//' | sed 's/  \+/ /g'
  fi
done | sort -k11 -n
