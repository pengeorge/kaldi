#!/bin/bash

. path.sh

format=pdf # pdf svg

. utils/parse_options.sh

if [ $# != 4 ]; then
   echo "usage: $0 [--format pdf|svg] <utt-id> <lattice-ark> <word-list> <out-dir>"
   echo "e.g.:  $0 utt-0001 \"test/lat.*.gz\" tri1/graph/words.txt lat-show"
   exit 1;
fi

uttid=$1
lat=$2
words=$3
outdir=$4

uttid_trans=`echo $uttid | sed "s:|:=:g"`
#uttid_trans=`echo $uttid | sed "s:|:\\\\\\\\\\\\\\\|:g"`
#uttid_trans=`echo $uttid | sed "s:|:\\\|:g"`
echo $uttid_trans
echo "$uttid_trans"
#exit 0;

#tmpdir=$(mktemp -d); trap "rm -r $tmpdir" EXIT # cleanup
tmpdir=tmp

if [[ $lat =~ gz$ ]]; then
    gunzip -c $lat > $tmpdir/lat.ark
else
    cp $lat $tmpdir/lat.ark
fi
lattice-to-fst ark:$tmpdir/lat.ark ark,scp:$tmpdir/fst.ark,$tmpdir/fst.scp || exit 1

! grep -e "^$uttid " $tmpdir/fst.scp && echo "ERROR : Missing utterance '$uttid' from gzipped lattice ark '$lat'" && exit 1
#fstcopy "scp:grep -e '^$uttid ' $tmpdir/fst.scp |" "scp:echo '$uttid $tmpdir/$uttid_trans.fst' |" || exit 1
echo "$uttid $tmpdir/$uttid_trans.fst" > $tmpdir/out.scp
fstcopy "scp:grep -e '^$uttid ' $tmpdir/fst.scp |" "scp:$tmpdir/out.scp" || exit 1
#fstdraw --portrait=true --osymbols=$words $tmpdir/$uttid.fst | dot -T${format} > $tmpdir/$uttid.${format}
fstdraw --portrait=true --osymbols=$words $tmpdir/$uttid_trans.fst | dot -T${format} > $outdir/$uttid_trans.${format}

#[ $format == "pdf" ] && evince $tmpdir/$uttid.pdf
#[ $format == "svg" ] && eog $tmpdir/$uttid.svg

exit 0
