#!/bin/bash

set -e

. lang.conf

export LC_ALL=C

mkdir -p exp/morph_gen
lexicon_file_mapped=exp/morph_gen/lexicon.mapped.txt

cut -f 2- $lexicon_file | sed 's/é/e/g' | paste <(cut -f 1 $lexicon_file) - > ${lexicon_file_mapped}.include_special
cat ${lexicon_file_mapped}.include_special | grep -v '^<' > $lexicon_file_mapped
cat ${lexicon_file_mapped}.include_special | grep '^<' > ${lexicon_file_mapped}.special
cut -f 2- $lexicon_file_mapped | sed 's/\t/\n/g' | sed 's/^ \+//' |\
  sort -u > exp/morph_gen/morph-pron-phone_train.txt

  set +e
  morfessor -t exp/morph_gen/morph-pron-phone_train.txt -S exp/morph_gen/model.segm -T exp/morph_gen/morph-pron-phone_train.txt --atom-separator ' ' --compound-separator '\n' --output-format-separator '#'
#  morfessor -t exp/morph_gen/morph-pron-phone_train.txt -S exp/morph_gen/model.segm -S exp/morph_gen/model.pickled  --atom-separator ' ' --compound-separator '\n' --output-format-separator '#'
#  morfessor-segment -L exp/morph_gen/model.segm exp/morph_gen/test.txt \
#  --atom-separator '' --compound-separator '\n' \
#  > exp/morph_gen/test.seged.txt
  #-o exp/morph_gen/morph-pron-phone_train.segmented
  set -e

sed '1d' exp/morph_gen/model.segm | cut -f 2- -d' ' | sed 's/ + /\n/g' |sort -u > exp/morph_gen/constructions.list

sed '1d' exp/morph_gen/model.segm | cut -f 2- -d' ' | sed 's/ + / . /g' > exp/morph_gen/subword-annotated.only_pron.txt

perl ./czpScripts/gen_subword-annotated-lex.pl $lexicon_file_mapped exp/morph_gen/subword-annotated.only_pron.txt > exp/morph_gen/morph_lexicon.txt
cut -f 1 ${lexicon_file_mapped}.special | paste - <(cut -f 1 ${lexicon_file_mapped}.special ) >> exp/morph_gen/morph_lexicon.txt

sed 's/ \+/-/g' exp/morph_gen/constructions.list | paste - exp/morph_gen/constructions.list > data/extra_lexicon/morph
cat ${lexicon_file_mapped}.special >> data/extra_lexicon/morph

cat data/srilm/train.txt | perl -e '
  open(MLEX, "exp/morph_gen/morph_lexicon.txt") or die;
  open(W2S, ">exp/morph_gen/lexicon.w2s.txt") or die;
  open(DEV, "$ARGV[0]") or die;
  open(DEV_OUT, ">$ARGV[1]") or die;
  my %w2s;
  while (<MLEX>) {
      chomp;
      my @col = split(/\t/, $_);
      my $word = shift @col;
      print W2S "$word";
      while (my $pron = shift @col) { # other prons are ignored
          my @raw_morphs = split(/ \. /, $pron);
          my @morphs = ();
          foreach my $m (@raw_morphs) {
              $m =~ s/ /-/g;
              push(@morphs, $m);
          }
          print W2S "\t".join(" ", @morphs);
          if (!defined($w2s{$word})) {
              $w2s{$word} = join(" ", @morphs);
          }
      }
      print W2S "\n";
  }
  while (<STDIN>) {
      chomp;
      my @col = split(/ /, $_);
      my @new_sent = ();
      foreach my $word (@col) {
          if (defined($w2s{$word})) {
              push(@new_sent, $w2s{$word});
          } elsif ($word =~ m/^<(.*)>$/) {
              if ($1 eq "<unk>") {
                  push(@new_sent, "<unk>");
              } else {
                  push(@new_sent, $word);
              }
          } else {
              die "Unknown word: $word\n";
          }
      }
      print join(" ", @new_sent)."\n";
  }
  while (<DEV>) {
      chomp;
      my @col = split(/ /, $_);
      my @new_sent = ();
      foreach my $word (@col) {
          if (defined($w2s{$word})) {
              push(@new_sent, $w2s{$word});
          } elsif ($word =~ m/^<(.*)>$/) {
              if ($1 eq "<unk>") {
                  push(@new_sent, "<unk>");
              } else {
                  push(@new_sent, $word);
              }
          } else {
              print STDERR "Unknown word: $word\n";
              push(@new_sent, "<unk>");
          }
      }
      print DEV_OUT join(" ", @new_sent)."\n";
  }' data/srilm/dev.txt data/extra_text/dev_morph > data/extra_text/morph     

