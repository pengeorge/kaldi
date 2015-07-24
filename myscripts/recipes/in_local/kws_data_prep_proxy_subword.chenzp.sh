#!/bin/bash

# Copyright 2014  Guoguo Chen
# Apache 2.0.

# TODO For subword system, the "word" is always case-sensitive. So the processing of
#      case-insensitive case in this scrit is meaningless. DO NOT USE IT!!
#      This should be fixed by specifying another parameter indicating whether the true
#      words are case-insensitive. (chenzp, Apr 12,2014)


# Begin configuration section.  
nj=8
cmd=run.pl
self_prior=false
make_proxy_stochastic=false
reverse_confusion_matrix=false
use_case=false
use_log=false
cm_type=
beam=-1             # Beam for proxy FST, -1 means no prune
phone_beam=-1       # Beam for KxL2xE FST, -1 means no prune
nbest=-1            # Use top n best proxy keywords in proxy FST, -1 means all
                    # proxies
phone_nbest=50      # Use top n best phone sequences in KxL2xE, -1 means all
                    # phone sequences
phone_cutoff=5      # We don't generate proxy keywords for OOV keywords that
                    # have less phones than the specified cutoff as they may
                    # introduce a lot false alarms
confusion_matrix=   # If supplied, using corresponding E transducer
count_cutoff=1      # Minimal count to be considered in the confusion matrix;
                    # will ignore phone pairs that have count less than this.
pron_probs=false    # If true, then lexicon looks like:
                    # Word Prob Phone1 Phone2...
case_insensitive=true
icu_transform="Any-Lower"
proxy_set=          # List of keywords to generate proxies for, one KWID per
                    # line. If empty, then by default generate proxies for all
                    # OOV keywords.
# End configuration section.

[ -f ./path.sh ] && . ./path.sh; # source the path.
echo $0 "$@"
. parse_options.sh || exit 1;

if [ $# -ne 7 ]; then
  echo "Usage: local/kws_data_prep_proxy_subword.sh <word-lang-dir> <subword-lang-dir> <data-dir> \\"
  echo "                 <word2phone-lexicon> <L1-lexicon> <L2-lexicon> <kws-data-dir>"
  echo " e.g.: local/kws_data_prep_proxy_subword.sh ../204/data/lang data/lang/ data/dev10h/ \\"
  echo "      data/local/tmp.lang/lexiconp.txt oov_lexicon.txt data/dev10h/kws/"
  echo "allowed options:"
  echo "  --case-sensitive <true|false>  # Being case-sensitive or not"
  echo "  --icu-transform  <string>      # Transliteration for upper/lower case" 
  echo "                                 # mapping"
  echo "  --proxy-set      <IV/OOV>      # Keyword set for generating proxies"
  exit 1
fi

set -e 
set -o pipefail

wlangdir=$1
langdir=$2
datadir=$3
lw2p_lexicon=$4
l1_lexicon=$5
l2_lexicon=$6
kwsdatadir=$7

# Checks some files.
for f in $wlangdir/words.txt $langdir/words.txt $kwsdatadir/kwlist.xml $lw2p_lexicon $l1_lexicon $l2_lexicon; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1
done

keywords=$kwsdatadir/kwlist.xml
mkdir -p $kwsdatadir/tmp/

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
  }' > $kwsdatadir/raw_keywords_all.txt

# Takes care of upper/lower case.
cp $wlangdir/words.txt $kwsdatadir/words.out.txt
cp $langdir/words.txt $kwsdatadir/subwords.out.txt
cat $l1_lexicon | sed 's/\s/ /g' > $kwsdatadir/tmp/L1.tmp.lex
cat $lw2p_lexicon | sed 's/\s/ /g' > $kwsdatadir/tmp/L_w2p.tmp.lex
if $case_insensitive; then
  echo "$0: Running case insensitive processing"
  echo "$0: Using ICU with transofrm \"$icu_transform\""

  # Processing words.txt
  cat $kwsdatadir/words.out.txt |\
    uconv -f utf8 -t utf8 -x "${icu_transform}"  > $kwsdatadir/words.norm.txt

  # Processing subwords.txt
  cat $kwsdatadir/subwords.out.txt |\
    uconv -f utf8 -t utf8 -x "${icu_transform}"  > $kwsdatadir/subwords.norm.txt
  if $use_case; then
    cat $kwsdatadir/subwords.out.txt | sed '1d' | sed '$d' | cut -d ' ' -f 1 | uconv -f utf8 -t utf8 -x "${icu_transform}" | sort -u |\
      awk 'BEGIN{print "<eps> 0"; c=0;} { c++; print $1" "c;} END{c++; print "#0 "c;}' > $kwsdatadir/subwords.txt
  else
    cp $kwsdatadir/subwords.out.txt $kwsdatadir/subwords.txt
    cp $kwsdatadir/words.out.txt $kwsdatadir/words.txt
  fi

  # Processing lexicon
  cat $l2_lexicon | sed 's/\s/ /g' | cut -d ' ' -f 1 |\
    uconv -f utf8 -t utf8 -x "${icu_transform}" |\
    paste -d ' ' - <(cat $l2_lexicon | sed 's/\s/ /g' | cut -d ' ' -f 2-) \
    > $kwsdatadir/tmp/L2.tmp.lex

  paste <(cut -f 1 $kwsdatadir/raw_keywords_all.txt) \
    <(cut -f 2 $kwsdatadir/raw_keywords_all.txt |\
    uconv -f utf8 -t utf8 -x "${icu_transform}") \
    > $kwsdatadir/keywords_all.txt
  cat $kwsdatadir/keywords_all.txt |\
    local/kwords2indices.pl --map-oov 0 $kwsdatadir/words.norm.txt \
    > $kwsdatadir/keywords_all.int
else
  cat $l2_lexicon | sed 's/\s/ /g' > $kwsdatadir/tmp/L2.tmp.lex
  cp $kwsdatadir/raw_keywords_all.txt $kwsdatadir/keywords_all.txt
  
  cp $kwsdatadir/subwords.out.txt $kwsdatadir/subwords.txt
  cp $kwsdatadir/words.out.txt $kwsdatadir/words.txt

  cat $kwsdatadir/keywords_all.txt | \
    sym2int.pl --map-oov 0 -f 2- $kwsdatadir/words.txt \
    > $kwsdatadir/keywords_all.int
fi

# Writes some scoring related files.
set +e # When egrep/grep found nothing and return 1, 'set -e' option would cause
       # script exit. (chenzp Mar 2014)
cat $kwsdatadir/keywords_all.int |\
  egrep -v " 0 | 0$" | cut -f 1 -d ' ' |\
  local/subset_kwslist.pl $keywords > $kwsdatadir/kwlist_invocab.xml
cat $kwsdatadir/keywords_all.int |\
  egrep " 0 | 0$" | cut -f 1 -d ' ' |\
  local/subset_kwslist.pl $keywords > $kwsdatadir/kwlist_outvocab.xml

# Selects a set to generate proxies for. By default, generate proxies for OOV
# keywords.
if [ -z $proxy_set ]; then
  cat $kwsdatadir/keywords_all.int |\
    egrep " 0 | 0$" | awk '{print $1;}' | sort -u \
    > $kwsdatadir/keywords_proxy.list
else
  cp $proxy_set $kwsdatadir/keywords_proxy.list
fi
cat $kwsdatadir/keywords_all.txt |\
  grep -f $kwsdatadir/keywords_proxy.list > $kwsdatadir/keywords_proxy.txt

cat $kwsdatadir/keywords_proxy.txt |\
  cut -f 2- | awk '{for(x=1;x<=NF;x++) {print $x;}}' |\
  sort -u > $kwsdatadir/keywords_proxy_words.list

# Maps original phone set to a "reduced" phone set. We limit L2 to only cover
# the words that are actually used in keywords_proxy.txt for efficiency purpose.
# Besides, if L1 and L2 contains the same words, we use the pronunciation from
# L1 since it is the lexicon used for the LVCSR training.

# remove tonal suffix (chenzp, Mar 1,2014)
cat $kwsdatadir/tmp/L_w2p.tmp.lex | cut -d ' ' -f 1 |\
  paste -d ' ' - <(cat $kwsdatadir/tmp/L_w2p.tmp.lex | cut -d ' ' -f 2-|\
  sed 's/_[B|E|I|S]//g' | sed 's/_[%|"]//g') |\
  sed 's/_[0-9]\+//g' |\
  awk '{if(NF>=2) {print $0}}' > $kwsdatadir/tmp/L_w2p.orig.lex
cat $kwsdatadir/tmp/L1.tmp.lex | cut -d ' ' -f 1 |\
  paste -d ' ' - <(cat $kwsdatadir/tmp/L1.tmp.lex | cut -d ' ' -f 2-|\
  sed 's/_[B|E|I|S]//g' | sed 's/_[%|"]//g') |\
  sed 's/_[0-9]\+//g' |\
  awk '{if(NF>=2) {print $0}}' > $kwsdatadir/tmp/L1.orig.lex

# We use lower-case L1. After making KxL2xExL1 stochastic, we compose it with a Case FST to ignore the case of proxy words.
# this is because we have a case-sensitive index. (Apr 1,2014  chenzp)
if $case_insensitive && $use_case; then
  paste -d ' ' <(cut -d ' ' -f 1 ${kwsdatadir}/tmp/L_w2p.orig.lex | uconv -f utf8 -t utf8 -x "${icu_transform}") \
     <(cut -d ' ' -f 2- ${kwsdatadir}/tmp/L_w2p.orig.lex) | sort -u > ${kwsdatadir}/tmp/L_w2p.lex
  paste -d ' ' <(cut -d ' ' -f 1 ${kwsdatadir}/tmp/L1.orig.lex | uconv -f utf8 -t utf8 -x "${icu_transform}") \
     <(cut -d ' ' -f 2- ${kwsdatadir}/tmp/L1.orig.lex) | sort -u > ${kwsdatadir}/tmp/L1.lex
else
  cp $kwsdatadir/tmp/L_w2p.orig.lex $kwsdatadir/tmp/L_w2p.lex
  cp $kwsdatadir/tmp/L1.orig.lex $kwsdatadir/tmp/L1.lex
fi
 

cat $kwsdatadir/tmp/L2.tmp.lex | cut -d ' ' -f 1 |\
  paste -d ' ' - <(cat $kwsdatadir/tmp/L2.tmp.lex | cut -d ' ' -f 2-|\
  sed 's/_[B|E|I|S]//g' | sed 's/_[%|"]//g') |\
  sed 's/_[0-9]\+//g' |\
  awk '{if(NF>=2) {print $0}}' | perl -e '
  ($lex1, $words) = @ARGV;
  open(L, "<$lex1") || die "Fail to open $lex1.\n";
  open(W, "<$words") || die "Fail to open $words.\n";
  while (<L>) {
    chomp;
    @col = split;
    @col >= 2 || die "Too few columsn in \"$_\".\n";
    $w = $col[0];
    $w_p = $_;
    if (defined($lex1{$w})) {
      push(@{$lex1{$w}}, $w_p);
    } else {
      $lex1{$w} = [$w_p];
    }
  }
  close(L);
  while (<STDIN>) {
    chomp;
    @col = split;
    @col >= 2 || die "Too few columsn in \"$_\".\n";
    $w = $col[0];
    $w_p = $_;
    if (defined($lex1{$w})) {
      next;
    }
    if (defined($lex2{$w})) {
      push(@{$lex2{$w}}, $w_p);
    } else {
      $lex2{$w} = [$w_p];
    }
  }
  %lex = (%lex1, %lex2);
  while (<W>) {
    chomp;
    if (defined($lex{$_})) {
      foreach $x (@{$lex{$_}}) {
        print "$x\n";
      }
    }
  }
  close(W);
  ' $kwsdatadir/tmp/L_w2p.lex $kwsdatadir/keywords_proxy_words.list \
  > $kwsdatadir/tmp/L2.lex
rm -f $kwsdatadir/tmp/L1.tmp.lex $kwsdatadir/tmp/L2.tmp.lex

# Creates words.txt that covers all the words in L1.lex and L2.lex. We append
# new words to the original word symbol table.

# When case-sensitive, this loop would do the same thing
for words_type in {words,words.out}; do
  if [ $words_type == "words" ]; then
    L_w2p_in_use=L_w2p.lex
  else
    L_w2p_in_use=L_w2p.orig.lex
  fi
  max_id=`cat $kwsdatadir/${words_type}.txt | awk '{print $2}' | sort -n | tail -1`;
  cat $kwsdatadir/keywords_proxy.txt |\
    awk '{for(i=2; i <= NF; i++) {print $i;}}' |\
    cat - <(cat $kwsdatadir/tmp/L2.lex | awk '{print $1;}') |\
    cat - <(cat $kwsdatadir/tmp/$L_w2p_in_use | awk '{print $1;}') |\
    sort -u | grep -F -v -x -f <(cat $kwsdatadir/${words_type}.txt | awk '{print $1;}') |\
    awk 'BEGIN{x='$max_id'+1}{print $0"\t"x; x++;}' |\
    cat $kwsdatadir/${words_type}.txt - > $kwsdatadir/tmp/${words_type}.txt
  cp $kwsdatadir/sub${words_type}.txt $kwsdatadir/tmp/sub${words_type}.txt
done

set -e # reset -e (chenzp Mar 1,2014)

# Creates keyword list that we need to generate proxies for.
cat $kwsdatadir/keywords_proxy.txt | perl -e '
  open(W, "<'$kwsdatadir/tmp/L2.lex'") ||
    die "Fail to open L2 lexicon: '$kwsdatadir/tmp/L2.lex'\n";
  my %lexicon;
  while (<W>) {
    chomp;
    my @col = split();
    @col >= 2 || die "'$0': Bad line in lexicon: $_\n";
    if ('$pron_probs' eq "false") {
      $lexicon{$col[0]} = scalar(@col)-1;
    } else {
      $lexicon{$col[0]} = scalar(@col)-2;
    }
  }
  while (<>) {
    chomp;
    my $line = $_;
    my @col = split();
    @col >= 2 || die "Bad line in keywords file: $_\n";
    my $len = 0;
    for (my $i = 1; $i < scalar(@col); $i ++) {
      if (defined($lexicon{$col[$i]})) {
        $len += $lexicon{$col[$i]};
      } else {
        print STEDRR "'$0': No pronunciation found for word: $col[$i]\n";
      }
    }
    if ($len >= '$phone_cutoff') {
      print "$line\n";
    } else {
      print STDERR "'$0': Keyword $col[0] is too short, not generating proxy\n";
    }
  }' > $kwsdatadir/tmp/keywords.txt

# Creates proxy keywords.
local/generate_proxy_keywords_subword.chenzp.sh \
  --use-log $use_log --cm-type "$cm_type" \
  --self-prior $self_prior \
  --cmd "$cmd" --nj "$nj" --beam "$beam" --nbest "$nbest" \
  --phone-beam $phone_beam --phone-nbest $phone_nbest \
  --confusion-matrix "$confusion_matrix" --count-cutoff "$count_cutoff" \
  --make-proxy-stochastic "$make_proxy_stochastic" \
  --reverse-confusion-matrix "$reverse_confusion_matrix" \
  --pron-probs "$pron_probs" $kwsdatadir/tmp/

# Push weight on the stochastic FSTs
fsttablepush ark:$kwsdatadir/tmp/keywords.fsts ark:$kwsdatadir/tmp/keywords.pushed.fsts 

if $case_insensitive && $use_case; then
  cat $kwsdatadir/tmp/L1.orig.lex | perl -e '
    use Encode;
    my %map;
    while (<STDIN>) {
      chomp;
      my @col = split();
      my $lower = encode("utf8", lc(decode("utf8", $col[0])));
      $map{$col[0]} = $lower;
    }
    for (keys %map) {
      print "0 0 $map{$_} $_\n";
    }
    print "0\n";
    ' | fstcompile --isymbols=$kwsdatadir/tmp/subwords.txt --osymbols=$kwsdatadir/tmp/subwords.out.txt - |\
      fstarcsort --sort_type=ilabel > $kwsdatadir/Case.fst

  fstcomposeeach ark:$kwsdatadir/tmp/keywords.pushed.fsts $kwsdatadir/Case.fst ark:$kwsdatadir/PxC.fsts
    fsttableproject ark:$kwsdatadir/PxC.fsts ark:$kwsdatadir/keywords.fsts
else
  cp $kwsdatadir/tmp/keywords.pushed.fsts $kwsdatadir/keywords.fsts
fi

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
