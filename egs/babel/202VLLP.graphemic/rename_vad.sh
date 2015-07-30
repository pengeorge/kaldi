#/bin/bash

prefix=toRm.
no_training=false

. ./utils/parse_options.sh

if ! $no_training; then
  for f in data/train_seg exp/make_plp/train_seg exp/make_plp_pitch/train_seg \
            exp/tri4b_seg exp/tri4_train_seg_ali; do
    mv $f `dirname $f`/${prefix}`basename $f`
  done
  rm plp/*train_seg*
fi

for f in exp/make_seg exp/*/decode_dev10h.seg* exp/*/decode_eval.seg* \
         data/dev10h.seg* data/eval.seg*; do
  mv $f `dirname $f`/${prefix}`basename $f`
done

rm plp/*dev10h.seg* plp/*eval.seg*
