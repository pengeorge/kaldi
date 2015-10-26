#!/bin/bash

set -e
set -o pipefail

. path.sh
lex=data/lang/words.txt  #./data/lang_ext_music/words.txt
w2c=`dirname $lex`/w2c.int
. ./utils/parse_options.sh

if [ $# -ne 1 ]; then
  echo "Usage: $0 [options] <decode-dir>"
  echo " e.g.: $0 exp/tri6/decode_dev10h"
  exit 1;
fi

dir=$1
datatype=`basename $dir | grep -Po '(?<=decode_)[^_]*'`

if [ ! -f $w2c ]; then
  echo "Word-to-char ID file does not exist. Now create it."
  cut -d' ' -f 1 $lex | perl -e '
    use Encode;
    while (<STDIN>) {
      chomp;
      if (/^</ || /^#/) {
        print "$_ $_\n";
      } else {
        print "$_ ".encode("utf8", join(" ", split(//, decode("utf8", $_))))."\n";
      }
    }' | sym2int.pl --map-oov "<unk>" $lex > $w2c
fi

if [ ! -f data/$datatype/text ]; then
  echo "data/$datatype/text does not exist. Generate it manually."
  cut -d' ' -f 1 data/$datatype/utt2spk | paste - <(cut -d' ' -f 6- data/$datatype/stm) > data/$datatype/text
fi
lattice-oracle-cer.chenzp $w2c "ark:gunzip -cdf $dir/lat.*.gz|" \
  "ark:sym2int.pl --map-oov '<unk>' -f 2- $lex < data/$datatype/text |" \
  "ark,t:| int2sym.pl -f 2- $lex > $dir/scoring/oracle_path" 2>&1 |\
  tee $dir/scoring/oracle_cer.log

echo Done

