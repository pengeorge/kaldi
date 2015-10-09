#!/bin/bash

# Copyright 2012  Johns Hopkins University (Author: Daniel Povey).  Apache 2.0.

# SGMM training, with speaker vectors.  This script would normally be called on
# top of fMLLR features obtained from a conventional system, but it also works
# on top of any type of speaker-independent features (based on
# deltas+delta-deltas or LDA+MLLT).  For more info on SGMMs, see the paper "The
# subspace Gaussian mixture model--A structured model for speech recognition".
# (Computer Speech and Language, 2011).

# Begin configuration section.
nj=4
cmd=run.pl
stage=-6 # use this to resume partially finished training 
context_opts= # e.g. set it to "--context-width=5 --central-position=2"  for a
# quinphone system.
scale_opts="--transition-scale=1.0 --acoustic-scale=0.1 --self-loop-scale=0.1"
num_iters=25   # Total number of iterations of training
num_iters_alimdl=3 # Number of iterations for estimating alignment model.
max_iter_inc=15 # Last iter to increase #substates on.
realign_iters="5 10 15"; # Iters to realign on. 
spkvec_iters="5 8 12 17" # Iters to estimate speaker vectors on.
increase_dim_iters= #"6 10 14"; # Iters on which to increase phn dim and/or spk dim;
    # rarely necessary, and if it is, only the 1st will normally be necessary.
rand_prune=0.1 # Randomized-pruning parameter for posteriors, to speed up training.
               # Bigger -> more pruning; zero = no pruning.
phn_dim=  # You can use this to set the phonetic subspace dim. [default: feat-dim+1]
spk_dim=  # You can use this to set the speaker subspace dim. [default: feat-dim]
power=0.25 # Exponent for number of gaussians according to occurrence counts
beam=8
self_weight=0.9
retry_beam=40
leaves_per_group=5 # Relates to the SCTM (state-clustered tied-mixture) aspect:
                   # average number of pdfs in a "group" of pdfs.
update_m_iter=4
spk_dep_weights=false # [Symmetric SGMM] set this to false if you don't want "u" (i.e. to turn off
                      # symmetric SGMM.
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;


if [ $# -lt 7 ]; then
  echo "Usage: steps/train_sgmm2.sh <num-leaves> <num-substates> <data1> <lang1> <ali-dir1> [ <data2> <lang2> <ali-dir2> ... ] <ubm> <exp-dir>"
  echo " e.g.: steps/train_sgmm2.sh 5000 8000 data/train_si84 data/lang \\"
  echo "                      exp/tri3b_ali_si84 exp/ubm4a/final.ubm exp/sgmm4a"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --silence-weight <sil-weight>                    # weight for silence (e.g. 0.5 or 0.0)"
  echo "  --num-iters <#iters>                             # Number of iterations of E-M"
  echo "  --leaves-per-group <#leaves>                     # Average #leaves shared in one group"
  exit 1;
fi

set -u;

argv=("$@") 
num_args=$#
num_lang=$[($num_args-4)/3]
num_pdfs=$1  # final #leaves, at 2nd level of tree.
totsubstates=$2
ubm=${argv[$num_args-2]}
dir=${argv[$num_args-1]}

num_groups=$[$num_pdfs/$leaves_per_group]
first_spkvec_iter=`echo $spkvec_iters | awk '{print $1}'` || exit 1;

mkdir -p $dir/log

# Check some files.
for f in $ubm; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

ubm_init_args=
for lang in $(seq 0 $[$num_lang-1]); do
  mkdir -p $dir/$lang/log
  datadirs[$lang]=${argv[$lang*3+2]}
  langdirs[$lang]=${argv[$lang*3+3]}
  alidirs[$lang]=${argv[$lang*3+4]}

  datadir=${datadirs[$lang]}
  langdir=${langdirs[$lang]}
  alidir=${alidirs[$lang]}

  echo "Language $lang: $datadir $langdir $alidir"
  # Set various variables.
  ciphonelists[$lang]=`cat $langdir/phones/context_indep.csl` || exit 1;
  oovs[$lang]=`cat $langdir/oov.int`
  silphonelists[$lang]=`cat ${langdir}/phones/silence.csl` || exit 1;
  njs[$lang]=`cat ${alidir}/num_jobs` || exit 1;
  spkvecs_opts[$lang]=  # Empty option for now, until we estimate the speaker vectors.
  gselect_opts[$lang]="--gselect=ark,s,cs:gunzip -c $dir/$lang/gselect.JOB.gz|"

  nj=${njs[$lang]}

  for f in $datadir/feats.scp $langdir/L.fst $alidir/ali.1.gz $alidir/final.mdl; do
    [ ! -f $f ] && echo "No such file $f" && exit 1;
  done
  echo $nj > $dir/num_jobs$lang
  sdata=$datadir/split$nj;
  [[ -d $sdata && $datadir/feats.scp -ot $sdata ]] || split_data.sh $datadir $nj || exit 1;
  splice_opts=`cat $alidir/splice_opts 2>/dev/null` # frame-splicing options.
  cmvn_opts=`cat $alidir/cmvn_opts 2>/dev/null`
  cp $alidir/splice_opts $dir/$lang 2>/dev/null # frame-splicing options.
  cp $alidir/cmvn_opts $dir/$lang 2>/dev/null # cmn/cmvn option.
 
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
    echo "$0: using transforms from $alidir"
    feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark,s,cs:$alidir/trans.JOB ark:- ark:- |"
  elif [ -f $alidir/raw_trans.1 ]; then
    echo "$0: using raw-fMLLR transforms from $alidir"
    feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark,s,cs:$alidir/raw_trans.JOB ark:- ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $alidir/final.mat ark:- ark:- |"
  fi

  featss[$lang]=$feats
done


if [ "$self_weight" == "1.0" ]; then
  numsubstates=$num_groups # Initial #-substates.
else
  numsubstates=$num_pdfs # Initial #-substates.
fi
incsubstates=$[($totsubstates-$numsubstates)/$max_iter_inc] # per-iter increment for #substates
feat_dim=`gmm-info ${alidirs[0]}/final.mdl 2>/dev/null | awk '/feature dimension/{print $NF}'` || exit 1;
[ $feat_dim -eq $feat_dim ] || exit 1; # make sure it's numeric.
[ -z $phn_dim ] && phn_dim=$[$feat_dim+1]
[ -z $spk_dim ] && spk_dim=$feat_dim



##

if [ $stage -le -6 ]; then
  for lang in $(seq 0 $[$num_lang-1]); do
    {
    echo "$0: accumulating tree stats for lang $lang"
    $cmd JOB=1:${njs[$lang]} $dir/$lang/log/acc_tree.JOB.log \
      acc-tree-stats $context_opts --ci-phones=${ciphonelists[$lang]} ${alidirs[$lang]}/final.mdl "${featss[$lang]}" \
      "ark:gunzip -c ${alidirs[$lang]}/ali.JOB.gz|" $dir/$lang/JOB.treeacc || exit 1;
    [ "`ls $dir/$lang/*.treeacc | wc -w`" -ne "${njs[$lang]}" ] && echo "$0: Wrong #tree-stats" && exit 1;
    sum-tree-stats $dir/$lang/treeacc $dir/$lang/*.treeacc 2>$dir/$lang/log/sum_tree_acc.log || exit 1;
    rm $dir/$lang/*.treeacc
    echo "$0: Done accumulating tree stats for lang $lang"
  } & 
  done
  wait
fi

host=`readlink -f $dir | grep -Po '(?<=kaldi_exp_)x\d+(?=/)'`
local_cmd=`echo $cmd | sed "s:-q \+[^ ]\+:-q ${host}.q:"`

if [ $stage -le -5 ]; then
  for lang in $(seq 0 $[$num_lang-1]); do
    {
    echo "$0: Getting questions for tree clustering for lang $lang."
    # preparing questions, roots file...
    cluster-phones $context_opts $dir/$lang/treeacc ${langdirs[$lang]}/phones/sets.int $dir/$lang/questions.int 2> $dir/$lang/log/questions.log || exit 1;
    cat ${langdirs[$lang]}/phones/extra_questions.int >> $dir/$lang/questions.int
    compile-questions $context_opts ${langdirs[$lang]}/topo $dir/$lang/questions.int $dir/$lang/questions.qst 2>$dir/$lang/log/compile_questions.log || exit 1;

    echo "$0: Building the tree for $lang"
    $local_cmd $dir/$lang/log/build_tree.log \
      build-tree-two-level $context_opts --binary=false --verbose=1 --max-leaves-first=$num_groups \
       --max-leaves-second=$num_pdfs $dir/$lang/treeacc ${langdirs[$lang]}/phones/roots.int \
       $dir/$lang/questions.qst ${langdirs[$lang]}/topo $dir/$lang/tree $dir/$lang/pdf2group.map || exit 1;
    echo "$0: Done building tree for $lang"
  } &
  done
  wait
fi

if [ $stage -le -4 ]; then
  for lang in $(seq 0 $[$num_lang-1]); do
    {
    echo "$0: Initializing the model for lang $lang"  
    # Note: if phn_dim > feat_dim+1 or spk_dim > feat_dim, these dims
    # will be truncated on initialization.
    $local_cmd $dir/$lang/log/init_sgmm.log \
      sgmm2-init --spk-dep-weights=$spk_dep_weights --self-weight=$self_weight \
         --pdf-map=$dir/$lang/pdf2group.map --phn-space-dim=$phn_dim \
         --spk-space-dim=$spk_dim ${langdirs[$lang]}/topo $dir/$lang/tree $ubm $dir/$lang/0.mdl || exit 1;
    echo "$0: Done initializing model for lang $lang"
  } &
  done
  wait
fi

if [ $stage -le -3 ]; then
  for lang in $(seq 0 $[$num_lang-1]); do
    {
    echo "$0: doing Gaussian selection for lang $lang"
    $cmd JOB=1:${njs[$lang]} $dir/$lang/log/gselect.JOB.log \
      sgmm2-gselect $dir/$lang/0.mdl "${featss[$lang]}" \
      "ark,t:|gzip -c >$dir/$lang/gselect.JOB.gz" || exit 1;
    echo "$0: Done gaussian selection for lang $lang"
  } &
  done
  wait
fi

if [ $stage -le -2 ]; then
  for lang in $(seq 0 $[$num_lang-1]); do
    {
    echo "$0: compiling training graphs for lang $lang"
    langdir=${langdirs[$lang]}
    text="ark:sym2int.pl --map-oov ${oovs[$lang]} -f 2- $langdir/words.txt < ${datadirs[$lang]}/split${njs[$lang]}/JOB/text|"
    $cmd JOB=1:${njs[$lang]} $dir/$lang/log/compile_graphs.JOB.log \
      compile-train-graphs $dir/$lang/tree $dir/$lang/0.mdl  $langdir/L.fst  \
      "$text" "ark:|gzip -c >$dir/$lang/fsts.JOB.gz" || exit 1;
    echo "$0: Done compiling graphs for lang $lang"
  } &
  done
  wait
fi

if [ $stage -le -1 ]; then
  for lang in $(seq 0 $[$num_lang-1]); do
    {
    echo "$0: converting alignments for lang $lang" 
    alidir=${alidirs[$lang]}
    $cmd JOB=1:${njs[$lang]} $dir/$lang/log/convert_ali.JOB.log \
      convert-ali $alidir/final.mdl $dir/$lang/0.mdl $dir/$lang/tree "ark:gunzip -c $alidir/ali.JOB.gz|" \
      "ark:|gzip -c >$dir/$lang/ali.JOB.gz" || exit 1;
    echo "$0: Done converting aligments for lang $lang"
  } &
  done
  wait
fi

x=0
while [ $x -lt $num_iters ]; do
   echo "$0: training pass $x ... "
   if echo $realign_iters | grep -w $x >/dev/null && [ $stage -le $x ]; then
     for lang in $(seq 0 $[$num_lang-1]); do
       {
       echo "Pass $x: re-aligning data for lang $lang"
       $cmd JOB=1:${njs[$lang]} $dir/$lang/log/align.$x.JOB.log  \
         sgmm2-align-compiled ${spkvecs_opts[$lang]} $scale_opts "${gselect_opts[$lang]}" \
         --utt2spk=ark:${datadirs[$lang]}/split${njs[$lang]}/JOB/utt2spk --beam=$beam --retry-beam=$retry_beam \
         $dir/$lang/$x.mdl "ark:gunzip -c $dir/$lang/fsts.JOB.gz|" "${featss[$lang]}" \
         "ark:|gzip -c >$dir/$lang/ali.JOB.gz" || exit 1;
       echo "Pass $x: Done re-aligning for lang $lang"
     } &
     done
     wait
   fi
   if [ $spk_dim -gt 0 ] && echo $spkvec_iters | grep -w $x >/dev/null; then
     if [ $stage -le $x ]; then
       for lang in $(seq 0 $[$num_lang-1]); do
         {
         echo "Pass $x: est-spkvecs for lang $lang"
         $cmd JOB=1:${njs[$lang]} $dir/$lang/log/spkvecs.$x.JOB.log \
           ali-to-post "ark:gunzip -c $dir/$lang/ali.JOB.gz|" ark:- \| \
           weight-silence-post 0.01 ${silphonelists[$lang]} $dir/$lang/$x.mdl ark:- ark:- \| \
           sgmm2-est-spkvecs --rand-prune=$rand_prune --spk2utt=ark:${datadirs[$lang]}/split${njs[$lang]}/JOB/spk2utt \
           ${spkvecs_opts[$lang]} "${gselect_opts[$lang]}" $dir/$lang/$x.mdl "${featss[$lang]}" ark,s,cs:- \
           ark:$dir/$lang/tmp_vecs.JOB '&&' mv $dir/$lang/tmp_vecs.JOB $dir/$lang/vecs.JOB || exit 1;
         echo "Pass $x: Done est-spkvecs for lang $lang"
       } &
       done
     fi
     wait
     for lang in $(seq 0 $[$num_lang-1]); do
       spkvecs_opts[$lang]="--spk-vecs=ark:$dir/$lang/vecs.JOB"
     done
   fi  
   if [ $x -eq 0 ]; then
     flags=wS # on the first iteration, don't update projections M or N
   elif [ $spk_dim -gt 0 -a $[$x%2] -eq 1 -a $x -ge $first_spkvec_iter ]; then 
     # Update N if we have speaker-vector space and x is odd,
     # and we've already updated the speaker vectors...
     flags=NwS
   else
     if [ $x -ge $update_m_iter ]; then
       flags=MwS # udpate M.
     else
       flags=wS # no M on early iters, if --update-m-iter option given.
     fi
   fi
   $spk_dep_weights && [ $x -ge $first_spkvec_iter ] && flags=${flags}u; # update 
   # spk-weight projections "u".
   
   if [ $stage -le $x ]; then
     for lang in $(seq 0 $[$num_lang-1]); do
       {
       echo "Pass $x: Acc shared parameters for lang $lang: $flags"
       $cmd JOB=1:${njs[$lang]} $dir/$lang/log/acc_shared.$x.JOB.log \
         sgmm2-acc-shared-stats.chenzp ${spkvecs_opts[$lang]} --utt2spk=ark:${datadirs[$lang]}/split${njs[$lang]}/JOB/utt2spk \
         --update-flags=$flags "${gselect_opts[$lang]}" --rand-prune=$rand_prune \
         $dir/$lang/$x.mdl "${featss[$lang]}" "ark,s,cs:gunzip -c $dir/$lang/ali.JOB.gz | ali-to-post ark:- ark:-|" \
         $dir/$lang/$x.JOB.acc_shared || exit 1;
       echo "Pass $x: Done acc shared parameters for lang $lang"
       } &
       {
       echo "Pass $x: Acc language-dependent parameters for lang $lang: vct"
       $cmd JOB=1:${njs[$lang]} $dir/$lang/log/acc.$x.JOB.log \
         sgmm2-acc-stats ${spkvecs_opts[$lang]} --utt2spk=ark:${datadirs[$lang]}/split${njs[$lang]}/JOB/utt2spk \
         --update-flags=vct "${gselect_opts[$lang]}" --rand-prune=$rand_prune \
         $dir/$lang/$x.mdl "${featss[$lang]}" "ark,s,cs:gunzip -c $dir/$lang/ali.JOB.gz | ali-to-post ark:- ark:-|" \
         $dir/$lang/$x.JOB.acc || exit 1; 
       echo "Pass $x: Done acc language-dependent parameters for lang $lang"
       } &
     done
     wait
     echo "Pass $x: Aggregate language-independent parameters"
     langs_accs=
     for lang in $(seq 0 $[$num_lang-1]); do
       langs_accs="$langs_accs \"sgmm2-sum-shared-accs.chenzp - $dir/$lang/$x.*.acc_shared |\""
     done
     # Get shared accs
     $local_cmd $dir/log/aggregate_shared_accs.$x.log \
       sgmm2-aggregate-shared-accs.chenzp $dir/$x.accs_shared $langs_accs || exit 1;
   fi

   # The next option is needed if the user specifies a phone or speaker sub-space
   # dimension that's higher than the "normal" one.
   increase_dim_opts=
   if echo $increase_dim_iters | grep -w $x >/dev/null; then
     increase_dim_opts="--increase-phn-dim=$phn_dim --increase-spk-dim=$spk_dim"
     # Note: the command below might have a null effect on some iterations.
     if [ $spk_dim -gt $feat_dim ]; then 
       for lang in $(seq 0 $[$num_lang-1]); do
         {
         echo "Pass $x: increase dim for $lang"
         $cmd JOB=1:${njs[$lang]} $dir/$lang/log/copy_vecs.$x.JOB.log \
           copy-vector --print-args=false --change-dim=$spk_dim \
           ark:$dir/$lang/vecs.JOB ark:$dir/$lang/vecs_tmp.$JOB '&&' \
           mv $dir/$lang/vecs_tmp.JOB $dir/$lang/vecs.JOB || exit 1;
         echo "Pass $x: Done increase dim for $lang"
         } &
       done
       wait
     fi
   fi

   if [ $stage -le $x ]; then
     langs_mdls=
     for lang in $(seq 0 $[$num_lang-1]); do
       langs_mdls="$langs_mdls $dir/$lang/$x.mdl $dir/$lang/$[$x+1].shared.mdl"
     done
     echo "Pass $x: Update shared parameters: $flags"
     $local_cmd $dir/log/update_shared.$x.log \
       sgmm2-est-shared.chenzp --update-flags=$flags \
       $increase_dim_opts \
       $dir/$x.accs_shared $langs_mdls || exit 1;
     for lang in $(seq 0 $[$num_lang-1]); do
       {
       echo "Pass $x: Update language-dependent parameters for lang $lang: vct"
       $local_cmd $dir/$lang/log/update.$x.log \
         sgmm2-est --update-flags=vct --split-substates=$numsubstates \
         $increase_dim_opts --power=$power --write-occs=$dir/$lang/$[$x+1].occs \
         $dir/$lang/$[$x+1].shared.mdl "sgmm2-sum-accs - $dir/$lang/$x.*.acc|" $dir/$lang/$[$x+1].mdl || exit 1;
       #rm $dir/$lang/$x.mdl $dir/$lang/$x.shared.mdl 2>/dev/null
       rm $dir/$lang/$x.*.acc $dir/$lang/$x.*.acc_shared $dir/$lang/$x.occs 2>/dev/null
       echo "Pass $x: Done updating parameters for lang $lang" 
       } &
     done
     wait
     rm $dir/$x.accs_shared 2>/dev/null
   fi
   if [ $x -lt $max_iter_inc ]; then
     numsubstates=$[$numsubstates+$incsubstates]
   fi
   x=$[$x+1];
done

for lang in $(seq 0 $[$num_lang-1]); do
  rm $dir/$lang/final.mdl $dir/$lang/final.occs 2>/dev/null
  ln -s $x.mdl $dir/$lang/final.mdl
  ln -s $x.occs $dir/$lang/final.occs
done

if [ $spk_dim -gt 0 ]; then
  # We need to create an "alignment model" that's been trained
  # without the speaker vectors, to do the first-pass decoding with.
  # in test time.

  # We do this for a few iters, in this recipe.

  for lang in $(seq 0 $[$num_lang-1]); do
    final_mdls[$lang]=$dir/$lang/$x.mdl
    cur_alimdls[$lang]=$dir/$lang/$x.mdl
  done
  while [ $x -lt $[$num_iters+$num_iters_alimdl] ]; do
    echo "$0: building alignment model (pass $x)"
    if [ $x -eq $num_iters ]; then # 1st pass of building alimdl.
      flags_shared=MwS # don't update v the first time.  Note-- we never update transitions.
      # they wouldn't change anyway as we use the same alignment as previously.
      flags=c
    else
      flags_shared=MwS
      flags=vc
    fi
    
    for lang in $(seq 0 $[$num_lang-1]); do
      nj=${njs[$lang]}
      final_mdl=${final_mdls[$lang]}
      cur_alimdl=${cur_alimdls[$lang]}
      sdata=${datadirs[$lang]}/split$nj
      feats=${featss[$lang]}
      if [ $stage -le $x ]; then
        $cmd JOB=1:$nj $dir/$lang/log/acc_shared_ali.$x.JOB.log \
          ali-to-post "ark:gunzip -c $dir/$lang/ali.JOB.gz|" ark:- \| \
          sgmm2-post-to-gpost ${spkvecs_opts[$lang]} "${gselect_opts[$lang]}" \
           --utt2spk=ark:$sdata/JOB/utt2spk $final_mdl "$feats" ark,s,cs:- ark:- \| \
          sgmm2-acc-stats-gpost --rand-prune=$rand_prune --update-flags=$flags_shared \
            $cur_alimdl "$feats" ark,s,cs:- $dir/$lang/$x.JOB.aliacc_shared || exit 1;
        $local_cmd $dir/$lang/log/update_ali.$x.log \
          sgmm2-est --update-flags=$flags_shared --remove-speaker-space=true --power=$power \
          $cur_alimdl "sgmm2-sum-accs - $dir/*/$x.*.aliacc_shared|" $dir/$lang/$[$x+1].shared.alimdl || exit 1;
        cur_shared_alimdl=$dir/$lang/$[$x+1].shared.alimdl
        $cmd JOB=1:$nj $dir/$lang/log/acc_ali.$x.JOB.log \
          ali-to-post "ark:gunzip -c $dir/$lang/ali.JOB.gz|" ark:- \| \
          sgmm2-post-to-gpost ${spkvecs_opts[$lang]} "${gselect_opts[$lang]}" \
           --utt2spk=ark:$sdata/JOB/utt2spk $final_mdl "$feats" ark,s,cs:- ark:- \| \
          sgmm2-acc-stats-gpost --rand-prune=$rand_prune --update-flags=$flags \
            $cur_shared_alimdl "$feats" ark,s,cs:- $dir/$lang/$x.JOB.aliacc || exit 1;
        $local_cmd $dir/$lang/log/update_ali.$x.log \
          sgmm2-est --update-flags=$flags --remove-speaker-space=true --power=$power \
          $cur_shared_alimdl "sgmm2-sum-accs - $dir/$lang/$x.*.aliacc|" $dir/$lang/$[$x+1].alimdl || exit 1;
        rm $dir/$lang/$x.*.aliacc_shared $dir/$lang/$x.*.aliacc || exit 1;
        [ $x -gt $num_iters ]  && rm $dir/$lang/$x.alimdl $dir/$lang/$x.shared.alimdl
      fi
      cur_alimdls[$lang]=$dir/$lang/$[$x+1].alimdl
    done
    x=$[$x+1]
  done
  for lang in $(seq 0 $[$num_lang-1]); do
    rm $dir/$lang/final.alimdl 2>/dev/null 
    ln -s $x.alimdl $dir/$lang/final.alimdl
  done
fi

for lang in $(seq 0 $[$num_lang-1]); do
  utils/summarize_warnings.pl $dir/$lang/log
done

echo Done
