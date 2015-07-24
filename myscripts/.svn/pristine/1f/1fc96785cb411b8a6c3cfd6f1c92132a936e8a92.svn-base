#!/bin/bash

# Mar 5,2014  Author: chenzp

help_message="$(basename $0): 
             Usage:
                 $(basename $0) <subset-id> <data-dir> <decode-dir>"

# Begin configuration section.  
min_lmwt=7   # TODO this option should be replaced by min_param, keep here for compatible
max_lmwt=17
min_param=
max_param=
duptime=0.6
cmd=run.pl
kwsout_dir=
subdir=   # for extra normalization methods, results will be put into a subdir of decode dir
          # if no subdir, just set empty.
norm_method=kaldi2
stage=0
suffix=  # e.g. model name, kws dir name is kws_$suffix. Because different model may lead to different keywords FSTs (such as phone confusion)   (chenzp, Jan 19,2014)
extraid=
ntrue_scale=1.0
skip_scoring=false
oov=false
# End configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

set -u
set -e
set -o pipefail

if [[ "$#" -ne "3" ]] ; then
    echo -e "$0: FATAL: wrong number of script parameters!\n\n"
    printf "$help_message\n\n"
    exit 1;
fi

subsetid=$1
datadir=$2
decodedir=$3

if [[ $subsetid =~ \. ]]; then
  extraid=${subsetid%%.*}
  subsettype=${subsetid##*.}
else
  extraid=
  subsettype=$subsetid
fi
subsetfile=$datadir/subsets/${subsetid}.xml
if $oov; then
  if [ -z $extraid ]; then
    extraid=oov
  else
    extraid=${extraid}_oov
  fi
fi

if [ -z $extraid ] && [ ! -f $decodedir/.done.kws ] \
  || [ ! -z $extraid ] && [ ! -f $decodedir/.done.kws.$extraid ]; then
  echo "[WARNING] KWS for '$extraid' is not ready. Ignore subseting $subsetid."
  exit 1;
fi

if [ -z "$min_param" ]; then
  min_param=$min_lmwt
fi
if [ -z "$max_param" ]; then
  max_param=$max_lmwt
fi

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
  if [ -z $extraid ] ; then
#    kwsindir=$decodedir/$basekwsdir
    kwsoutdir=$decodedir/$subdir/$basekwsdir
    kwsindir=$kwsoutdir
  else
#    kwsindir=$decodedir/${extraid}_$basekwsdir
    kwsoutdir=$decodedir/$subdir/${extraid}_$basekwsdir
    kwsindir=$kwsoutdir
  fi
else
  kwsoutdir=$kwsout_dir
  kwsindir=$kwsoutdir
fi

mkdir -p $kwsoutdir

for d in "$datadir" "$kwsdatadir" "$kwsindir" "$kwsoutdir"; do
  if [ ! -d "$d" ]; then
    echo "$0: FATAL: expected directory $d to exist"
    exit 1;
  fi
done

if [ ! -f "$subsetfile" ]; then
    echo "$0: FATAL: expected subset keyword id list file $subsetfile"
    exit 1;
fi

if [[ ! -f "$kwsdatadir/ecf.xml"  ]] ; then
    echo "$0: FATAL: the $kwsdatadir does not contain the ecf.xml file"
    exit 1;
fi

echo $kwsdatadir
duration=`head -1 $kwsdatadir/ecf.xml |\
    grep -o -E "duration=\"[0-9]*[    \.]*[0-9]*\"" |\
    perl -e 'while($m=<>) {$m=~s/.*\"([0-9.]+)\".*/\1/; print $m/2;}'`

#duration=`head -1 $kwsdatadir/ecf.xml |\
#    grep -o -E "duration=\"[0-9]*[    \.]*[0-9]*\"" |\
#    grep -o -E "[0-9]*[\.]*[0-9]*" |\
#    perl -e 'while(<>) {print $_/2;}'`

echo "Duration: $duration"

mem_est_factor=500
#if [ ! -f ${kwsindir}_$min_param/result.1 ]; then
if [ -f ${kwsindir}_$min_param/kwslist.xml ]; then
  line=`grep '<kw ' ${kwsoutdir}_$min_param/kwslist.xml | wc -l`
else
  line=`cat ${kwsoutdir}_$min_param/result.* | wc -l`
fi
mem_est=`echo $line | perl -e '$num=<>; chomp($num); printf "%d", $num/'$mem_est_factor';'`
echo "$subsetid ($extraid): The estimated memory usage is $mem_est MB"
cmd="`echo "$cmd" | sed 's:ram_free=[0-9]\+M:ram_free='$mem_est'M:' | sed 's:mem_free=[0-9]\+M:mem_free='$mem_est'M:'`"

#if [ ! -f ${kwsindir}_$min_param/result.1 ]; then
if [ -f ${kwsindir}_$min_param/kwslist.xml ]; then # We prefer using kwslist.xml
  if [ $stage -le 1 ]; then
    # When using kwslist.xml to subset, the script write_kwslist.pl would not be called.
    echo "$subsetid ($extraid): Filtering kwslist to generate subset kwslist"
      $cmd PARAM=$min_param:$max_param ${kwsoutdir}/subset.${subsettype}.PARAM.log \
        czpScripts/local/subset_kws.sh --use-raw false --outdir ${kwsoutdir}_PARAM/$subsettype $subsetid $datadir ${kwsindir}_PARAM
  fi
else # using result.*, which is more memory consuming. NOT RECOMMENDED!!!
  if [ $stage -le 0 ]; then
    echo "$subsetid ($extraid): Filtering raw results to generate subset results"
      $cmd PARAM=$min_param:$max_param ${kwsoutdir}/subset.${subsettype}.PARAM.log \
        czpScripts/local/subset_kws.sh --use-raw true --outdir ${kwsoutdir}_PARAM/$subsettype $subsetid $datadir ${kwsindir}_PARAM
#      set -e ';' set -o pipefail ';'\
#      if \[ ! -d ${kwsoutdir}_PARAM/$subsettype \]';' then mkdir ${kwsoutdir}_PARAM/$subsettype ';'fi ';' \
#      grep -Pf \<\(grep -Po \'\(?\<=\<kw kwid=\"\)[^\"]\(?=\"\)\' $subsetfile \| awk \'{print \"^\"\\$\0}\'\) \
#        ${kwsoutdir}_PARAM/result.* \> ${kwsoutdir}_PARAM/$subsettype/result || exit 1
  fi

  if [ $stage -le 1 ]; then
    if [ "$norm_method" != "skip" ]; then
      echo "$subsetid ($extraid): Writing $norm_method normalized results"
    else
      echo "$subsetid ($extraid): Writing unnormalized results"
    fi
    if [[ "$norm_method" =~ ^kaldi ]] || [ "$norm_method" == 'KST' ]; then
      flag=
    else
      flag="--all-YES true"  # TODO we haven't thought about how to set a threshold
                             # in these methods, just return all and ignore ATWV.
    fi
    $cmd PARAM=$min_param:$max_param ${kwsoutdir}/write_normalized.${subsettype}.PARAM.log \
      set -e ';' set -o pipefail ';'\
      cat ${kwsoutdir}_PARAM/$subsettype/result \| \
        czpScripts/kws/write_kwslist.chenzp.pl  --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=$duration \
          --segments=$datadir/segments --normalize=$norm_method --duptime=$duptime --remove-dup=true\
          --map-utter=$kwsdatadir/utter_map $flag --digits=3 \
          - ${kwsoutdir}_PARAM/$subsettype/kwslist.xml || exit 1
  fi

  if [ $stage -le 2 ]; then
    echo "$subsetid ($extraid): Writing unnormalized results"
    $cmd PARAM=$min_param:$max_param ${kwsoutdir}/write_unnormalized.${subsettype}.PARAM.log \
      set -e ';' set -o pipefail ';'\
      cat ${kwsoutdir}_PARAM/$subsettype/result \| \
          czpScripts/kws/write_kwslist.chenzp.pl --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=$duration \
            --segments=$datadir/segments --normalize=skip --duptime=$duptime --remove-dup=true\
            --map-utter=$kwsdatadir/utter_map \
            - ${kwsoutdir}_PARAM/$subsettype/kwslist.unnormalized.xml || exit 1;
  fi
fi


if [ -z $extraid ] ; then
  extraid_flags=
else
  extraid_flags="  --extraid ""$extraid"" "
fi

if [ $stage -le 3 ] && ! $skip_scoring ; then
  if [[ (! -x czpScripts/kws/kws_score.chenzp.sh ) ]] ; then
    echo "Not scoring, because the file czpScripts/kws/kws_score.chenzp.sh is not present"
  else
    echo "$subsetid ($extraid): Scoring KWS results"
    if [ -z $suffix ] ; then
      suffix_flags=
    else
      suffix_flags="  --suffix ""$suffix"" "
    fi
    $cmd PARAM=$min_param:$max_param ${kwsoutdir}/scoring.${subsettype}.PARAM.log \
       czpScripts/kws/kws_score.chenzp.sh $suffix_flags $extraid_flags \
         --kwlist $subsetfile  $datadir ${kwsoutdir}_PARAM/$subsettype || exit 1;
  fi
fi

exit 0
