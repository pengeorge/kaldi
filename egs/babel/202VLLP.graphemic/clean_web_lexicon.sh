#!/bin/bash
set -e

. lang.conf

input_lexicon=$1
output_lexicon=$2

dir=data/clean_`basename ${input_lexicon}`

if [ ! -z $train_data_dir ]; then
  trans_dir=$train_data_dir/transcription
else
  trans_dir=$train_data_trans_dir
fi

mkdir -p data/local
./czpScripts/local/extract_word_list_from_transcription.sh --case-insensitive $case_insensitive $trans_dir data/local/word_list_in_train.txt

cat data/local/word_list_in_train.txt | grep -vP '^<.*>$' | grep -vP '^\(' | sed 's/\(.\)/\1\n/g' | sort -u | grep -vP '^$' > data/local/charset_in_train.txt

mkdir -p $dir

#./gen_graphemic_lex.pl < $input_lexicon > $dir/graphemic_lexicon.no_clean.txt 2> $dir/non-latin-letter.txt

cat $dir/graphemic_lexicon.no_clean.txt  | awk '
    BEGIN {
      while(( getline line< ARGV[2] ) > 0 ) {
          CHARSET[ line ]=line
      }
      FILENAME="-"
      i=0

      while(( getline line< ARGV[1] ) > 0 ) {
        n = split(line, e)
        keep = 1
        for (i=2; i <= n; i++) {
          if (! (e[i] in CHARSET)) {
            #print e[i]
            keep = 0
            break
          }
        }
        if (keep == 1) {
          print line
        }
      }
    }' - data/local/charset_in_train.txt > $output_lexicon
    #| cut -f 2- | sed 's/ /\n/g' | sort -u > remain_charset.tmp
    #
