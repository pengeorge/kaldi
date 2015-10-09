#!/bin/bash
# Copyright 2014  Johns Hopkins University (Author: Yenda Trmal)
# Apache 2.0

# Begin configuration section.  
iters=5
stage=0
encoding='utf-8'
remove_tags=true
only_words=true
ext_pron=
icu_transform="Any-Lower"
var_counts=3  #Generate upto N variants
var_mass=0.9  #Generate so many variants to produce 90 % of the prob mass
cmd=run.pl
nj=10          #Split the task into several parallel, to speedup things
model=
# End configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

set -u
set -e

if [ $# != 3 ]; then
   echo "Usage: $0 [options] <word-list> <g2p-model-dir> <output-dir>"
   echo "... where <word-list> is a list of words whose pronunciation is to be generated"
   echo "          <g2p-model-dir> is a directory used as a target during training of G2P"
   echo "          <output-dir> is the directory where the output lexicon should be stored"
   echo "e.g.: $0 oov_words exp/g2p exp/g2p/oov_lex"
   echo ""
   echo "main options (for others, see top of script file)"
   echo "  --nj <int>                                    # How many tasks should be spawn (to speedup things)"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   exit 1;
fi

wordlist=$1
modeldir=$2
output=$3


mkdir -p $output/log

model=$modeldir/g2p.model.final
[ ! -f $model ] && echo "File $model not found in the directory $data." && exit 1
#[ ! -x $wordlist ] && echo "File $wordlist not found!" && exit 1

cp $wordlist $output/wordlist.orig.txt

if [ ! -z $icu_transform ] ; then
  #we have to keep a correspondence map A -> trasnform(A)
  paste \
    <(cat $output/wordlist.orig.txt | uconv -f $encoding -t $encoding -x $icu_transform) \
    $output/wordlist.orig.txt \
  > $output/transform_map.txt
  cut -f 1 $output/transform_map.txt | sort -u > $output/wordlist.txt
else
  cp $output/wordlist.orig.txt  $output/wordlist.txt
fi

if [ -z "$ext_pron" ]; then
  cp $output/wordlist.txt $output/wordlist.for_g2p.txt
  touch $output/output_from_ext_pron
else
  cat $output/wordlist.txt | perl -e '
    use strict;
    my $ext_pron = $ARGV[0];
    my $known = $ARGV[1];
    my %Pron;
    open(LEX, "$ext_pron") or die "Cannot open ext_pron file: $ext_pron \n";
    while (<LEX>) {
      chomp;
      my @prons = split(/\t/, $_);
      my $w = shift @prons;
      @{$Pron{$w}} = ();
      while (my $pron = shift @prons) {
        my $newpron = "";
        my @phones = split(/ /, $pron);
        foreach my $phone (@phones) {
          $phone =~ s/_//g;
          $newpron = "$newpron $phone";
        }
        $newpron =~ s/^ //;
        push(@{$Pron{$w}}, $newpron);
      }
    }
    open(KNOWN, ">$known") or die "Cannot open known_wordlist to write: $known\n";
    while (<STDIN>) {
      chomp;
      if (defined($Pron{$_})) {
        my $weight = 1/@{$Pron{$_}};
        for (my $i = 0; $i < @{$Pron{$_}}; $i++) {
          print KNOWN "$_\t$i\t$weight\t$Pron{$_}[$i]\n";
        }
      } else {
        print "$_\n";
      }
    }' $ext_pron $output/output_from_ext_pron > $output/wordlist.for_g2p.txt
fi


if ! g2p=`which g2p.py` ; then
  echo "The Sequitur was not found !"
  echo "Go to $KALDI_ROOT/tools and execute extras/install_sequitur.sh"
  exit 1
fi


echo "Applying the G2P model to wordlist $wordlist"

if [ $stage -le 0 ]; then
  $cmd JOBS=1:$nj $output/log/apply.JOBS.log \
    split -n l/JOBS/$nj $output/wordlist.for_g2p.txt \| \
    g2p.py -V $var_mass --variants-number $var_counts --encoding $encoding \
      --model $modeldir/g2p.model.final --apply - \
    \> $output/output.JOBS
fi
cat $output/output.* $output/output_from_ext_pron > $output/output

#Remap the words from output file back to the original casing
#Conversion of some of thems might have failed, so we have to be careful
#and use the transform_map file we generated beforehand
#Also, because the sequitur output is not readily usable as lexicon (it adds 
#one more column with ordering of the pron. variants) convert it into the proper lexicon form
output_lex=$output/lexicon.lex
if [ ! -z $icu_transform ] ; then
  #also, the transform is generally N -> 1, i.e. we have to take
  #extra care of words that might have been mapped into the same one
  perl -e 'open(WORDS, $ARGV[0]) or die "Could not open file $ARGV[0]"; 
           while(<WORDS>) { chomp; @F=split; 
             if ($MAP{$F[0]} ) { push @{$MAP{$F[0]}}, $F[1]; } 
             else { $MAP{$F[0]} = [$F[1]]; }
           }
           close(WORDS);
           open(LEX, $ARGV[1]) or die "Could not open file $ARGV[1]";
           while(<LEX>) {chomp; @F=split /\t/;
             if ( $#F != 3 ) {
               print STDERR "WARNING: Non-acceptable entry \"" . join(" ", @F) . "\" ($#F splits)\n";
               next;
             }
             foreach $word (@{$MAP{$F[0]}} ) {
               print "$word\t$F[2]\t$F[3]\n"; 
             }
           }
           close(LEX);
           ' \
    $output/transform_map.txt $output/output | sort -u > $output_lex
else
  #Just convert it to a proper lexicon format
  cut -f 1,3,4 $output/output $output_lex
fi

#Some words might have been removed or skipped during the process,
#let's check it and warn the user if so...
nlex=`cut -f 1 $output_lex | sort -u | wc -l`
nwlist=`cut -f 1 $output/wordlist.orig.txt | sort -u | wc -l`
if [ $nlex -ne $nwlist ] ; then
  echo "WARNING: Unable to generate pronunciation for all words. ";
  echo "WARINNG:   Wordlist: $nwlist words"
  echo "WARNING:   Lexicon : $nlex words"
  echo "WARNING:Diff example: "
  set +e # diff would return 1 if any difference is found.
  diff <(cut -f 1 $output_lex | sort -u ) \
       <(cut -f 1 $output/wordlist.orig.txt | sort -u )
  set -e
fi
exit 0
