#!/bin/bash

# Copyright 2012  Johns Hopkins University (Author: Guoguo Chen)
# Apache 2.0.

# Begin configuration section.  
case_insensitive=true
use_icu=true
icu_transform="Any-Lower"
silence_word='<silence>' # Optional silence word to insert (once) between words of the transcript.
# End configuration section.

echo $0 "$@"

help_message="
   Usage: local/kws_data_prep_subword.sh <word-to-subwords-lexicon> <word-lang-dir> <subword-lang-dir> <data-dir> <kws-data-dir>
    e.g.: local/kws_data_prep_subword.sh w2s.lex ../204/data/lang data/lang/ data/eval/ data/kws/
   Input is in <kws-data-dir>: kwlist.xml, ecf.xml (rttm file not needed).
   Output is in <kws-data/dir>: keywords.txt, keywords_all.int, kwlist_invocab.xml,
       kwlist_outvocab.xml, keywords.fsts
   Note: most important output is keywords.fsts
   allowed switches:
      --case-sensitive <true|false>      # Shall we be case-sensitive or not?
                                         # Please not the case-sensitivness depends 
                                         # on the shell locale!
      --use-uconv <true|false>           # Use the ICU uconv binary to normalize casing
      --icu-transform <string>           # When using ICU, use this transliteration
              
"

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;


if [ $# -ne 5 ]; then
  printf "FATAL: invalid number of arguments.\n\n"
  printf "$help_message\n"
  exit 1;
fi

set -u
set -e 
set -o pipefail

w2slex=$1;
wlangdir=$2;
langdir=$3;
datadir=$4;
kwsdatadir=$5;
keywords=$kwsdatadir/kwlist.xml


mkdir -p $kwsdatadir;

cat $keywords | perl -e '
  #binmode STDIN, ":utf8"; 
  binmode STDOUT, ":utf8"; 

  use XML::Simple;
  use Data::Dumper;

  my $data = XMLin(\*STDIN);

  #print Dumper($data->{kw});
  foreach $kwentry (@{$data->{kw}}) {
    #print Dumper($kwentry);
    print "$kwentry->{kwid}\t$kwentry->{kwtext}\n";
  }
' > $kwsdatadir/keywords.txt


# Map the keywords to integers; note that we remove the keywords that
# are not in our $langdir/words.txt, as we won't find them anyway...
#cat $kwsdatadir/keywords.txt | babel/filter_keywords.pl $langdir/words.txt - - | \
#  sym2int.pl --map-oov 0 -f 2- $langdir/words.txt | \
if  $case_insensitive && ! $use_icu  ; then
  echo "$0: Running case insensitive processing"
  cat $wlangdir/words.txt | tr '[:lower:]' '[:upper:]'  > $kwsdatadir/words.txt
  [ `cut -f 1 -d ' ' $kwsdatadir/words.txt | sort -u | wc -l` -ne `cat $kwsdatadir/words.txt | wc -l` ] && \
    echo "$0: Warning, multiple words in dictionary differ only in case: " 
    

  cat $kwsdatadir/keywords.txt | tr '[:lower:]' '[:upper:]'  | \
    sym2int.pl --map-oov 0 -f 2- $kwsdatadir/words.txt > $kwsdatadir/keywords_all.int
elif  $case_insensitive && $use_icu ; then
  echo "$0: Running case insensitive processing (using ICU with transform \"$icu_transform\")"
  cat $wlangdir/words.txt | uconv -f utf8 -t utf8 -x "${icu_transform}"  > $kwsdatadir/words.txt
  [ `cut -f 1 -d ' ' $kwsdatadir/words.txt | sort -u | wc -l` -ne `cat $kwsdatadir/words.txt | wc -l` ] && \
    echo "$0: Warning, multiple words in dictionary differ only in case: " 

  paste <(cut -f 1  $kwsdatadir/keywords.txt  ) \
        <(cut -f 2  $kwsdatadir/keywords.txt | uconv -f utf8 -t utf8 -x "${icu_transform}" ) |\
    local/kwords2indices.pl --map-oov 0  $kwsdatadir/words.txt > $kwsdatadir/keywords_all.int
else
  cp $wlangdir/words.txt  $kwsdatadir/words.txt
  cat $kwsdatadir/keywords.txt | \
    sym2int.pl --map-oov 0 -f 2- $kwsdatadir/words.txt > $kwsdatadir/keywords_all.int
fi

cp $langdir/words.txt $kwsdatadir/subwords.txt  # subword is always case-sensitive !

cut -f 1 -d ' ' $kwsdatadir/subwords.txt | sed '1d' | grep -P '^<' | grep -v -P '^<hes>' |\
  awk '{print $1" "$1;}' > $kwsdatadir/W2S.lex

cat $w2slex | awk -F"\t" '{for (i=2; i<= NF; i++) { print $1"\t"$i; }}' > $kwsdatadir/w2s.mline.lex
cat $kwsdatadir/w2s.mline.lex |  sym2int.pl --map-oov 123456789 -f 2- $kwsdatadir/subwords.txt |\
  grep -v -w 123456789 | int2sym.pl -f 2- $kwsdatadir/subwords.txt >> $kwsdatadir/W2S.lex
n1=`cat $kwsdatadir/w2s.mline.lex | wc -l`
n2=`cat $kwsdatadir/W2S.lex | wc -l`
echo "After removing OOV symbols from word-to-syllable lexicon, #lines changed from $n1 to $n2"

(cat $kwsdatadir/keywords_all.int | \
  grep -v " 0 " | grep -v " 0$" > $kwsdatadir/keywords.int ) || true

(cut -f 1 -d ' ' $kwsdatadir/keywords.int | \
  local/subset_kwslist.pl $keywords > $kwsdatadir/kwlist_invocab.xml) || true

(cat $kwsdatadir/keywords_all.int | \
  egrep " 0 | 0$" | cut -f 1 -d ' ' | \
  local/subset_kwslist.pl $keywords > $kwsdatadir/kwlist_outvocab.xml) || true


# Compile word-to-subwords FST
echo "Compiling word-to-subwords FST"
cat $kwsdatadir/W2S.lex |\
  local/make_lexicon_fst_special.pl - $silence_word |\
  fstcompile --isymbols=$kwsdatadir/subwords.txt \
  --osymbols=$kwsdatadir/words.txt - |\
  fstinvert | fstarcsort --sort_type=olabel > $kwsdatadir/W2S.fst

# Compile keywords into FSTs
echo "Compiling keywords into FSTs, silence_word=$silence_word"
if [ -z $silence_word ]; then
  transcripts-to-fsts --right-compose=$kwsdatadir/W2S.fst ark:$kwsdatadir/keywords.int ark,t:$kwsdatadir/keywords.fsts
else
  silence_int_word=`grep -w $silence_word $wlangdir/words.txt | awk '{print $2}'`
  silence_int_subword=`grep -w $silence_word $langdir/words.txt | awk '{print $2}'`
  ([ -z $silence_int_word ] || [ -z $silence_int_subword ]) && \
     echo "$0: Error: could not find integer representation of silence word $silence_word" && exit 1;
  transcripts-to-fsts --right-compose=$kwsdatadir/W2S.fst ark:$kwsdatadir/keywords.int ark,t:- | \
    awk -v 'OFS=\t' -v silintw=$silence_int_word -v silints=$silence_int_subword '{if (NF == 4 && $1 != 0) { print $1, $1, silintw, silints; } print; }' \
     > $kwsdatadir/keywords.fsts
fi


#fstcomposeeach ark,t:$kwsdatadir/keywords_word.fsts $kwsdatadir/W2S.fst ark,t:$kwsdatadir/keywords.fsts

if [ ! -f $datadir/kws_common/.done ]; then
  mkdir -p $datadir/kws_common
  # Creates utterance id for each utterance.
  cat $datadir/segments | \
    awk '{print $1}' | \
    sort | uniq | perl -e '
    $idx=1;
    while(<>) {
      chomp;
      print "$_ $idx\n";
      $idx++;
    }' > $datadir/kws_common/utter_id

  # Map utterance to the names that will appear in the rttm file. You have 
  # to modify the commands below accoring to your rttm file
  cat $datadir/segments | awk '{print $1" "$2}' |\
    sort | uniq > $datadir/kws_common/utter_map;

  touch $datadir/kws_common/.done
fi

echo "$0: Kws data preparation succeeded"
