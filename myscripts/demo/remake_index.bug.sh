# TODO 此代码生成的索引有BUG！！！！ 用reorganize-index.sh重新组织索引
numjob=96

recipedir=/home/kaldi/code/kaldi-trunk/egs/babel/bnbc
tmpfsdir=/media/kws_demo/bnbc
#indices_dir=$tmpfsdir/exp/tri6_nnet_mpe/decode_eval.seg_ext_v2.kn0122_epoch1/kws_indices
indices_dir=$tmpfsdir/exp/tri6_nnet_mpe/decode_eval.seg_epoch1/kws_indices
lmwt=11
kwsdatadir=$tmpfsdir/data/eval.seg/kws
langdir=$tmpfsdir/lang
#decodedir=$recipedir/exp/tri6_nnet_mpe/decode_eval.seg_ext_v2.kn0122_epoch1
decodedir=$recipedir/exp/tri6_nnet_mpe/decode_eval.seg_epoch1

cmd="queue.pl -q all.q@@allhosts -l mem_free=10G,ram_free=10G"
max_states=150000
silence_word=
model_flags=
skip_optimization=false
word_ins_penalty=0
max_silence_frames=50
model_flags="--model `dirname $decodedir`/final.mdl"

reorg_decodedir=$decodedir/reorg_$numjob
mkdir -p $reorg_decodedir

org_nj=`cat $decodedir/num_jobs`

if [ ! -f $reorg_decodedir/num_jobs ]; then
    step=$[$org_nj/$numjob]
    for i in `seq 1 $numjob`; do
        echo "Generating lat.$i.gz ($i/$numjob) ..."
        files=`seq $[($i-1)*$step+1] $[$i*$step] | awk '{print "'$decodedir'/lat."$1".gz";}'`
        gzip -cdf $files | gzip -c > $reorg_decodedir/lat.$i.gz
    done
    echo $numjob > $reorg_decodedir/num_jobs
fi

indices=${indices_dir}_$lmwt/remake_$numjob
mkdir -p $indices

if [ ! -f $indices/.done ]; then
    acwt=`perl -e "print (1.0/$lmwt);"` 
    [ ! -z $silence_word ] && silence_opt="--silence-word $silence_word"
    czpScripts/kws/make_index.chenzp.sh $silence_opt --cmd "$cmd" --acwt $acwt $model_flags\
      --skip-optimization $skip_optimization --max-states $max_states \
      --word-ins-penalty $word_ins_penalty --max-silence-frames $max_silence_frames\
      $kwsdatadir $langdir $reorg_decodedir $indices  || exit 1
fi
