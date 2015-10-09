#!/bin/bash

set -e;
set -o pipefail

# chenzp 2015
# Modify an existing LM (with some 'count 0' words) by assigning probabilities based on a score file

inlm=./data/srilm_bbnucoluc100w5+.kn/lm.gz
score_file=./word_score.lr.txt
score_col_idx=1
suffix=LR
score_type="raw" # input score type (-log/log/raw...)
lambda=1
zipf=false
#inlm=./data/srilm_bbnucoluc100w5+.kn/lm.gz
#score_file=./ppl_info.txt
#score_col_idx=2
#suffix=PPL
#score_type="-log"

. ./utils/parse_options.sh

outlm=`dirname $inlm`ModOOCby${suffix}`perl -e "print $lambda*10;"`

if $zipf; then
  outlm=${outlm}z
fi
outlm=${outlm}/lm.gz

if [ $score_type == "-log" ]; then
  r=r
fi

mkdir -p `dirname $outlm`
inlm_lex=data/extra_lexicon/$(basename `dirname $inlm` | sed 's/srilm_//')
if [ ! -f $inlm_lex ]; then
  echo "inlm lexicon not exist: $inlm_lex"
  exit 1;
fi
./czpScripts/prep_lex/lexicon_subtraction.pl \
  $score_file ./data/extra_lexicon/VLLP \
  | ./czpScripts/prep_lex/lexicon_intersection.pl \
    - data/extra_lexicon/$(basename `dirname $inlm` | sed 's/srilm_//') \
  | sort -g$r -k $[score_col_idx+1] |\
  perl ./gen_modLM.pl <(gzip -cdf $inlm) $lambda $score_col_idx $score_type $zipf | gzip -c - > $outlm

cp `dirname $inlm`/vocab `dirname $outlm`/
