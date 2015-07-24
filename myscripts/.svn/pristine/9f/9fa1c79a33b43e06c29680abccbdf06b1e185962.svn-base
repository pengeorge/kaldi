#/bin/bash 

# Copyright 2014  MSIIP, Tsinghua University (Author: Zhipeng Chen)
# Apache 2.0.

set -e
set -o pipefail

tgtdir=/media/kws_demo
remake=false
use_icu=true
icu_transform="Any-Lower"
silence_word=  # Optional silence word to insert (once) between words of the transcript.

echo $0 "$@"

. conf/common_vars_leave1q.sh || exit 1;
. ./lang.conf || exit 1;

help_message="Usage: kws_demo_prep.sh <index-dir>" 

[ -f ./path.sh ] && . ./path.sh; # source the path.
. ./utils/parse_options.sh

if [ $# -ne 1 ]; then
  printf "FATAL: invalid number of arguments.\n\n"
  printf "$help_message\n"
  exit 1;
fi

indexdir=$1

if [ ! -f "$indexdir/index.1.gz" ]; then
  echo "Index dir does not exist. Run run-4-anydecode first."
  exit 1;
fi

if [[ ! $indexdir =~ ^/ ]]; then
  echo "Index dir should be given as a full path (starting with '/')"
  exit 1;
fi

datatype=`echo $indexdir | grep -Po '(?<=/decode_)[^\.]+\.[^_]+(?=_)'`
echo "datatype=$datatype"
#decode=$(basename $(dirname $indexdir) | sed "s:^decode_::")_$lmwt
#sys=$(basename $(dirname $(dirname $(dirname $indexdir)
indexTgtDir=${tgtdir}/`echo $indexdir | sed 's:^.*/egs/babel/::'`
mkdir -p $indexTgtDir
cp $indexdir/index.*.gz $indexTgtDir/
cp $indexdir/num_jobs $indexTgtDir/
srcRoot=$indexdir/../../../..
destRoot=$indexTgtDir/../../../..
orgIndexDir=$indexdir # index without remake
if $remake; then
    srcRoot=${srcRoot}/..
    destRoot=${destRoot}/..
    orgIndexDir=`dirname $indexdir`
fi
kwsdirname=kws # TODO if expansion, plus suffix
kwsdatadir=$destRoot/data/$datatype/$kwsdirname
mkdir -p $kwsdatadir
# copy related files (words.txt, L1, E, ...)
srckwsdatadir=$srcRoot/data/$datatype/$kwsdirname
for f in {words.txt,utter_id,utter_map}; do
  cp $srckwsdatadir/$f $kwsdatadir/
done
cp $srckwsdatadir/../segments $kwsdatadir/../
mkdir -p $destRoot/data/lang/phones
cp $srcRoot/data/lang/phones/word_boundary.int $destRoot/data/lang/phones/
cp $srcRoot/data/lang/words.txt $destRoot/data/lang/
kwsoutdir=`echo $indexTgtDir | sed 's:kws_indices:online_kws:'`
echo $kwsoutdir
mkdir -p $kwsoutdir
chmod 777 $kwsoutdir

# Calculate duration
#head -1 $srckwsdatadir/ecf.xml |\
#    grep -o -E "duration=\"[0-9]*[    \.]*[0-9]*\"" |\
#    perl -e 'while($m=<>) {$m=~s/.*\"([0-9.]+)\".*/\1/; print $m/2;}' > $kwsdatadir/duration
echo "Generating duration from $kwsdatadir/../segments"
awk 'BEGIN{dur=0;}{dur += $4 - $3; }END{printf "%d",dur;}' $kwsdatadir/../segments > $kwsdatadir/duration

lmwt=`echo $orgIndexDir | grep -Po '(?<=_)\d+$'`
echo "Generating utter_one_best from $orgIndexDir/../score_$lmwt/$datatype.utt.ctm"
cat $orgIndexDir/../score_$lmwt/$datatype.utt.ctm | awk 'BEGIN{utt=""}{if (utt==$1) {printf " "$5;} else {utt=$1;printf "\n"$1"\t"$5;}}' | sed '1d' > $indexTgtDir/utter_one_best


#if  $case_insensitive && ! $use_icu  ; then
#  echo "$0: Running case insensitive processing"
#  cat $langdir/words.txt | tr '[:lower:]' '[:upper:]'  > $kwsdatadir/words.txt
#  [ `cut -f 1 -d ' ' $kwsdatadir/words.txt | sort -u | wc -l` -ne `cat $kwsdatadir/words.txt | wc -l` ] && \
#    echo "$0: Warning, multiple words in dictionary differ only in case: " 
#elif  $case_insensitive && $use_icu ; then
#  echo "$0: Running case insensitive processing (using ICU with transform \"$icu_transform\")"
#  cat $langdir/words.txt | uconv -f utf8 -t utf8 -x "${icu_transform}"  > $kwsdatadir/words.txt
#  [ `cut -f 1 -d ' ' $kwsdatadir/words.txt | sort -u | wc -l` -ne `cat $kwsdatadir/words.txt | wc -l` ] && \
#    echo "$0: Warning, multiple words in dictionary differ only in case: " 
#else
#  cp $langdir/words.txt  $kwsdatadir/words.txt
#fi

