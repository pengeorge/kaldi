numjob=96
#rootdir=/media/kws_demo/bnbc
rootdir=/home/kaldi/code/kaldi-trunk/egs/babel/bnbc
indices_dir=$rootdir/exp/tri6_nnet_mpe/decode_eval.seg_ext_v2.kn0122_epoch1/kws_indices_11
skip_optimization=false
strict=true
max_states=150000

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

reorg_indexdir=$indices_dir/remake_$numjob
mkdir -p $reorg_indexdir
org_nj=`cat $indices_dir/num_jobs`
cmd="queue.pl -q all.q@@allhosts -l mem_free=6G,ram_free=6G"
if [ ! -f $reorg_indexdir/num_jobs ]; then
    step=$[$org_nj/$numjob]
    for i in `seq 1 $numjob`; do
        echo "Generating index.$i.gz ($i/$numjob) ..."
        files=`seq $[($i-1)*$step+1] $[$i*$step] | awk '{print "'$indices_dir'/index."$1".gz";}'`
        ($cmd JOB=1:1 $reorg_indexdir/log/remake.$i.log \
            kws-index-union --skip-optimization=$skip_optimization --strict=$strict --max-states=$max_states \
            "ark:gzip -cdf `echo $files` |" "ark:|gzip -c > $reorg_indexdir/index.$i.gz") &
    done
    wait
    echo $numjob > $reorg_indexdir/num_jobs
fi
#$cmd JOB=1:$nj $kwsdir/log/index.JOB.log \
#    lattice-add-penalty --word-ins-penalty=$word_ins_penalty "ark:gzip -cdf $decodedir/lat.JOB.gz|" ark:- \| \
#    lattice-scale --acoustic-scale=$acwt --lm-scale=$lmwt ark:- ark:- \| \
#    lattice-to-kws-index --max-silence-frames=$max_silence_frames --strict=$strict ark:$utter_id ark:- ark:- \| \
#    kws-index-union --skip-optimization=$skip_optimization --strict=$strict --max-states=$max_states \
#    ark:- "ark:|gzip -c > $kwsdir/index.JOB.gz"  || exit 1
