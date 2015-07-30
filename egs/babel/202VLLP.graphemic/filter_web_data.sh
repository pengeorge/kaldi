#!/bin/bash -v
set -e

if [ $# != 3 ]; then
  echo "Usage: $0 <sample_lexicon> <web-text> <web-lexicon>"
  echo "e.g. $0 data/local/word_list_in_train.txt data/extra_text/bbn data/extra_lexicon/bbn"
  exit 1;
fi

sample_lexicon=$1
text=$2
web_lexicon=$3

base=`basename $text`
for k in 4 5; do
  for n in 100; do
    for s in 2; do
      for e in 4 5; do
        ext=${base}t0${k}c${n}
        cat $text | perl ./czpScripts/prep_lex/filter_LM_text.pl \
          $sample_lexicon 0.$k |\
          awk '{if (NF<=max) print $0}' max="$n" > data/extra_text/${ext}
        cat data/extra_text/${ext} | perl ./czpScripts/prep_lex/filter_LM_text_by_word_list.pl \
          ./english_words.txt ./swahili_words.txt 0.${e} 0.${s} \
          > data/extra_text/${ext}s0${s}e0${e}
        ext=${ext}s0${s}e0${e}
        ./czpScripts/prep_lex/filter_lexicon_by_text.sh \
          data/extra_text/${ext} $web_lexicon data/extra_lexicon/${ext}
      done
    done
  done
done
