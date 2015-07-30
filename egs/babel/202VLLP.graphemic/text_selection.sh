#!/bin/bash
set -e

src=bbnucoluc100w5
lmdir=./data/srilm_kn
srclm_flag=kn
filter_by=ratio # score

. ./utils/parse_options.sh

if [ ! -f ${lmdir}/lm.arpa ]; then
  gzip -cdf ${lmdir}/lm.gz > ${lmdir}/lm.arpa
fi

for mode in 1 2; do
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
  echo
  echo

  for s in 48; do
    new_ext=${src}x${srclm_flag}m${mode}
    if [ $filter_by == ratio ]; then
      new_ext=${new_ext}r0${s}
      lineNum=`gzip -cdf $expdir/${src}.sw.mode${mode}.sorted.gz | wc -l`
      echo "lineNum=$lineNum"
      keepNum=$(perl -e 'printf("%d",'$lineNum'*0.'$s');')
      echo "will keep $keepNum"
      gzip -cdf ${expdir}/${src}.sw.mode${mode}.sorted.gz | head -n $keepNum | cut -f2- > data/extra_text/${new_ext}
    elif [ $filter_by == score ]; then
      new_ext=${new_ext}s0${s}
      gzip -cdf ${expdir}/${src}.sw.mode${mode}.sorted.gz | awk '{if ($1 <= thres) print $0;}' thres=0.$s > data/extra_text/${new_ext}
    fi

    ./czpScripts/prep_lex/filter_lexicon_by_text.sh \
      data/extra_text/${new_ext} data/extra_lexicon/${src} data/extra_lexicon/${new_ext}
  done
done
