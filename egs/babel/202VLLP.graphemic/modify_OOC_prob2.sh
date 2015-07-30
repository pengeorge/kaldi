#!/bin/bash

set -e

inlm=./data/srilm_bbnucoluc100w5+.kn/lm.gz
score_file=./ppl_info.txt

. ./utils/parse_options.sh

k=$1
outlm=./data/srilm_bbnucoluc100w5+.knModOOCbyPPL0$k/lm.gz
mkdir -p `dirname $outlm`
./czpScripts/prep_lex/lexicon_subtraction.pl \
  $score_file ./data/extra_lexicon/VLLP \
  | sort -nr -k 3 |\
  perl ./gen_modLM.pl <(gzip -cdf $inlm) 0.$k | gzip -c - > $outlm
