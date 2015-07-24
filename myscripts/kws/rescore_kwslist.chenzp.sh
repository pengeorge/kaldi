#!/bin/bash

# Mar 6,2014  Author: chenzp

help_message="$(basename $0): 
             Usage:
                 $(basename $0) <data-dir> <decode-dir>"

# Begin configuration section.  
method=burst # KST
alpha=0.2
rescore_threshold=0.1
lexicon=
suffix=
min_lmwt=11
max_lmwt=11
cmd=run.pl
kwsout_dir=
newout_dir=
stage=0
suffix=  # e.g. model name, kws dir name is kws_$suffix. Because different model may lead to different keywords FSTs (such as phone confusion)   (chenzp, Jan 19,2014)
extraid=
skip_scoring=false
# End configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

set -u
set -e
set -o pipefail

if [[ "$#" -ne "2" ]] ; then
    echo -e "$0: FATAL: wrong number of script parameters!\n\n"
    printf "$help_message\n\n"
    exit 1;
fi

datadir=$1
decodedir=$2

if [ -z $suffix ] ; then
    basekwsdir=kws
else
    basekwsdir=kws_$suffix
fi
if [ -z $extraid ] ; then
  kwsdatadir=$datadir/$basekwsdir
else
  kwsdatadir=$datadir/${extraid}_$basekwsdir
fi

if [ -z $kwsout_dir ] ; then
  if [[ "$method" =~ ^burst ]]; then
    this_method="${method}${alpha}"
  else
    this_method=${method}
  fi
  if [ -z $extraid ] ; then
    kwsoutdir=$decodedir/$basekwsdir
    newoutdir=$decodedir/rescore_kwslist-$this_method/$basekwsdir
  else
    kwsoutdir=$decodedir/${extraid}_$basekwsdir
    newoutdir=$decodedir/rescore_kwslist-$this_method/${extraid}_$basekwsdir
  fi
else
  kwsoutdir=$kwsout_dir
fi

if [ ! -z $newout_dir ]; then
  newoutdir=$newout_dir
fi

for d in "$datadir" "$kwsdatadir" "$kwsoutdir"; do
  if [ ! -d "$d" ]; then
    echo "$0: FATAL: expected directory $d to exist"
    exit 1;
  fi
done

if [[ ! -f "$kwsdatadir/ecf.xml"  ]] ; then
    echo "$0: FATAL: the $kwsdatadir does not contain the ecf.xml file"
    exit 1;
fi

echo $kwsdatadir
duration=`head -1 $kwsdatadir/ecf.xml |\
    grep -o -E "duration=\"[0-9]*[    \.]*[0-9]*\"" |\
    perl -e 'while($m=<>) {$m=~s/.*\"([0-9.]+)\".*/\1/; print $m/2;}'`

echo "Duration: $duration"

if [ $stage -le 0 ]; then
    echo "Rescoring results will be in $newoutdir"
    mkdir -p $newoutdir
fi

if [ $stage -le 1 ]; then
  if true; then
    flag=
  else
    flag="--all-YES true"  # TODO we haven't thought about how to set a threshold
                           # in these methods, just return all and ignore ATWV.
  fi
  if [[ "$method" =~ ^burst ]]; then
    flag="$flag --alpha=$alpha"
  fi
  if [[ "$method" =~ ^docsim ]]; then
    if [ ! -f ${decodedir}/fullvocab_kws/.done.tfidf${alpha} ]; then
      $cmd LMWT=$min_lmwt:$max_lmwt ${decodedir}/fullvocab_kws/est_tfidf${alpha}.LMWT.log \
        perl ./czpScripts/kws/est_tfidf.pl --lexicon "$lexicon" --alpha $alpha ${decodedir}/fullvocab_kws_LMWT/kwslist.unnormalized.xml data/train/df.txt ${decodedir}/fullvocab_kws_LMWT/tf${alpha}.txt ${decodedir}/fullvocab_kws_LMWT/tfidf${alpha}.txt
      touch ${decodedir}/fullvocab_kws/.done.tfidf${alpha}
    fi
    if [ ! -f ${decodedir}/fullvocab_kws/.done.${method} ]; then
      $cmd LMWT=$min_lmwt:$max_lmwt ${decodedir}/fullvocab_kws/calc_${method}.LMWT.log \
        perl czpScripts/kws/calc_doc_sim.pl '<' ${decodedir}/fullvocab_kws_LMWT/tfidf${alpha}.txt '>' ${decodedir}/fullvocab_kws_LMWT/${method}.txt
      touch ${decodedir}/fullvocab_kws/.done.${method}      
    fi
    flag="$flag --docsimfile=${decodedir}/fullvocab_kws_LMWT/${method}.txt"
  fi
  echo "Writing $method rescoring results"
  $cmd LMWT=$min_lmwt:$max_lmwt ${newoutdir}/rescore.LMWT.log \
    set -e ';' set -o pipefail ';'\
    mkdir -p ${newoutdir}_LMWT ';' \
      perl czpScripts/kws/rescore.pl --flen=0.01 --duration=$duration \
        --segments=$datadir/segments --method=$method --rescore-threshold $rescore_threshold \
        $flag \
        ${kwsoutdir}_LMWT/kwslist.unnormalized.xml ${newoutdir}_LMWT/kwslist.unnormalized.xml || exit 1
fi

if [ -z $extraid ] ; then
  extraid_flags=
else
  extraid_flags="  --extraid ""$extraid"" "
fi

if [ $stage -le 3 ]; then
  if [[ (! -x czpScripts/kws/kws_score.chenzp.sh ) ]] ; then
    echo "Not scoring, because the file czpScripts/kws/kws_score.chenzp.sh is not present"
  elif [[ $skip_scoring == true ]] ; then
    echo "Not scoring, because --skip-scoring true was issued"
  else
    echo "Scoring KWS results"
    if [ -z $suffix ] ; then
      suffix_flags=
    else
      suffix_flags="  --suffix ""$suffix"" "
    fi
    $cmd LMWT=$min_lmwt:$max_lmwt ${newoutdir}/scoring.LMWT.log \
       czpScripts/kws/kws_score.chenzp.sh --fast true $suffix_flags $extraid_flags \
          $datadir ${newoutdir}_LMWT || exit 1;
  fi
fi

exit 0
