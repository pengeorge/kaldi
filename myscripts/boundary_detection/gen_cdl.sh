#!/bin/bash
dataname=bound_det_train
split=true
datadir=data/train
mdldir=exp/tri6_nnet
subset=  # If only a subset of sequences in $datadir is used
exclude= # If  a subset of sequences in $datadir is excluded
feat_type= # lda/raw, default: lda

splice=0

. path.sh
. cmd.sh
. ./utils/parse_options.sh

set -e

alidir=${mdldir}_ali
dir=$alidir/$dataname

echo ==================================
echo Start generating CDL and nc files
echo ==================================
echo "dataname=$dataname"
echo "split=$split"
echo "datadir=$datadir"
echo "mdldir=$mdldir"
echo "subset=$subset"
echo "exclude=$exclude"
echo "splice=$splice"
echo

if [ ! -z $subset ] && [ ! -f $subset ]; then
  echo "File $subset does not exist"
  exit 1
fi
if [ ! -z $exclude ] && [ ! -f $exclude ]; then
  echo "File $exclude does not exist"
  exit 1
fi
if [ ! -d $alidir ]; then
  echo "Alignment dir $alidir does not exist."
  exit 1
fi
if [ ! -f $alidir/align.show ]; then
  echo ===============================
  echo  Generating $alidir/align.show
  echo ===============================
  show-alignments data/lang/phones.txt $mdldir/final.mdl "ark:gunzip -cdf $alidir/ali.*.gz |" > $alidir/align.show
fi
if [ ! -f $alidir/boundSeq.txt ] || [ $alidir/boundSeq.txt -ot $alidir/align.show ]; then
  echo =================================
  echo  Generating $alidir/boundSeq.txt
  echo =================================
  perl czpScripts/align/align-show-to-01.pl $alidir/align.show > $alidir/boundSeq.txt
fi
cut -f 1 $alidir/boundSeq.txt > $alidir/seqTags_in_ali.txt

nj=`cat $alidir/num_jobs`
if [ -z $nj ]; then
  "Number of jobs is not defined"
  exit 1
fi
if $split; then
  cmd=$train_cmd
  sdata=$datadir/split$nj
  if [ ! -d $sdata ]; then
    echo "Split directory does not exist"
    exit 1
  fi
  sdata=$sdata/JOB
else
  cmd=run.pl
  sdata=$datadir
  if [ ! -d $sdata ]; then
    echo "Split directory does not exist"
    exit 1
  fi
fi

mkdir -p $dir

if [ ! -f $dir/feats.txt ]; then
  echo ===================================
  echo "Transform binary features to text"
  echo ===================================
  feats="ark,s,cs:utils/filter_scp.pl $alidir/seqTags_in_ali.txt $sdata/feats.scp |"
  if [ -z $exclude ]; then
    feats="$feats utils/filter_scp.pl $subset - | apply-cmvn --norm-vars=false --utt2spk=ark:$sdata/utt2spk scp:$sdata/cmvn.scp scp:- ark:- |"
  else
    feats="$feats utils/filter_scp.pl --exclude $exclude - | apply-cmvn --norm-vars=false --utt2spk=ark:$sdata/utt2spk scp:$sdata/cmvn.scp scp:- ark:- |"
  fi
  if [ -z $feat_type ] || [ "$feat_type" = lda ]; then
    # splice and then LDA
    feats="$feats splice-feats  ark:- ark:- | transform-feats $mdldir/final.mat ark:- ark:- |"
  fi
  if $split; then
    if [ -z $feat_type ] || [ "$feat_type" = lda ]; then
      # per-speaker transform
      feats="$feats transform-feats --utt2spk=ark:$sdata/utt2spk ark:exp/tri5_ali/trans.JOB ark:- ark:- |"
    fi
    $cmd JOB=1:$nj $dir/log/feats_to_txt.JOB.log \
      feats-to-txt --left-context=$splice --right-context=$splice "$feats" $dir/seqTags.JOB.txt $dir/feats.JOB.txt
    cp $dir/seqTags.1.txt $dir/seqTags.txt
    cp $dir/feats.1.txt $dir/feats.txt
    for i in `seq 2 $nj`; do
      cat $dir/seqTags.${i}.txt >> $dir/seqTags.txt
      cat $dir/feats.${i}.txt >> $dir/feats.txt
    done
  else
    if [ -z $feat_type ] || [ "$feat_type" = lda ]; then
      # per-speaker transform
      feats="$feats transform-feats --utt2spk=ark:$sdata/utt2spk 'ark:cat exp/tri5_ali/trans.*|' ark:- ark:- |"
    fi
    $cmd $dir/log/feats_to_txt.log \
      feats-to-txt --left-context=$splice --right-context=$splice "$feats" $dir/seqTags.txt $dir/feats.txt
  #    feats-to-txt --left-context=$splice --right-context=$splice "ark,s,cs:utils/filter_scp.pl --exclude $exclude $sdata/JOB/feats.scp | apply-cmvn --norm-vars=false --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:- ark:- | splice-feats  ark:- ark:- | transform-feats $mdldir/final.mat ark:- ark:- | transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark:exp/tri5_ali/trans.JOB ark:- ark:- |" $dir/seqTags.JOB.txt $dir/feats.JOB.txt
  fi
fi

echo ===================================
echo "Filter boundSeq"
echo ===================================
if [ -f $dir/boundSeq.filtered.txt ]; then
  rm $dir/boundSeq.filtered.txt
fi
for id in `cat $dir/seqTags.txt`; do
  grep $id $alidir/boundSeq.txt >> $dir/boundSeq.filtered.txt
done
#cut -f 1 $dir/boundSeq.filtered.txt > $dir/seqTags.txt
#cat $dir/feats.all.txt | perl -e '
#  open(ALL, "'$dir/seqTags.all.txt'") or die "cannot open seqTags.all.txt";
#  open(FIL, "'$dir/boundSeq.filtered.txt'") or die "cannot open boundSeq.filtered.txt";
#  while ($line = <FIL>) {
#    @col = split(/\t/, $line);
#    $fil = $col[0];
#    $num = $col[1];
#    $all = <ALL>;
#    while ($all != $fil) {
#      $all = <ALL>;
#    }
#    print " [\n";
#    print $feat;
#  }
#  close(ALL);
#  close(FIL);' > $dir/feats.txt
#exit 0;

echo ===================================
echo "Output CDL and nc files"
echo ===================================
{
echo "targetStrings ="
sed '$d' $dir/boundSeq.filtered.txt | cut -f 3 | sed 's:^\(.*\)$:  "\1",:'
tail -n 1 $dir/boundSeq.filtered.txt | cut -f 3 | sed 's:^\(.*\)$:  "\1" ;:'
echo

echo "seqTags ="
sed '$d' $dir/seqTags.txt | sed 's:^\(.*\)$:  "\1",:'
tail -n 1 $dir/seqTags.txt | sed 's:^\(.*\)$:  "\1" ;:'
echo

echo "seqLengths = `cut -f 2 $dir/boundSeq.filtered.txt | paste -sd',' | sed 's:,:, :g'` ;"
echo

echo "targetClasses = `cut -f 3 $dir/boundSeq.filtered.txt | paste -sd' ' | sed 's: :, :g'` ;"
echo

echo "inputs ="
cat $dir/feats.txt | sed 's:^ \+::' | grep -v "\[" | sed 's:]::' | sed 's: :, :g'
} > $dir/part2.cdl.tmp
sed '$s/, $/ ;/' $dir/part2.cdl.tmp > $dir/part2.cdl

cat > $dir/part1.cdl << EOF
netcdf $dataname {
dimensions:
	numSeqs = `cat $dir/seqTags.txt | wc -l` ;
	numTimesteps = `awk 'BEGIN{s=0}{s+=$2}END{print s}' $dir/boundSeq.filtered.txt` ;
  inputPattSize = `sed -n '2p' $dir/feats.txt | awk '{print NF-1}'` ;
	numLabels = 2 ;
	maxLabelLength = 1 ;
	maxTargStringLength = 60000 ;
	maxSeqTagLength = 100 ;
variables:
	int numTargetClasses ;
		numTargetClasses:longname = "number of target classes" ;
	char labels(numLabels, maxLabelLength) ;
		labels:longname = "target labels" ;
	char targetStrings(numSeqs, maxTargStringLength) ;
		targetStrings:longname = "target strings" ;
	char seqTags(numSeqs, maxSeqTagLength) ;
		seqTags:longname = "sequence tags" ;
	int seqLengths(numSeqs) ;
		seqLengths:longname = "sequence seqLengths" ;
	int targetClasses(numTimesteps) ;
		targetClasses:longname = "target classes" ;
	float inputs(numTimesteps, inputPattSize) ;
		inputs:longname = "inputs adjusted for mean 0 and std dev 1" ;

data:

  numTargetClasses = 2 ;

  labels = "0", "1";

EOF

cat $dir/part1.cdl $dir/part2.cdl > $dir/${dataname}.cdl
echo '}' >> $dir/${dataname}.cdl
ncgen -o $dir/${dataname}.nc -x $dir/${dataname}.cdl

echo ===================================
echo "Done."
echo ===================================
