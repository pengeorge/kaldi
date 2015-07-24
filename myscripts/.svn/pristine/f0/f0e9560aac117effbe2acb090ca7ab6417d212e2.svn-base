#!/bin/bash
# Copyright 2012  Johns Hopkins University (Author: Daniel Povey).  Apache 2.0.

# This trains a UBM (i.e. a mixture of Gaussians), by clustering
# the Gaussians from a trained HMM/GMM system and then doing a few
# iterations of UBM training.
# We mostly use this for SGMM systems.

# Begin configuration section.
nj=4
cmd=run.pl
silence_weight=  # You can set it to e.g. 0.0, to weight down silence in training.
stage=-2
num_gselect1=50 # first stage of Gaussian-selection
num_gselect2=25 # second stage.
intermediate_num_gauss=2000
num_iters=3
no_fmllr=false
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;


if [ $# -lt 5 ]; then
  echo "Usage: steps/train_ubm.sh <num-gauss> <data1> <lang1> <ali1-dir> [ <data2> <lang2> <ali-dir2> ... ] <exp>"
  echo " e.g.: steps/train_ubm.sh 400 data/train_si84 data/lang exp/tri2b_ali_si84 exp/ubm3c"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --silence-weight <sil-weight>                    # weight for silence (e.g. 0.5 or 0.0)"
  echo "  --num-iters <#iters>                             # Number of iterations of E-M"\
  echo "  --no-fmllr (true|false)                          # ignore speaker matrices even if present"
  exit 1;
fi

argv=("$@") 
num_args=$#
num_lang=$[($num_args-2)/3]
num_gauss=$1
dir=${argv[$num_args-1]}

if [ $[$num_gauss*2] -gt $intermediate_num_gauss ]; then
  echo "intermediate_num_gauss was too small $intermediate_num_gauss"
  intermediate_num_gauss=$[$num_gauss*2];
  echo "setting it to $intermediate_num_gauss"
fi

mkdir -p $dir/log

ubm_init_args=
for lang in $(seq 0 $[$num_lang-1]); do
  datadirs[$lang]=${argv[$lang*3+1]}
  langdirs[$lang]=${argv[$lang*3+2]}
  alidirs[$lang]=${argv[$lang*3+3]}

  datadir=${datadirs[$lang]}
  langdir=${langdirs[$lang]}
  alidir=${alidirs[$lang]}

  echo "Language $lang: $datadir $langdir $alidir"
  # Set various variables.
  silphonelists[$lang]=`cat ${langdir}/phones/silence.csl` || exit 1;
  njs[$lang]=`cat ${alidir}/num_jobs` || exit 1;

  silphonelist=${silphonelists[$lang]}
  nj=${njs[$lang]}

  ubm_init_args="$ubm_init_args $alidir/final.mdl $alidir/final.occs"

  for f in $datadir/feats.scp $langdir/L.fst $alidir/ali.1.gz $alidir/final.mdl; do
    [ ! -f $f ] && echo "No such file $f" && exit 1;
  done
  echo $nj > $dir/num_jobs$lang
  sdata=$datadir/split$nj;
  [[ -d $sdata && $datadir/feats.scp -ot $sdata ]] || split_data.sh $datadir $nj || exit 1;
  splice_opts=`cat $alidir/splice_opts 2>/dev/null` # frame-splicing options.
  cmvn_opts=`cat $alidir/cmvn_opts 2>/dev/null`
 
  ## Set up features.
  if [ -f $alidir/final.mat ]; then feat_type=lda; else feat_type=delta; fi
  echo "$0: feature type of lang $lang is $feat_type"

  case $feat_type in
    delta) feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | add-deltas ark:- ark:- |";;
    lda) 
      echo "Using LDA feature in multilang SGMM training is not supported."
      exit 1;
      feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $alidir/final.mat ark:- ark:- |"
      cp $alidir/final.mat $dir    
      ;;
    *) echo "$0: invalid feature type $feat_type" && exit 1;
  esac

  if [ -f $alidir/trans.1 ]; then
    if $no_fmllr; then
      echo "$0: deliberately ignoring speaker transforms from $alidir"
    else
      echo "$0: using transforms from $alidir"
      feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark,s,cs:$alidir/trans.JOB ark:- ark:- |"
    fi
  elif [ -f $alidir/raw_trans.1 ]; then
    echo "$0: using raw-FMLLR transforms from $alidir"
    feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark,s,cs:$alidir/raw_trans.JOB ark:- ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $alidir/final.mat ark:- ark:- |"  
  fi

  if [ ! -z "$silence_weight" ]; then
    weights_opt="--weights='ark,s,cs:gunzip -c $alidir/ali.JOB.gz | ali-to-post ark:- ark:- | weight-silence-post $silence_weight $silphonelist $alidir/final.mdl ark:- ark:- | post-to-weights ark:- ark:- |'"
  else
    weights_opt=
  fi
  featss[$lang]=$feats
  weights_opts[$lang]=$weights_opt
done


##

host=`readlink -f $dir | grep -Po '(?<=kaldi_exp_)x\d+(?=/)'`
local_cmd=`echo $cmd | sed "s:-q \+[^ ]\+:-q ${host}.q:"`

if [ $stage -le -2 ]; then
  echo "$0: clustering models to get initial UBM"
  $local_cmd $dir/log/cluster.log \
    init-ubm-multilang.chenzp --intermediate-num-gauss=$intermediate_num_gauss --ubm-num-gauss=$num_gauss \
    --verbose=2 --fullcov-ubm=true $ubm_init_args \
    $dir/0.ubm   || exit 1;
fi

# Do initial phase of Gaussian selection and save it to disk -- later on we'll
# do more Gaussian selection to further prune, as the model changes.


if [ $stage -le -1 ]; then
  for lang in $(seq 0 $[$num_lang-1]); do
    echo "$0: doing Gaussian selection for lang $lang"
    mkdir -p $dir/$lang/log
    $cmd JOB=1:${njs[$lang]} $dir/$lang/log/gselect.JOB.log \
      gmm-gselect --n=$num_gselect1 "fgmm-global-to-gmm $dir/0.ubm - |" "${featss[$lang]}" \
      "ark:|gzip -c >$dir/$lang/gselect.JOB.gz" || exit 1;
  done
fi


x=0
while [ $x -lt $num_iters ]; do
  echo "Pass $x"
  for lang in $(seq 0 $[$num_lang-1]); do
    $cmd JOB=1:${njs[$lang]} $dir/$lang/log/acc.$x.JOB.log \
      gmm-gselect --n=$num_gselect2 "--gselect=ark,s,cs:gunzip -c $dir/$lang/gselect.JOB.gz|" \
      "fgmm-global-to-gmm $dir/$x.ubm - |" "${featss[$lang]}" ark:- \| \
      fgmm-global-acc-stats ${weights_opts[$lang]} --gselect=ark,s,cs:- $dir/$x.ubm "${featss[$lang]}" \
      $dir/$lang/$x.JOB.acc || exit 1;
  done
  lowcount_opt="--remove-low-count-gaussians=false"
  [ $[$x+1] -eq $num_iters ] && lowcount_opt=   # Only remove low-count Gaussians 
  # on last iter-- we can't do it earlier, or the Gaussian-selection info would
  # be mismatched.
  $local_cmd $dir/log/update.$x.log \
    fgmm-global-est $lowcount_opt --verbose=2 $dir/$x.ubm "fgmm-global-sum-accs - $dir/*/$x.*.acc |" \
      $dir/$[$x+1].ubm || exit 1;
  rm $dir/*/$x.*.acc $dir/$x.ubm
  x=$[$x+1]
done

rm $dir/*/gselect.*.gz
rm $dir/final.ubm 2>/dev/null
mv $dir/$x.ubm $dir/final.ubm || exit 1;
