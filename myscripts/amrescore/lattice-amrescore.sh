#!/bin/bash

set -e 
set -u

# Tune AM scores on lattices using phonetic confusion model.
# Only for the WSJ recipe.
# Copyright 2015  Tsinghua University (Author: Zhipeng Chen)
# Apache 2.0

# Begin configuration section.
nj=30
acwt=15  # used in lattice-amrescore for picking shortest paths
n=1000     # maximum number of paths to retain
beam=5
count_cutoff=1

skip_scoring=false
scoring_opts=
# End configuration section.

echo "$0 $@"  # Print the command line for logging

. cmd.sh
[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

if [ $# != 5 ]; then
    echo "Usage: $0 <lang-dir> <graph-dir> <dev-data-dir> <test-data-dir> <test-data-decode-dir>"
    echo "e.g. $0 data/lang exp/tri4b/graph data/dev data/test exp/tri4b/decode_test"
    exit 1;
fi

langdir=$1; shift
graphdir=$1; shift
devdatadir=$1; shift
testdatadir=$1; shift
decodedir=$1; shift

modeldir=$(dirname $decodedir)
model=$(basename $modeldir)

# Decode dev data
decode_script=steps/decode.sh
case $model in
  mono*|tri1*|tri2*) decode_script=steps/decode.sh;;
  tri3*|tri4*) decode_script=steps/decode_fmllr.sh;;
esac
   
dev=$(basename $devdatadir)
graph_suffix=${graphdir##*graph}
dev_decodedir=$modeldir/decode${graph_suffix}_$dev
if ! [[ $(basename $decodedir) =~ ^decode${graph_suffix}_ ]]; then
  echo "WARNING: test data decoding dir '$decodedir' is not consistent with graph dir '$graphdir'"
fi

if [ ! -f $dev_decodedir/.done ]; then
  echo "STEP: decode dev data $devdatadir"
  $decode_script --nj $nj --cmd "$decode_cmd" \
    $graphdir $devdatadir \
    $dev_decodedir || exit 1;
  touch $dev_decodedir/.done
fi

# Force align dev data
align_script=steps/align_si.sh
alidir=${modeldir}_ali_${dev}

case $model in
  mono|tri1*|tri2*)
    align_script=steps/align_si.sh
    align_opts="--boost-silence 1.25"
    ;;
  tri3*|tri4*)
    align_script=steps/align_fmllr.sh
    align_opts=
    ;;
esac

if [ ! -f $alidir/.done ]; then
  echo "STEP: force align dev data with model $model"
  $align_script $align_opts --nj $nj --cmd "$train_cmd" \
    $devdatadir $langdir $modeldir $alidir || exit 1;
  touch $alidir/.done
fi

# Generate lexicon FST
L_dir=$langdir/L_for_conf_mat
if [ ! -f $L_dir/.done ] || [ ! -f $L_dir/L.fst ]; then
  echo "STEP: generate lexicon FST for lang $langdir"
  mkdir $L_dir
  lang_suffix=${langdir##*lang}
  lexiconp=data/local/lang_tmp${lang_suffix}/lexiconp.txt
  cp $langdir/words.txt $L_dir/words.txt
  cat $lexiconp | sed 's/\s/ /g' > $L_dir/L.tmp.lex

  cat $L_dir/L.tmp.lex | cut -d ' ' -f 1 |\
    paste -d ' ' - <(cat $L_dir/L.tmp.lex | cut -d ' ' -f 2-|\
      sed 's/[0-2]_[B|E|I|S]//g' | sed 's/_[B|E|I|S]//g' | sed 's/_[%|"]//g') |\
    awk '{if(NF>=2) {print $0}}' > $L_dir/L.lex

  ndisambig=`utils/add_lex_disambig.pl $L_dir/L.lex $L_dir/L_disambig.lex`
  ndisambig=$[$ndisambig+1]; # add one disambig symbol for silence in lexicon FST.
  ( for n in `seq 0 $ndisambig`; do echo '#'$n; done ) > $L_dir/disambig.txt

  cat $L_dir/L.lex |\
    awk '{for(i=3; i <= NF; i++) {print $i;}}' |\
    sort -u | sed '1i\<eps>' |\
    cat - $L_dir/disambig.txt | awk 'BEGIN{x=0} {print $0"\t"x; x++;}' \
    > $L_dir/phones.txt

  # Compiles lexicon into FST
  phone_disambig_symbol=`grep \#0 $L_dir/phones.txt | awk '{print $2}'`
  word_disambig_symbol=`grep \#0 $L_dir/words.txt | awk '{print $2}'`
  phone_disambig_symbols=`grep \# $L_dir/phones.txt |\
    awk '{print $2}' | tr "\n" " "`
  word_disambig_symbols=`grep \# $L_dir/words.txt |\
    awk '{print $2}' | tr "\n" " "`

  echo "phone_disambig_symbol=$phone_disambig_symbol"
  echo "phone_disambig_symbols=$phone_disambig_symbols"
  echo "word_disambig_symbol=$word_disambig_symbol"
  echo "word_disambig_symbols=$word_disambig_symbols"

  cat $L_dir/L_disambig.lex |\
    utils/make_lexicon_fst.pl --pron-probs - |\
    fstcompile --isymbols=$L_dir/phones.txt \
    --osymbols=$L_dir/words.txt - |\
    fstaddselfloops "echo $phone_disambig_symbol |" \
    "echo $word_disambig_symbol |" |\
    fstdeterminize | fstrmsymbols "echo $phone_disambig_symbols|" |\
    fstrmsymbols --remove-from-output=true "echo $word_disambig_symbols|" |\
    fstrmepsilon |\
    fstarcsort --sort_type=ilabel > $L_dir/L.fst
  touch $L_dir/.done
fi

# Generate confusion matrix
cmdir=$modeldir/conf_matrix_$dev
if [ ! -f $cmdir/.done ]; then
  echo "STEP: generate confusion matrix for model $model and dev data $dev"
  my_local/generate_confusion_matrix.sh --cmd "$decode_cmd" --nj $nj \
    $graphdir $modeldir $alidir $dev_decodedir $cmdir
  my_local/count_to_logprob.pl --cutoff $count_cutoff $cmdir/confusions.txt $cmdir/confusion_prob.txt

  cat $L_dir/phones.txt |\
    grep -v -E "<.*>" | grep -v "SIL" | awk '{print $1;}' |\
    my_local/build_edit_distance_fst.pl --boundary-off=true \
      --confusion-matrix $cmdir/confusion_prob.txt - - |\
    fstcompile --isymbols=$L_dir/phones.txt \
    --osymbols=$L_dir/phones.txt - $cmdir/E.fst
  touch $cmdir/.done
fi

# AM rescore
outdir=${decodedir}_amrescore_${acwt}_${n}_${dev}_${count_cutoff}_beam${beam}
if [ ! -f $outdir/.done ]; then
  eval_nj=`cat $decodedir/num_jobs`
  $decode_cmd JOB=1:$eval_nj $outdir/log/amrescore.JOB.log \
    lattice-amrescore --acoustic-scale=$acwt --n=$n --confused-path-beam=$beam "ark:gzip -cdf $decodedir/lat.JOB.gz |" \
    $cmdir/E.fst $L_dir/L.fst "ark:|gzip -c > $outdir/lat.JOB.gz" || exit 1
  touch $outdir/.done
fi

# Score WER
if [ ! -f $outdir/.done.score ]; then
  [ ! -x local/score.sh ] && \
    echo "$0: not scoring because local/score.sh does not exist or not executable." && exit 1;
  local/score.sh $scoring_opts --cmd "$decode_cmd" $testdatadir $graphdir $outdir
  touch $outdir/.done.score
fi


