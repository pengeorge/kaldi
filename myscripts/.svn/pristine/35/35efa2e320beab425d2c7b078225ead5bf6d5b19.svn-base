#!/bin/bash

scoredir=exp/tri6_nnet/decode_music3.man_ext_music/score_10

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

set -e 
set -o pipefail
set -u

subset_list=$1
if [ -z $subset_list ]; then
  echo "subset list file is not specified"
  exit 1;
fi
subset_name=`basename $subset_list`

ScoringProgram=`which sclite` || ScoringProgram=$KALDI_ROOT/tools/sctk-2.4.8/bin/sclite
[ ! -x $ScoringProgram ] && echo "Cannot find scoring program at $ScoringProgram" && exit 1;
SortingProgram=`which hubscr.pl` || SortingProgram=$KALDI_ROOT/tools/sctk-2.4.8/bin/hubscr.pl
[ ! -x $ScoringProgram ] && echo "Cannot find scoring program at $ScoringProgram" && exit 1;

name=`dirname $scoredir | xargs basename | grep -Po '(?<=decode_)[^_]+'`

for f in $scoredir/stm $scoredir/${name}.ctm  ; do
  [ ! -f $f ] && echo "$0: expecting file $f to exist" && exit 1;
done

outdir=$scoredir/$subset_name
if [ -f "$outdir" ] && [ ! -d "$outdir" ]; then
  echo "File $outdir exists."
  exit 1
fi

mkdir -p $outdir
echo "Processing $outdir"

# filter ctm
echo "Filtering STM and CTM"
ctm=$outdir/${name}.ctm
stm=$outdir/stm
grep -f <(awk '{print "BABEL_DIY_003_20150109-"$1"_inLine"}' $subset_list) $scoredir/${name}.ctm > $ctm
grep -f <(awk '{print "BABEL_DIY_003_20150109-"$1"_inLine"}' $subset_list) $scoredir/stm > $stm

cp $ctm $ctm.unsorted
cp $stm $stm.unsorted
$SortingProgram sortCTM < $ctm.unsorted  > $ctm
$SortingProgram sortSTM < $stm.unsorted  > $stm

echo "Scoring CTM..."
$ScoringProgram -s -r $stm  stm -h $ctm ctm \
  -n "$name.ctm" -f 0 -D -F  -o  sum rsum prf dtl sgml -e utf-8 || exit 1
$ScoringProgram -s -r $stm stm -h $ctm ctm \
  -n "$name.char.ctm" -o sum rsum prf dtl sgml -f 0 -D -F -c NOASCII DH -e utf-8 || exit 1

cat $scoredir/../scoring/oracle_cer.log | perl -e '
  open(LIST, "'$subset_list'") or die;
  while (<LIST>) {
    chomp;
    $list{$_} = 1;
  }
  close(LIST);
  $err = 0;
  $tot = 0;
  $ins = 0;
  $del = 0;
  $sub = 0;
  while (<STDIN>) {
    chomp;
    if (/^Lattice/) {
      if (/20150109-(.*)_inLine/) {
        if (defined($list{$1})) {
          print "$_\n";
          $nextline = <STDIN>;
          print "$nextline";
          if ($nextline =~ /%CER [\d\.]+ \[ (\d+) \/ (\d+), (\d+) insertions, (\d+) deletions, (\d+) sub/) {
            $err += $1;
            $tot += $2;
            $ins += $3;
            $del += $4;
            $sub += $5;
          }
        }
      }
    }
  }
  printf "Overall \%CER %.2f [ %d / %d , %d insertions, %d deletions, %d substitutions ]\n", 100*$err/$tot, $err, $tot, $ins, $del, $sub;' > $outdir/oracle_cer.log

echo Done
echo
