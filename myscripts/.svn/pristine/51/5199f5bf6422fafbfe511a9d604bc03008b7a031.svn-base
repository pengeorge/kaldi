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
norm_method=kaldi
stage=0
suffix=  # e.g. model name, kws dir name is kws_$suffix. Because different model may lead to different keywords FSTs (such as phone confusion)   (chenzp, Jan 19,2014)
extraid=
ntrue_scale=1.0
skip_scoring=false
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

subsetfile=$datadir/subsets/$subsetid.xml

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
    kwsindir=$decodedir/$basekwsdir
    kwsoutdir=$decodedir/$subdir/$basekwsdir
  else
    kwsindir=$decodedir/${extraid}_$basekwsdir
    kwsoutdir=$decodedir/$subdir/${extraid}_$basekwsdir
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

if [ ! -f ${kwsoutdir}_$min_param/result.1 ]; then
  if [ $stage -le 1 ]; then
      echo "Filtering kwslist to generate subset kwslist"
      $cmd PARAM=$min_param:$max_param ${kwsoutdir}/subset.$subsetid.PARAM.log \
        czpScripts/local/subset_kws.sh --outdir ${kwsoutdir}_PARAM/$subsetid $subsetid $datadir ${kwsindir}_PARAM
  fi
else
  if [ $stage -le 0 ]; then
      echo "Filtering raw results to generate subset results"
      $cmd PARAM=$min_param:$max_param ${kwsoutdir}/subset.$subsetid.PARAM.log \
        czpScripts/local/subset_kws.sh --outdir ${kwsoutdir}_PARAM/$subsetid $subsetid $datadir ${kwsindir}_PARAM
#      set -e ';' set -o pipefail ';'\
#      if \[ ! -d ${kwsoutdir}_PARAM/$subsetid \]';' then mkdir ${kwsoutdir}_PARAM/$subsetid ';'fi ';' \
#      grep -Pf \<\(grep -Po \'\(?\<=\<kw kwid=\"\)[^\"]\(?=\"\)\' $subsetfile \| awk \'{print \"^\"\\$\0}\'\) \
#        ${kwsoutdir}_PARAM/result.* \> ${kwsoutdir}_PARAM/$subsetid/result || exit 1
  fi

  if [ $stage -le 1 ]; then
    if [ "$norm_method" != "skip" ]; then
      echo "Writing $norm_method normalized results"
    else
      echo "Writing unnormalized results"
    fi
    if [[ "$norm_method" =~ ^kaldi ]] || [ "$norm_method" == 'KST' ]; then
      flag=
    else
      flag="--all-YES true"  # TODO we haven't thought about how to set a threshold
                             # in these methods, just return all and ignore ATWV.
    fi
    $cmd PARAM=$min_param:$max_param ${kwsoutdir}/write_normalized.$subsetid.PARAM.log \
      set -e ';' set -o pipefail ';'\
      cat ${kwsoutdir}_PARAM/$subsetid/result \| \
        czpScripts/kws/write_kwslist.chenzp.pl  --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=$duration \
          --segments=$datadir/segments --normalize=$norm_method --duptime=$duptime --remove-dup=true\
          --map-utter=$kwsdatadir/utter_map $flag \
          - ${kwsoutdir}_PARAM/$subsetid/kwslist.xml || exit 1
  fi

  if [ $stage -le 2 ]; then
    echo "Writing unnormalized results"
    $cmd PARAM=$min_param:$max_param ${kwsoutdir}/write_unnormalized.$subsetid.PARAM.log \
      set -e ';' set -o pipefail ';'\
      cat ${kwsoutdir}_PARAM/$subsetid/result \| \
          czpScripts/kws/write_kwslist.chenzp.pl --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=$duration \
            --segments=$datadir/segments --normalize=skip --duptime=$duptime --remove-dup=true\
            --map-utter=$kwsdatadir/utter_map \
            - ${kwsoutdir}_PARAM/$subsetid/kwslist.unnormalized.xml || exit 1;
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
    echo "Scoring KWS results"
    if [ -z $suffix ] ; then
      suffix_flags=
    else
      suffix_flags="  --suffix ""$suffix"" "
    fi
    $cmd PARAM=$min_param:$max_param ${kwsoutdir}/scoring.$subsetid.PARAM.log \
       czpScripts/kws/kws_score.chenzp.sh $suffix_flags $extraid_flags \
         --kwlist $subsetfile  $datadir ${kwsoutdir}_PARAM/$subsetid || exit 1;
  fi
fi

exit 0
