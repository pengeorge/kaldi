#/bin/bash

# Copyright 2014  MSIIP, Tsinghua University (Author: Zhipeng Chen)
# Apache 2.0.

set -e
set -o pipefail


runat=/home/kaldi/code/kaldi-trunk/egs/babel/bnbc
echo $0 "$@" > /dev/null
pushd $runat > /dev/null

. ./demo.conf || exit 1;
. ./id2host.conf || exit 1;
. ./lang.conf || exit 1;

#cmd=$decode_cmd
help_message="Usage: $0 <keyword>" 

[ -f ./path.sh ] && . ./path.sh; # source the path.
. ./utils/parse_options.sh

if [ $# -ne 1 ]; then
  printf "FATAL: invalid number of arguments.\n\n"
  printf "$help_message\n"
  exit 1;
fi

kw=$1
fname=kw_`date | md5sum | cut -d' ' -f 1`
datatype=`echo $indexdir | grep -Po '(?<=/decode_)[^\.]+\.[^_]+(?=_)'`
if [[ $indexdir =~ remake ]]; then
    root=${indexdir}/../../../../..
    kwdir=`dirname $indexdir | sed 's:kws_indices:online_kws:'`
else
    root=${indexdir}/../../../..
    kwdir=`echo $indexdir | sed 's:kws_indices:online_kws:'`
fi
kwsdatadir=$root/data/$datatype/kws # TODO

if $chinese_like; then
    perl ./czpScripts/demo/expand.pl "$kw" |\
        awk '{print NR"\t"$0;}' > $kwdir/${fname}.txt
else
    cat "1\t$kw" > $kwdir/${fname}.txt
fi

if  $case_insensitive && ! $use_icu  ; then
  cat $kwdir/${fname}.txt | tr '[:lower:]' '[:upper:]'  | \
    sym2int.pl --map-oov 0 -f 2- $kwsdatadir/words.txt > $kwdir/${fname}_all.int
elif  $case_insensitive && $use_icu ; then
  paste <(cut -f 1  $kwdir/${fname}.txt  ) \
        <(cut -f 2  $kwdir/${fname}.txt | uconv -f utf8 -t utf8 -x "${icu_transform}" ) |\
    local/kwords2indices.pl --map-oov 0  $kwsdatadir/words.txt > $kwdir/${fname}_all.int
else
  cp $langdir/words.txt  $kwsdatadir/words.txt
  cat $kwdir/${fname}.txt | \
    sym2int.pl --map-oov 0 -f 2- $kwsdatadir/words.txt > $kwdir/${fname}_all.int
fi

(cat $kwdir/${fname}_all.int | \
  grep -v " 0 " | grep -v " 0$" > $kwdir/${fname}.int ) || true

  # is IV
  # Compile keywords into FSTs  TODO
  if [ -z $silence_word ]; then
    transcripts-to-fsts ark:$kwdir/${fname}.int ark,t:$kwdir/${fname}.fsts 
  else
    silence_int=`grep -w $silence_word $langdir/words.txt | awk '{print $2}'`
    [ -z $silence_int ] && \
       echo "$0: Error: could not find integer representation of silence word $silence_word" && exit 1;
    transcripts-to-fsts ark:$kwdir/${fname}.int ark,t:- | \
      awk -v 'OFS=\t' -v silint=$silence_int '{if (NF == 4 && $1 != 0) { print $1, $1, silint, silint; } print; }' \
       > $kwdir/${fname}.fsts
  fi


# czpScripts/kws/kws_search.chenzp.sh
#czpScripts/kws/kws_search.chenzp.sh --cmd "run.pl" --max-states 150000 \
#    --min-lmwt ${lmwt} --max-lmwt ${lmwt} --skip-scoring true \
#    --indices-dir $indexdir $root/data/lang $root/data/$datatype/$kwsdirname ${indexdir}_${lmwt}/..
kwsdir=$kwdir/${fname}
#steps/search_index.sh --cmd "run.pl" --indices-dir $indexdir \
#    --strict false $kwsdatadir $kwsdir  || exit 1

mkdir -p $kwsdir/log;
if [ -z "$nj" ]; then
    nj=`cat $indexdir/num_jobs` || exit 1;
fi
echo "Running search..." >&2
#$cmd JOB=1:$nj $kwsdir/log/search.JOB.log \
#  kws-search-client serverx22 $[6000+JOB] $kwsdir
for JOB in `seq 1 $nj`; do
    kws-search-client ${id2host[$JOB]} $[6000+$JOB] $kwsdir 2> $kwsdir/log/search.$JOB.log > $kwsdir/result.$JOB &
done
wait;

#$cmd JOB=1:$nj $kwsdir/log/search.JOB.log \
#  kws-search --strict=false --negative-tolerance=-1 \
#  "ark:gzip -cdf $indexdir/index.JOB.gz|" ark:$kwdir/${fname}.fsts \
#  "ark,t:|int2sym.pl -f 2 $kwsdatadir/utter_id > $kwsdir/result.JOB" || exit 1;

if [ -f $kwsdir/result.1 ]; then
    echo "Running normalization..." >&2
    cat $kwsdir/result.* | int2sym.pl -f 2 $kwsdatadir/utter_id |\
      czpScripts/kws/write_kwslist.chenzp.pl  --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=`cat $kwsdatadir/duration` \
      --segments=$kwsdatadir/../segments --normalize=$norm_method --duptime=$duptime --remove-dup=true --remove-NO=true \
      --map-utter=$kwsdatadir/utter_map --digits=3 \
      - ${kwsdir}/kwslist.xml || exit 1
    cat ${kwsdir}/kwslist.xml
else
    exit 1
fi
popd >/dev/null
