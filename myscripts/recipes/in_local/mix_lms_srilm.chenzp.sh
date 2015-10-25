#!/bin/bash 
export LC_ALL=C

dev_text=
lambda=0.5

. ./utils/parse_options.sh


lm1=$1
lm2=$2
tgtdir=$3

##End of configuration
loc=`which ngram`;
if [ -z $loc ]; then
  if uname -a | grep 64 >/dev/null; then # some kind of 64 bit...
    sdir=`pwd`/../../../tools/srilm/bin/i686-m64 
  else
    sdir=`pwd`/../../../tools/srilm/bin/i686
  fi
  if [ -f $sdir/ngram ]; then
    echo Using SRILM tools from $sdir
    export PATH=$PATH:$sdir
  else
    echo You appear to not have SRILM tools installed, either on your path,
    echo or installed in $sdir.  See tools/install_srilm.sh for installation
    echo instructions.
    exit 1
  fi
fi

set -e

[ -z $dev_text ] && dev_text=data/dev2h/text

echo "Using dev text  : $dev_text"

for f in $lm1 $lm2 $dev_text; do
  [ ! -s $f ] && echo "No such file $f" && exit 1;
done

# Prepare the destination directory
mkdir -p $tgtdir


# Kaldi transcript files contain Utterance_ID as the first word; remove it
cat $dev_text | cut -f2- -d' ' > $tgtdir/dev.txt
if (($?)); then
    echo "Failed to create $tgtdir/dev.txt from $dev_text"
    exit 1
else
    echo "Removed first word (uid) from every line of $dev_text"
    # wc text.train train.txt # doesn't work due to some encoding issues
    echo $train_text contains `cat $dev_text | perl -ne 'BEGIN{$w=$s=0;}{split; $w+=$#_; $w++; $s++;}END{print "$w words, $s sentences\n";}'`
    echo $tgtdir/dev.txt contains `cat $tgtdir/dev.txt | perl -ne 'BEGIN{$w=$s=0;}{split; $w+=$#_; $w++; $s++;}END{print "$w words, $s sentences\n";}'`
fi

echo "----------------------------------------------------"
echo "Mix $lm1 and $lm2, lambda=$lambda"
echo "----------------------------------------------------"
ngram -lm $lm1 -mix-lm $lm2 -lambda $lambda -write-lm $tgtdir/lm.gz -unk -ppl $tgtdir/dev.txt |\
  column -t | tee $tgtdir/perplexities.txt

#echo "--------------------"
#echo "Computing perplexity"
#echo "--------------------"

echo "The perlexity scores report is stored in $tgtdir/perplexities.txt "

