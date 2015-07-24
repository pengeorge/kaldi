#!/bin/bash

# Copyright 2012  Johns Hopkins University (Author: Guoguo Chen, Yenda Trmal)
# Apache 2.0.


help_message="$(basename $0): do keyword indexing and search.  data-dir is assumed to have
                 kws/ subdirectory that specifies the terms to search for.  Output is in
                 decode-dir/kws/
             Usage:
                 $(basename $0) <lang-dir> <data-dir> <decode-dir>"

# Begin configuration section.  
#acwt=0.0909091
min_lmwt=7
max_lmwt=17
duptime=0.6
cmd=run.pl
model=
index_only=false
skip_scoring=false
skip_optimization=false # true can speed it up if #keywords is small.
max_states=150000
indices_dir=
kwsout_dir=
stage=0
word_ins_penalty=0
suffix=  # e.g. model name, kws dir name is kws_$suffix. Because different model may lead to different keywords FSTs (such as phone confusion)   (chenzp, Jan 19,2014)
         # e.g.2 if we do expansion on IVs, the keyword FSTs should be put into a different directory (chenzp, Mar 21,2014)
extraid=
norm_method=kaldi2
silence_word=  # specify this if you did to in kws_setup.sh, it's more accurate.
ntrue_scale=1.0
max_silence_frames=50

parallel_thres_mem=5000  # if the estimated memory > this value, the work from result.* to kwslist.*.xml
                          # would be run in parallel.
#kwlist_nj=96  # number of jobs for generating kwslist

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

silence_opt=

langdir=$1
datadir=$2
decodedir=$3

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
    kwsoutdir=$decodedir/$basekwsdir
  else
    kwsoutdir=$decodedir/${extraid}_$basekwsdir
  fi
else
  kwsoutdir=$kwsout_dir
fi
mkdir -p $kwsoutdir

if [ -z $indices_dir ]; then
  indices_dir=$kwsoutdir
fi

for d in "$datadir" "$kwsdatadir" "$langdir" "$decodedir"; do
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

#duration=`head -1 $kwsdatadir/ecf.xml |\
#    grep -o -E "duration=\"[0-9]*[    \.]*[0-9]*\"" |\
#    grep -o -E "[0-9]*[\.]*[0-9]*" |\
#    perl -e 'while(<>) {print $_/2;}'`

echo "Duration: $duration"

if [ ! -z "$model" ]; then
    model_flags="--model $model"
else
    model_flags=
fi
  

if false; then
  #TODO remove indexing code
if [ $stage -le 0 ] ; then
  if [ ! -f $indices_dir/.done.index ] ; then
    [ ! -d $indices_dir ] && mkdir  $indices_dir
    for lmwt in `seq $min_lmwt $max_lmwt` ; do
        indices=${indices_dir}_$lmwt
        mkdir -p $indices
  
        acwt=`perl -e "print (1.0/$lmwt);"` 
        [ ! -z $silence_word ] && silence_opt="--silence-word $silence_word"
        czpScripts/kws/make_index.chenzp.sh $silence_opt --cmd "$cmd" --acwt $acwt $model_flags\
          --skip-optimization $skip_optimization --max-states $max_states \
          --word-ins-penalty $word_ins_penalty --max-silence-frames $max_silence_frames\
          $datadir $langdir $decodedir $indices  || exit 1
    done
    touch $indices_dir/.done.index
  else
    echo "Assuming indexing has been aready done. If you really need to re-run "
    echo "the indexing again, delete the file $indices_dir/.done.index"
  fi
fi

if $index_only; then
  exit 0;
fi

fi

if [ $stage -le 1 ]; then
  for lmwt in `seq $min_lmwt $max_lmwt` ; do
      kwsoutput=${kwsoutdir}_$lmwt
      indices=${indices_dir}_$lmwt
      [ -d $kwsoutput ] && [ -f $kwsoutput/.done.search ] && continue;
      mkdir -p $kwsoutdir
      czpScripts/steps/search_index.chenzp.sh --cmd "$cmd" --indices-dir $indices \
        --strict false \
        $kwsdatadir $kwsoutput  || exit 1
      touch $kwsoutput/.done.search
  done
fi

kwlist_nj=`ls ${kwsoutdir}_${min_lmwt}/result.* | grep -Po '(?<=result\.)\d+(?=$)' | sort -nr | head -n 1`
mem_est=`cat ${kwsoutdir}_$min_lmwt/result.* | wc -l | perl -e '$num=<>; chomp($num); printf "%d", $num/1000;'`
echo "The estimated memory usage is $mem_est MB"
if [ $mem_est -gt $parallel_thres_mem ]; then
  mem_per_job=`perl -e 'printf "%d", '$mem_est'/'$kwlist_nj';'`
  echo "will write kwslist file in parallel, average memory of each job is about $mem_per_job MB"
  cmd="`echo "$cmd" | sed 's:ram_free=[0-9]\+M:ram_free='$mem_per_job'M:' | sed 's:mem_free=[0-9]\+M:mem_free='$mem_per_job'M:'`"
  . czpScripts/local/datasets/split_kwlist.sh
  for lmwt in `seq $min_lmwt $max_lmwt`; do
    ressplitdir=${kwsoutdir}_${lmwt}/split${kwlist_nj}
    [ -f $ressplitdir/.done.resplit ] && continue;
    echo "Re-splitting result.* by kwlist $lmwt/$max_lmwt"
    mkdir -p $ressplitdir/tmp
    #set +e;
    #for JOB in `seq 1 $kwlist_nj`; do
    #  grep -h -f $splitdir/kwlist.$JOB ${kwsoutdir}_${lmwt}/result.* > $ressplitdir/result.$JOB
    #done
    #$cmd JOB=1:$kwlist_nj $kwsoutdir/resplit_result.${lmwt}.JOB.log \
    #  grep -h -f $splitdir/kwlist.JOB ${kwsoutdir}_${lmwt}/result.* '>' $ressplitdir/result.JOB
    #set -e;
    echo "  split by kwid"
    rm -rf $ressplitdir/tmp
    mkdir -p $ressplitdir/tmp
    for JOB in `seq 1 $kwlist_nj`; do
      if [ $JOB == 1 ]; then
        osym='>'
      else
        osym='>>'
      fi
      perl -e '
      open(IN, "'${kwsoutdir}_${lmwt}/result.$JOB'") or die "cannot open file result.'$JOB'\n";
      my %res;
      while (my $line = <IN>) {
        my @col = split(/ /, $line);
        if (!defined($res{$col[0]})) {
          $res{$col[0]} = $line;
        } else {
          $res{$col[0]} .= $line;
        }
      }
      close(IN);
      for (keys %res) {
        open(OUT, "'${osym}$ressplitdir/tmp/'$_") or die "cannot open output file: '${osym}$ressplitdir/tmp/'$_\n";
        print OUT $res{$_};
        close(OUT);
      }'
    done
    echo "  touch missing file"
    for f in `cat $splitdir/kwlist`; do
      if [ ! -f $ressplitdir/tmp/$f ]; then
        touch $ressplitdir/tmp/$f
      fi
    done
    echo "  merge keywords in each job"
    $cmd JOB=1:$kwlist_nj $kwsoutdir/resplit_result.${lmwt}.JOB.log \
       flist='`'cat $splitdir/kwlist.JOB \| tr \'\\n\' ' ' '`;' \
       pushd $ressplitdir/tmp ';' \
       cat \$flist '>' ../result.JOB ';' \
       popd
    rm -rf $ressplitdir/tmp
    org_res_num=`cat ${kwsoutdir}_${lmwt}/result.* | wc -l`
    resplit_res_num=`cat $ressplitdir/result.* | wc -l`
    if [ $org_res_num -ne $resplit_res_num ]; then
      echo "ERROR: results number are not equal: $resplit_res_num != $org_res_num"
      echo "There must be something wrong"
      exit 1
    else
      touch $ressplitdir/.done.resplit
    fi
  done
  # Re-estimated memory
  mem_per_job=`du -s $ressplitdir/result.* | cut -f 1 | sort -nr | head -n 1 |\
               perl -e '$num=<>; chomp($num); printf "%d", $num/100;'`
  echo "The re-estimated maximum memory usage of one job is $mem_per_job MB"
  if [ $mem_per_job -gt 30000 ]; then
    echo "$mem_per_job MB > 30000 MB, we'll force the requested memory as 30000MB."
    echo "  Please monitor if the scoring is out of memory."
    mem_per_job=30000
  fi
  cmd="`echo "$cmd" | sed 's:ram_free=[0-9]\+M:ram_free='$mem_per_job'M:' | sed 's:mem_free=[0-9]\+M:mem_free='$mem_per_job'M:'`"
  if [ $stage -le 2 ]; then
    for lmwt in `seq $min_lmwt $max_lmwt`; do
     [ -f ${kwsoutdir}_${lmwt}/split${kwlist_nj}/.done.write_norm ] && continue;
#    {
      ressplitdir=${kwsoutdir}_${lmwt}/split${kwlist_nj}
      echo "Writing $norm_method normalized results: lmwt = $lmwt/$max_lmwt"
      if [ ! -f $ressplitdir/.done.kwslist.norm.split ]; then
        $cmd JOB=1:$kwlist_nj $kwsoutdir/write_normalized.${lmwt}.JOB.log \
          set -e ';' set -o pipefail ';'\
          cat $ressplitdir/result.JOB \| \
          czpScripts/kws/write_kwslist.chenzp.pl  --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=$duration \
            --segments=$datadir/segments --normalize=$norm_method --duptime=$duptime --remove-dup=true\
            --map-utter=$datadir/kws_common/utter_map --digits=3 \
            - $ressplitdir/kwslist.JOB.xml || exit 1
        touch $ressplitdir/.done.kwslist.norm.split
      fi
      #This script consumes too much memory
      #czpScripts/local/merge_splitted_kwslists.pl $ressplitdir/kwslist.JOB.xml \
      #  ${kwsoutdir}_${lmwt}/kwslist.xml $kwlist_nj
      merged_file=${kwsoutdir}_${lmwt}/kwslist.xml
      sed '$d' $ressplitdir/kwslist.1.xml > $merged_file
      for JOB in `seq 2 $((kwlist_nj-1))`; do
        sed '1d;$d' $ressplitdir/kwslist.${JOB}.xml >> $merged_file
      done
      sed '1d' $ressplitdir/kwslist.${kwlist_nj}.xml >> $merged_file
      touch $ressplitdir/.done.write_norm
#    } &
    done
  fi
  wait;
  if [ $stage -le 3 ]; then
    for lmwt in `seq $min_lmwt $max_lmwt`; do
      [ -f ${kwsoutdir}_${lmwt}/split${kwlist_nj}/.done.write_unnorm ] && continue;
#    {
      ressplitdir=${kwsoutdir}_${lmwt}/split${kwlist_nj}
      echo "Writing unnormalized results: lmwt = $lmwt/$max_lmwt"
      $cmd JOB=1:$kwlist_nj $kwsoutdir/write_unnormalized.${lmwt}.JOB.log \
        set -e ';' set -o pipefail ';'\
        cat $ressplitdir/result.JOB \| \
            czpScripts/kws/write_kwslist.chenzp.pl --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=$duration \
              --segments=$datadir/segments --normalize=skip --duptime=$duptime --remove-dup=true\
              --map-utter=$datadir/kws_common/utter_map \
              - $ressplitdir/kwslist.unnormalized.JOB.xml || exit 1;

      merged_file=${kwsoutdir}_${lmwt}/kwslist.unnormalized.xml
      sed '$d' $ressplitdir/kwslist.unnormalized.1.xml > $merged_file
      for JOB in `seq 2 $((kwlist_nj-1))`; do
        sed '1d;$d' $ressplitdir/kwslist.unnormalized.${JOB}.xml >> $merged_file
      done
      sed '1d' $ressplitdir/kwslist.unnormalized.${kwlist_nj}.xml >> $merged_file
      touch $ressplitdir/.done.write_unnorm
      #czpScripts/local/merge_splitted_kwslists.pl $ressplitdir/kwslist.unnormalized.JOB.xml \
      #  ${kwsoutdir}_${lmwt}/kwslist.unnormalized.xml $kwlist_nj
#    } &
    done
  fi
  wait
else # No parallel
  cmd="`echo "$cmd" | sed 's:ram_free=[0-9]\+M:ram_free='$mem_est'M:' | sed 's:mem_free=[0-9]\+M:mem_free='$mem_est'M:'`"
  if [ $stage -le 2 ]; then
    echo "Writing $norm_method normalized results"
    $cmd LMWT=$min_lmwt:$max_lmwt $kwsoutdir/write_normalized.LMWT.log \
      set -e ';' set -o pipefail ';'\
      cat ${kwsoutdir}_LMWT/result.* \| \
        czpScripts/kws/write_kwslist.chenzp.pl  --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=$duration \
          --segments=$datadir/segments --normalize=$norm_method --duptime=$duptime --remove-dup=true\
          --map-utter=$datadir/kws_common/utter_map --digits=3 \
          - ${kwsoutdir}_LMWT/kwslist.xml || exit 1
  fi
  if [ $stage -le 3 ]; then
    echo "Writing unnormalized results"
    $cmd LMWT=$min_lmwt:$max_lmwt $kwsoutdir/write_unnormalized.LMWT.log \
      set -e ';' set -o pipefail ';'\
      cat ${kwsoutdir}_LMWT/result.* \| \
          czpScripts/kws/write_kwslist.chenzp.pl --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=$duration \
            --segments=$datadir/segments --normalize=skip --duptime=$duptime --remove-dup=true\
            --map-utter=$datadir/kws_common/utter_map \
            - ${kwsoutdir}_LMWT/kwslist.unnormalized.xml || exit 1;
  fi
fi

if [ -z $extraid ] ; then
  extraid_flags=
else
  extraid_flags="  --extraid ""$extraid"" "
fi

if [ $stage -le 4 ]; then
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
    echo "The estimated memory usage is $mem_est MB"
    if [ $mem_est -gt 30000 ]; then
      echo "$mem_est MB > 30000 MB, we'll force the requested memory as 30000MB."
      echo "  Please monitor if the scoring is out of memory."
      mem_est=30000
    fi
    cmd="`echo "$cmd" | sed 's:ram_free=[0-9]\+M:ram_free='$mem_est'M:' | sed 's:mem_free=[0-9]\+M:mem_free='$mem_est'M:'`"
    $cmd LMWT=$min_lmwt:$max_lmwt $kwsoutdir/scoring.LMWT.log \
       czpScripts/kws/kws_score.chenzp.sh $suffix_flags $extraid_flags $datadir ${kwsoutdir}_LMWT || exit 1;
  fi
fi

exit 0
