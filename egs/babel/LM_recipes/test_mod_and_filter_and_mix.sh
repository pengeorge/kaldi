#!/bin/bash
set -e
set -o pipefail

# A full experimental recipe for the work "Exploiting noisy web data ...". Score files are required.
# 1. Modify LM 2. Filter text 3. Mix


fulllex=bbnucoluc100w5
lex=bbnucoluc100w5
method=LR
zipf=false
lambda=1
decode_dir=dev10h.pem

. ./utils/parse_options.sh

feat_dir=./data/OOV_feats/${fulllex}EXCVLLP

col=2
case $method in
  LR)
    feat_file=sw_score.txt
    score_type="raw"
    col=1
    ;;
  1gram)
    feat_file=web1gram.txt
    score_type="log"
    ;;
  wordPPL)
    feat_file=phone_LM_ppl.txt
    score_type="-log"
    ;;
  sentPPL)
    feat_file=sent_avg_ppl.txt
    score_type="-log"
    ;;
  ntrue)
    feat_file=$decode_dir/ntrue.txt
    score_type="log"
    ;;
  max_ntrue)
    feat_type=$decode_dir/ntrue.txt
    col=3
    score_type="log"
    ;;
  reest_ntrue)
    feat_file=$decode_dir/reest_ntrue.txt
    score_type="log"
    ;;
  *)
    exit 1;
    ;;
esac

flag=knModOOCby${method}`perl -e "print $lambda*10;"`
if $zipf; then
  flag=${flag}z
fi

ext=${lex}+.$flag
ext_for_mix=${lex}+${fulllex}x${flag}m2r048-VLLP.kn

if false ; then
echo "Generate word_score.${method}.txt"
cut -f 1 data/extra_lexicon/${lex}EXCVLLP | paste - <(cut -f $col $feat_dir/$feat_file) > word_score.${method}.txt
fi

echo "Modify OOC prob in LM"
inlm=./data/srilm_${lex}+.kn/lm.gz
if [ ! -f $inlm ]; then
  echo "inlm $inlm not exist"
  exit 1;
fi
./modify_OOC_prob2.sh --score-file ./word_score.${method}.txt --score-col-idx 1 \
  --inlm $inlm --zipf $zipf \
  --suffix $method --score-type "$score_type" --lambda $lambda

echo "Build lang for $ext"
./run_modified_lm_test.sh --ext ${ext} --lm-only true

echo "Select text according to $ext"
./text_selection.sh --lmdir data/srilm_${ext} --srclm-flag $flag

echo "Goto x34"
exit 0;

echo "Using selected text for web LM training"
./test_any_ext.any_smooth.sh --lm-only true --ext-set " $ext_for_mix "

echo "Mix LMs and decoding"
./test_mix_lm.sh --lm-only false --ext $ext --ext-for-mix $ext_for_mix --skip-kws false

