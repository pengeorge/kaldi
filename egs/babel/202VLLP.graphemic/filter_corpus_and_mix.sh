#!/bin/bash
set -e

lex_ext=glm6000
base_web_lex=bbnucoluc100w5
base_web_text=
thres=2 # 0.2

. ./utils/parse_options.sh

if [ -z $base_web_text ]; then
  base_web_text=$base_web_lex
fi

filtered_text_path=./data/extra_text/${base_web_lex}${lex_ext}Fil0${thres}
if [ ! -f $filtered_text_path ]; then
  ./czpScripts/prep_lex/filter_LM_text.pl <(cat ./data/extra_lexicon/${lex_ext} ./data/extra_lexicon/VLLP | sort -u) 0.${thres} \
    < ./data/extra_text/$base_web_text > $filtered_text_path
fi

filtered_text_ext=`basename $filtered_text_path`

./test_any_ext.any_smooth.sh --lm-only true --ext-set " ${lex_ext}+.kn "
new_web_ext=${lex_ext}+${filtered_text_ext}-VLLP
./test_any_ext.any_smooth.sh --lm-only true --ext-set " $new_web_ext "

./test_mix_lm.sh --lm-only false --ext ${lex_ext}+.kn --ext-for-mix $new_web_ext --skip-kws false

