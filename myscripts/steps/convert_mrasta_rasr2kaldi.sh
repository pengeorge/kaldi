#!/bin/bash 

# Copyright 2015 Zhipeng Chen
# Apache 2.0
# Combine PLP and pitch features together 
# Note: This file is based on make_plp.sh and make_pitch_kaldi.sh

# Begin configuration section.
nj=4
cmd=run.pl
compress=true
cleanup=true
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 5 ]; then
   echo "usage: $0 [options] <rasr-cache-file> <kaldi-data-dir> <data-dir> <log-dir> <path-to-mrasta-dir>";
   echo "options: "
   echo "  --nj                       <nj>                      # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>)     # how to run jobs."
   exit 1;
fi

cache=$1
kaldidata=$2
data=$3
logdir=$4
mrasta_dir=$5


# make $mrasta_dir an absolute pathname.
mrasta_dir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $mrasta_dir ${PWD}`

# use "name" as part of name of the archive.
name=`basename $data`

mkdir -p $data || exit 1;
mkdir -p $mrasta_dir || exit 1;
mkdir -p $logdir || exit 1;

if [ -f $data/feats.scp ]; then
  mkdir -p $data/.backup
  echo "$0: moving $data/feats.scp to $data/.backup"
  mv $data/feats.scp $data/.backup
fi

required="$cache"

for f in $required; do
  if [ ! -f $f ]; then
    echo "make_mrasta.sh: no such file $f"
    exit 1;
  fi
done

cp_from_kaldi="segments spk2utt utt2spk wav.scp reco2file_and_channel text stm"
for f in $cp_from_kaldi; do
  if [ -f $kaldidata/$f ]; then
    cp $kaldidata/$f $data/
  fi
done
utils/validate_data_dir.sh --no-text --no-feats $data || exit 1;

## Not supported yet. Should be configed in RASR feature-extraction
#if [ -f $data/spk2warp ]; then
#  echo "$0 [info]: using VTLN warp factors from $data/spk2warp"
#  vtln_opts="--vtln-map=ark:$data/spk2warp --utt2spk=ark:$data/utt2spk"
#elif [ -f $data/utt2warp ]; then
#  echo "$0 [info]: using VTLN warp factors from $data/utt2warp"
#  vtln_opts="--vtln-map=ark:$data/utt2warp"
#fi

for n in $(seq $nj); do
  # the next command does nothing unless $mrasta_dir/storage/ exists, see
  # utils/create_data_link.pl for more info.
  utils/create_data_link.pl $mrasta_dir/raw_mrasta_$name.$n.ark  
done

archiver $cache | grep -Po '\S+(?=\.attribs)' | sort > $data/utts_in_rasr_ark || (echo "Error extracting utt IDs from RASR archive" && exit 1);
cut -d' ' -f 1 $data/utt2spk | sort | diff - <(grep -Po '(?<=/)[^/]+$' $data/utts_in_rasr_ark | sort) || (echo "utts in RASR ark differs from that in utt2spk" && exit 1;)

split_utts=""
for n in $(seq $nj); do
  split_utts="$split_utts $logdir/utts_in_rasr_ark.$n"
done

utils/split_scp.pl $data/utts_in_rasr_ark $split_utts || exit 1;
rm $logdir/.error 2>/dev/null

mkdir -p $mrasta_dir/text_feats_$name
$cmd JOB=1:$nj $logdir/write_rasr_text_feats_${name}.JOB.log \
  ./czpScripts/steps/rasr_ark2kaldi_txt.sh $cache $logdir/utts_in_rasr_ark.JOB $logdir/utts.JOB $mrasta_dir/text_feats_$name || exit 1;

# plp_feats="ark:extract-segments scp,p:$scp $logdir/segments.JOB ark:- | compute-plp-feats $vtln_opts --verbose=2 --config=$plp_config ark:- ark:- |"
mrasta_feats="ark:convert-mrasta-feats-from-rasr --verbose=2 $logdir/utts.JOB $mrasta_dir/text_feats_$name ark:- |"

$cmd JOB=1:$nj $logdir/convert_mrasta_${name}.JOB.log \
  copy-feats --compress=$compress "$mrasta_feats" \
    ark,scp:$mrasta_dir/raw_mrasta_$name.JOB.ark,$mrasta_dir/raw_mrasta_$name.JOB.scp \
   || exit 1;

#  paste-feats --length-tolerance=$paste_length_tolerance "$mrasta_feats" ark:- \| \  # only use in concate features

if [ -f $logdir/.error.$name ]; then
  echo "Error producing MRASTA features for $name:"
  tail $logdir/make_mrasta_${name}.1.log
  exit 1;
fi

# concatenate the .scp files together.
for n in $(seq $nj); do
  cat $mrasta_dir/raw_mrasta_$name.$n.scp || exit 1;
done > $data/feats.scp

rm $logdir/utts_in_rasr_ark.* 2>/dev/null

nf=`cat $data/feats.scp | wc -l` 
nu=`cat $data/utt2spk | wc -l` 
if [ $nf -ne $nu ]; then
  echo "It seems not all of the feature files were successfully processed ($nf != $nu);"
  echo "consider using utils/fix_data_dir.sh $data"
fi

if $cleanup; then
  echo "Clean up text_feats_$name"
  rm $mrasta_dir/text_feats_$name/*
fi

if [ $nf -lt $[$nu - ($nu/20)] ]; then
  echo "Less than 95% the features were successfully generated.  Probably a serious error."
  exit 1;
fi

echo "Succeeded creating MRASTA features for $name"
