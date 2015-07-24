#!/bin/bash

echo "$0 $@"  # Print the command line for logging

case_insensitive=true

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

transcriptions=$1
output_word_list=$2

if $case_insensitive; then
  echo "Making lexicon: all lower case"
  (
    find $transcriptions -name "*.txt" | xargs egrep -vx '\[[0-9.]+\]'  |cut -f 2- -d ':' | sed 's/ /\n/g'
  ) | tr A-Z a-z | sort -u > $output_word_list
else
  (
    find $transcriptions -name "*.txt" | xargs egrep -vx '\[[0-9.]+\]'  |cut -f 2- -d ':' | sed 's/ /\n/g'
  ) | sort -u > $output_word_list
fi
