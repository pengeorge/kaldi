#!/bin/bash

# Copyright 2012 Johns Hopkins University (Author: Daniel Povey).
#           2015 Tsinghua University (Author: Zhipeng Chen).
# Apache 2.0.
# This script, which will generally be called from other neural-net training
# scripts, extracts the training examples used to train the neural net (and also
# the validation examples used for diagnostics), and puts them in separate archives.

set -e
set -u
# Begin configuration section.
cmd=run.pl

feat_type=raw
stage=0
splice_width=6 # meaning +- 6 frames on each side for second LDA
left_context= # left context for second LDA
right_context= # right context for second LDA
rand_prune=4.0 # Relates to a speedup we do for LDA.
within_class_factor=0.0001 # This affects the scaling of the transform rows...
                           # sorry for no explanation, you'll have to see the code.
transform_dir=     # If supplied, overrides alidir
num_feats=10000 # maximum number of feature files to use.  Beyond a certain point it just
                # gets silly to use more data.
lda_type=all # all/allphone/cluster
lda_dim=  # This defaults to no dimension reduction.
online_ivector_dir=
ivector_randomize_prob=0.0 # if >0.0, randomizes iVectors during training with
                           # this prob per iVector.
ivector_dir=
cmvn_opts=  # allows you to specify options for CMVN, if feature type is not lda.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;


if [ $# -lt 5 -o $[$#%2] -ne 1 ]; then
  echo "Usage: steps/nnet2/get_multilang_lda.sh [opts] <root0> <ali-dir0> <root1> <ali-dir1> <root N-1> <ali-dir N-1> <exp-dir>"
  echo " e.g.: steps/nnet2/get_multilang_lda.sh ../101 ../101/exp/tri5_ali ../104 ../104/exp/tri5_ali exp/dnn_scratch_4lang.raw"
  echo " This script will do the LDA computation for multiple language resources"
  echo "Main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config file containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --lda-type                                       # multilingual LDA type"
  echo "  --splice-width <width|4>                         # Number of frames on each side to append for feature input"
  #echo "                                                   # (note: we splice processed, typically 40-dimensional frames"
  echo "  --left-context <width;4>                         # Number of frames on left side to append for feature input, overrides splice-width"
  echo "  --right-context <width;4>                        # Number of frames on right side to append for feature input, overrides splice-width"
  echo "  --stage <stage|0>                                # Used to run a partially-completed training process from somewhere in"
  echo "                                                   # the middle."
  echo "  --online-vector-dir <dir|none>                   # Directory produced by"
  echo "                                                   # steps/online/nnet2/extract_ivectors_online.sh"
  exit 1;
fi

argv=("$@") 
num_args=$#
num_lang=$[($num_args-1)/2]

dir=${argv[$num_args-1]}


[ -z "$left_context" ] && left_context=$splice_width
[ -z "$right_context" ] && right_context=$splice_width

# TODO online_ivector_dir is not supported in multilang LDA
extra_files=
[ ! -z "$online_ivector_dir" ] && echo "online_ivector_dir is not supported" && exit 1 && \
  extra_files="$online_ivector_dir/ivector_online.scp $online_ivector_dir/ivector_period"

mkdir -p $dir/log
# Language index starts from 0.
for lid in $(seq 0 $[$num_lang-1]); do
  rootdir[$lid]=${argv[$lid*2]}
  alidir[$lid]=${argv[$lid*2+1]}
  lang[$lid]=${rootdir[$lid]}/data/lang
  # Check some files.
  for f in ${rootdir[$lid]}/data/train/feats.scp ${lang[$lid]}/L.fst ${alidir[$lid]}/ali.1.gz ${alidir[$lid]}/final.mdl ${alidir[$lid]}/tree $extra_files; do
    [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
  done
  # Set some variables.
  #oov=`cat $lang/oov.int`
  #num_leaves=`gmm-info $alidir/final.mdl 2>/dev/null | awk '/number of pdfs/{print $NF}'` || exit 1;
  silphonelist[$lid]=`cat ${lang[$lid]}/phones/silence.csl` || exit 1;

  nj[$lid]=`cat ${alidir[$lid]}/num_jobs` || exit 1;  # number of jobs in alignment dir...

  mkdir -p $dir/lda$[lid+1]/log
  echo ${nj[$lid]} > $dir/lda$[lid+1]/num_jobs
  cp ${alidir[$lid]}/tree $dir/lda$[lid+1]/tree

done


if [ -z "$cmvn_opts" ]; then
  cmvn_opts=`cat ${alidir[0]}/cmvn_opts 2>/dev/null`
  for lid in $(seq 1 $[$num_lang-1]); do
    this_cmvn_opts=`cat ${alidir[$lid]}/cmvn_opts 2>/dev/null`
    if [ "$this_cmvn_opts" != "$cmvn_opts" ]; then
      echo "Error: cmvn_opts not consistent, $lid vs. 0"
      exit 1;
    fi
  done
fi
echo $cmvn_opts >$dir/cmvn_opts 2>/dev/null

## Set up features.  Note: these are different from the normal features
## because we have one rspecifier that has the features for the entire
## training set, not separate ones for each batch.
if [ -z $feat_type ]; then
  echo "feat_type is not set, typically 'raw'"
  exit 1;
fi
echo "$0: feature type is $feat_type"


# If we have more than $num_feats feature files (default: 10k),
# we use a random subset.  This won't affect the transform much, and will
# spare us an unnecessary pass over the data.  Probably 10k is
# way too much, but for small datasets this phase is quite fast.
N=$[$num_feats/$nj]

feat_dim=  # for checking feat dim consistence in multilang
for lid in $(seq 0 $[$num_lang-1]); do
  data=${rootdir[$lid]}/data/train
  # in this dir we'll have just one job.
  sdata=$data/split${nj[$lid]}
  utils/split_data.sh $data ${nj[$lid]}

  if [ -z "$transform_dir" ]; then
    this_transform_dir=${alidir[$lid]}
  else
    this_transform_dir=${rootdir[$lid]}/exp/$transform_dir
  fi

  case $feat_type in
    raw) feats="ark,s,cs:utils/subset_scp.pl --quiet $N $sdata/JOB/feats.scp | apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:- ark:- |"
     ;;
    lda) 
      splice_opts=`cat ${alidir[$lid]}/splice_opts 2>/dev/null`
      for f in {splice_opts,cmvn_opts,final.mat}; do
        cp ${alidir[$lid]}/$f $dir/lda$[lid+1]/${f} || exit 1;
      done
      [ ! -z "$cmvn_opts" ] && \
         echo "You cannot supply --cmvn-opts option of feature type is LDA." && exit 1;
      cmvn_opts=$(cat $dir/cmvn_opts)
       feats="ark,s,cs:utils/subset_scp.pl --quiet $N $sdata/JOB/feats.scp | apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:- ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $dir/final.mat.$[lid+1] ark:- ark:- |"
      ;;
    *) echo "$0: invalid feature type $feat_type" && exit 1;
  esac

  if [ -f $this_transform_dir/trans.1 ] && [ $feat_type != "raw" ]; then
    echo "$0: using transforms from $this_transform_dir for lang $lid"
    feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark:$this_transform_dir/trans.JOB ark:- ark:- |"
  fi
  if [ -f $this_transform_dir/raw_trans.1 ] && [ $feat_type == "raw" ]; then
    echo "$0: using raw-fMLLR transforms from $this_transform_dir for lang $lid"
    feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark:$this_transform_dir/raw_trans.JOB ark:- ark:- |"
  fi


  feats_one="$(echo "$feats" | sed s:JOB:1:g)"
  # note: feat_dim is the raw, un-spliced feature dim without the iVectors.
  if [ -z $feat_dim ]; then
    feat_dim=$(feat-to-dim "$feats_one" -) || exit 1;
  else
    if [ $feat_dim -ne $(feat-to-dim "$feats_one" -) ]; then
      echo "feat_dim not consistent: 0 vs. $lid"
      exit 1;
    fi
  fi
  # by default: no dim reduction.


  spliced_feats[$lid]="$feats splice-feats --left-context=$left_context --right-context=$right_context ark:- ark:- |"

  if [ ! -z "$online_ivector_dir" ]; then
    echo "Online ivector is not supported yet."
    exit 1;
    ivector_period=$(cat $online_ivector_dir/ivector_period) || exit 1;
    # note: subsample-feats, with negative value of n, repeats each feature n times.
    spliced_feats="$spliced_feats paste-feats --length-tolerance=$ivector_period ark:- 'ark,s,cs:utils/filter_scp.pl $sdata/JOB/utt2spk $online_ivector_dir/ivector_online.scp | subsample-feats --n=-$ivector_period scp:- ark:- | ivector-randomize --randomize-prob=$ivector_randomize_prob ark:- ark:- |' ark:- |"
    ivector_dim=$(feat-to-dim scp:$online_ivector_dir/ivector_online.scp -) || exit 1;
  else
    ivector_dim=0
  fi
  echo $ivector_dim >$dir/ivector_dim
done

if [ -z "$lda_dim" ]; then
  spliced_feats_one="$(echo "${spliced_feats[0]}" | sed s:JOB:1:g)"  
  lda_dim=$(feat-to-dim "$spliced_feats_one" -) || exit 1;
fi

if [[ $lda_type =~ phone ]]; then
  acc_lda_bin=acc-phone-lda
  map_multi_model_class_bin=map-multi-model-phone
else
  acc_lda_bin=acc-lda
  map_multi_model_class_bin=map-multi-model-pdf
fi

if [ $stage -le 0 ]; then
  for lid in `seq 0 $[num_lang-1]`; do
    set +e; rm $dir/lda$[lid+1]/lda.*.acc 2>/dev/null; set -e; # in case any left over from before.
    this_alidir=${alidir[$lid]}
    echo "$0: Accumulating LDA statistics from $this_alidir."
    $cmd JOB=1:${nj[$lid]} $dir/lda$[lid+1]/log/lda_acc.JOB.log \
      ali-to-post "ark:gunzip -c $this_alidir/ali.JOB.gz|" ark:- \| \
      weight-silence-post 0.0 ${silphonelist[$lid]} $this_alidir/final.mdl ark:- ark:- \| \
      $acc_lda_bin --rand-prune=$rand_prune $this_alidir/final.mdl "${spliced_feats[$lid]}" ark,s,cs:- \
       $dir/lda$[lid+1]/lda.JOB.acc || exit 1;
  done
fi

echo $feat_dim > $dir/feat_dim
echo $lda_dim > $dir/lda_dim

if [ $stage -le 1 ]; then
  # Sum accs in each language
  echo "$0: Summing LDA statistics for each language."
  #for lid in `seq 0 $[num_lang-1]`; do
  $cmd JOB=1:$num_lang $dir/log/lda_sum.JOB.log \
    sum-lda-accs $dir/ldaJOB/lda.acc $dir/ldaJOB/lda.*.acc || exit 1;
  #rm $dir/$[lid+1]/lda.*.acc
fi

if [ $stage -le 2 ]; then
  # Generate class id mapping for multilingual LDA
  alimdls=
  for lid in `seq 0 $[num_lang-1]`; do
    alimdls="$alimdls ${alidir[$lid]}/final.mdl"
  done
  echo "$0: Mapping local class-ids (pdf/phone) to global cluster-ids by clustering method: $lda_type."
  $map_multi_model_class_bin ark:$dir/class_map $alimdls
fi

if [ $stage -le 3 ]; then
  # Accumalate multiple languages' accs
  echo "$0: Accumalate multiple languages' accs"
  sum-multi-model-lda-accs $dir/lda.acc ark:$dir/class_map $dir/*/lda.acc 2>$dir/log/multilang_lda_sum.log || exit 1;
  #rm $dir/lda.*.acc
fi

if [ $stage -le 4 ]; then
  # There are various things that we sometimes (but not always) need
  # the within-class covariance and its Cholesky factor for, and we
  # write these to disk just in case.
  nnet-get-feature-transform --write-cholesky=$dir/cholesky.tpmat \
     --write-within-covar=$dir/within_covar.spmat \
     --within-class-factor=$within_class_factor --dim=$lda_dim \
      $dir/lda.mat $dir/lda.acc \
      2>$dir/log/lda_est.log || exit 1;
fi

echo "$0: Finished estimating multilingual LDA"
