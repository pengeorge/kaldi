#!/bin/bash

. ./path.sh

#lm=$1

#while read line; do
#  echo `echo "$line" | cut -f 1`"	"`ngram -order 3 -lm $lm -unk -ppl <(echo "$line" | cut -f 2-) | sed -n '2p' | cut -f 4,6,8 -d' '`
#done

src=bbnucoluc100w5
lmdir=./data/srilm_kn
srclm_flag=kn

. ./utils/parse_options.sh

if [ ! -f ${lmdir}/lm.arpa ]; then
  gzip -cdf ${lmdir}/lm.gz > ${lmdir}/lm.arpa
fi

for mode in 1 ; do
  expdir=data/extra_text/${srclm_flag}.${src}
  mkdir -p $expdir
  if [ ! -f $expdir/${src}.sw.mode${mode}.sorted.gz ]; then
    if [ ! -f $expdir/.done.dirprepare ]; then
      cp data/extra_text/VLLP $expdir/in_text
      cp ${lmdir}/lm.gz $expdir/in_lm.gz
      echo "in_text from: data/extra_text/VLLP" > $expdir/note.txt
      echo "in_lm from: ${lmdir}/lm.gz" >> $expdir/note.txt
      touch $expdir/.done.dirprepare
    fi
    pushd $expdir
    XenC -m ${mode} -s sw --mono -i in_text -o ../${src} --in-slm in_lm.gz --to-lower true --bin-lm 0
    popd
  fi
done
