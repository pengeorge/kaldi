#!/bin/bash

# TODO not finish yet, don't use it!!!!!
# This script is based on viet/s5/local/eval_data_prep.sh

# Babel107 Vietnamese Eval data preparation 
# Author:  Zhipeng Chen (Feb 21, 2014)

# To be run from one directory above this script.

# The first directory ($sdir) contains the speech data, and the directory
# $sdir/audio/ must exist.
# The second directory ($tdir) contains the transcripts,
# in particular we need the files
# $tdir/*.stm and $tdir/*.rttm

if [ $# -ne 4 ]; then
  echo "Usage: "`basename $0`" <source-corpus-dir> <subset-descriptor-list-file> <segmentation-file(*.stm)> <target-corpus-subset-dir>"
  echo "See comments in the script for more details"
  exit 1
fi

sdir=$1/audio
list=$2
stm=$3
name=$4
[ ! -d $sdir ] \
  && echo "Directory $sidr is expected to be present."
[ ! -f $stm ] \
  && echo "STM File $stm does not exist." && exit 1;
#TODO get rttm directly from corpus
#[ ! -f $tdir/*.rttm ] \
#  && echo "Expecting file $tdir/*.rttm to be present" && exit 1;

. path.sh 

dir=data/local/$name
mkdir -p $dir

find $sdir/audio -iname '*.sph' | sort > $dir/sph.flist
sed -e 's?.*/??' -e 's?.sph??' \
    -e 's?_inLine?_A?' -e 's?_outLine?_B?' $dir/sph.flist |\
    sed -e 's?\(BABEL_BP_107_[0-9]\+\)_\([0-9]\+_[0-9]\+\)_\([A|B]\)?\1|\3|\2?' |\
    paste - $dir/sph.flist \
  > $dir/sph.scp

sph2pipe=$KALDI_ROOT/tools/sph2pipe_v2.5/sph2pipe
[ ! -x $sph2pipe ] \
  && echo "Could not execute the sph2pipe program at $sph2pipe" && exit 1;

awk -v sph2pipe=$sph2pipe,sdir=$sdir '{
  printf("%s %s -f wav -p -c 1 %s/%s.sph |\n", $1, sph2pipe, sdir, $1); 
}' < $list | sort > $dir/wav.scp || exit 1;

# Get segments file...
# segments file format is: utt-id side-id start-time end-time, e.g.:
# sw02001-A_000098-001156 sw02001-A 0.98 11.56
# pem file has lines like: 
# en_4156 A unknown_speaker 301.85 302.48
# stm file has lines like:
# en_4156 A en_4156_A 357.64 359.64  HE IS A POLICE OFFICER 

grep -v ';;' $stm \
  | awk 'NF>=6{
           spk=$1;
           sub(/_inLine/,"_A",spk);
           sub(/_outLine/,"_B",spk);
           utt=sprintf("%s_%06d",spk,$4*100);
           print utt,$1,$4,$5;}' \
  |  sed -e 's?\BABEL_BP_[0-9]\+_\([0-9]\+\)_\([0-9]\+_[0-9]\+\)_\([A|B]\)?\1|\3|\2?' \
  | sort -u > $dir/segments

grep -v ';;' $stm \
  | awk 'NF>=6{
           spk=$1;
           sub(/_inLine/,"_A",spk);
           sub(/_outLine/,"_B",spk);
           utt=sprintf("%s_%06d",spk,$4*100);
           print utt,$1,$4,$5;' \
  |  sed -e 's?\BABEL_BP_[0-9]\+_\([0-9]\+\)_\([0-9]\+_[0-9]\+\)_\([A|B]\)?\1_\3_\2?' \
  | awk 'NF>=6{
           spk=$1;
           sub(/_inLine/,"_A",spk);
           sub(/_outLine/,"_B",spk);
           utt=sprintf("%s_%06d",spk,$4*100);
           printf utt;
           for(n=6;n<=NF;n++) {
               printf(" %s", $n);
           }
           print ""; }' \
  |  sed -e 's?\BABEL_BP_[0-9]\+_\([0-9]\+\)_\([0-9]\+_[0-9]\+\)_\([A|B]\)?\1_\3_\2?' \
  | perl local/viet_map_words.pl | sort > $dir/text.all

# We'll use the stm file for sclite scoring.  There seem to be various errors
# in the stm file that upset hubscr.pl, and we fix them here.
sed -e 's:((:(:' $stm |\
  grep -v ';;' |\
  grep -v IGNORE_TIME_SEGMENT_ |\
  awk 'NF>=6{print $0;}' >  $dir/stm.unused

# next line uses command substitution
# Just checking that the segments are the same in pem vs. stm.
! cmp <(awk '{print $1}' $dir/text.all) <(awk '{print $1}' $dir/segments) && \
   echo "Segments from stm file and stm file do not match." && exit 1;

grep -v IGNORE_TIME_SEGMENT_ $dir/text.all | perl local/text2lower.pl > $dir/text
   
# create an utt2spk file that assumes each conversation side is
# a separate speaker.
awk '{spk=$2; sub(/BABEL_BP_107_/,"",spk); sub(/\|([A|B])\|.*$/,"-\1",spk); print $1,spk;}' $dir/segments > $dir/utt2spk  
utils/utt2spk_to_spk2utt.pl $dir/utt2spk > $dir/spk2utt

# cp $dir/segments $dir/segments.tmp
# awk '{x=$3-0.05; if (x<0.0) x=0.0; y=$4+0.05; print $1, $2, x, y; }' \
#   $dir/segments.tmp > $dir/segments

awk '{print $1}' $dir/wav.scp \
  | perl -ane '$_ =~ m:^(\S+)\|([AB])\|(.*)$: || die "bad label $_"; 
               print "$1|$2|$3 $1_$3";
               print "_inLine 1\n" if ($2 eq "A");
               print "_outLine 1\n" if ($2 eq "B");' \
  > $dir/reco2file_and_channel || exit 1;

dest=data/$name
mkdir -p $dest
for x in wav.scp segments text utt2spk spk2utt stm reco2file_and_channel; do
  cp $dir/$x $dest/$x
done

echo Data preparation and formatting completed for Babel107 Vietnamese $name 
echo "(but not MFCC extraction)"

