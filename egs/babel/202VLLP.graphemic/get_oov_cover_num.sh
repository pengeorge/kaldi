#!/bin/bash

set -e


key=ext #bbnucoluc100w5  # candidate word list (may include IV)
suffix=
. ./utils/parse_options.sh

org_lexicon=data/extra_lexicon/${key}${suffix} #+.knModOOCbyPPL06
#nt=./exp/tri5/decode_dev10h.pem_${key}${suffix}+.knModOOCbyPPL06/${key}${suffix}-exc-VLLP_kws_15/Ntrue.txt
nt=./exp/dnn_scratch_6langFLPNN.raw_cont_mpe/decode_dev10h.pem_ext_epoch1/bbnucoluc100w5-exc-VLLP_kws_11/Ntrue.txt

lmsorted=./exp/vocab_select/${key}.pron.mode1.sorted.gz

lmorderlist=$(dirname $lmsorted)/${key}.word_sorted.txt
if false; then
gzip -cdf $lmsorted |\
  perl -e '
    my %p2w;
    open(ALL, "$ARGV[0]") or die;
    while (<ALL>) {
      chomp;
      my @col = split(/\t/, $_);
      $col[1] =~ s/é/e/g;
      $col[1] =~ s/ó/o/g;
      $col[1] =~ s/í/i/g;
      $p2w{$col[1]} = $col[0];
    }
    close(ALL);
    while (<STDIN>) {
      chomp;
      my @col = split(/\t/, $_);
      $col[1] =~ s/é/e/g;
      $col[1] =~ s/ó/o/g;
      $col[1] =~ s/í/i/g;
      #$col[1] =~ tr/éó/eo/;
      if (!defined($p2w{$col[1]})) {
        die "something wrong: $_\n";
      }
      print "$p2w{$col[1]}\t$col[0]\n";
    } ' $org_lexicon > $lmorderlist
fi

if false; then
  ./czpScripts/prep_lex/lexicon_subtraction.pl \
    $lmorderlist data/extra_lexicon/VLLP > ${lmorderlist}.oov
fi
lmorderlist=${lmorderlist}.oov

ntorderlist=${nt}.orderlist
if false; then
  cut -f 2- ${nt} > $ntorderlist
  ./czpScripts/prep_lex/lexicon_subtraction.pl \
    $ntorderlist data/extra_lexicon/VLLP > ${ntorderlist}.oov
fi
ntorderlist=${ntorderlist}.oov

#for k in `seq 1 174`; do
randorderlist=${key}.rand
if false; then
./czpScripts/prep_lex/lexicon_subtraction.pl \
  data/extra_lexicon/${key} data/extra_lexicon/VLLP \
  | sort -R > $randorderlist
fi
for k in ; do
  ./czpScripts/prep_lex/lexicon_intersection.pl \
    <(head -n ${k}000 ${ntorderlist} | sort) \
    data/extra_lexicon/dev | wc -l
done
#if false; then
  for k in 3 5 7 9; do
    ./czpScripts/prep_lex/lexicon_intersection.pl \
      data/extra_lexicon/${key} \
      <(head -n ${k}000 ${ntorderlist} | sort) \
      > data/extra_lexicon/${key}${suffix}mldnnnt${k}000
  done
#fi
