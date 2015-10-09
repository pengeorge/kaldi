#!/bin/bash
set -e

. cmd.sh
. path.sh

# chenzp 2014
# This is for swbd recipe

if [ $# != 3 ]; then
    echo "Usage: $0 <model-name> <data-dir> <decode-dir>"
    echo "e.g. $0 tri4a data/eval_dev decode_eval_dev_viet_tg"
    exit 1;
fi

model=$1
datadir=$2
decodedir=$3

if [ ! -d exp/$model ]; then
    echo "[ERROR] Model $model doesn't exist."
    exit 1;
fi

tmp=`ls -l exp/$model/$decodedir/wer* 2>/dev/null | wc -l`
if [ $tmp = 0 ]; then
    echo "[INFO] No decoding results or scoring results. Now we'll do decoding first."
    graph_dir=exp/$model/graph_viet_tg
    if [ ! -d $graph_dir ]; then
        if [[ "$model" =~ 'mono' ]]; then
            mono='--mono'
        fi
        echo "Making graph..."
        $train_cmd $graph_dir/mkgraph.log \
          utils/mkgraph.sh $mono data/lang_viet_tg exp/$model $graph_dir
    fi
    case $model in
      *nnet*) decoder='steps/nnet2/decode.sh --transform-dir exp/tri4a/decode_eval_dev_viet_tg';;
      *dnn*) decoder=steps/decode_nnet.sh;;
#  echo '[WARN] in DNN case, graph_dir and decode_dir name is not standard as that of tri*, please do decoding on eval_dev first and then rerun this script.'
#  exit 1;;
      *fmmi*) decoder='steps/decode_fmmi.sh --iter 6 --transform-dir exp/tri4a/decode_eval_dev_viet_tg';;
      *mmi*) decoder='steps/decode.sh --iter 3 --tansform-dir exp/tri4a/decode_eval_dev_viet_tg';;
      tri4*) decoder=steps/decode_fmllr.sh;;
      tri3*)  decoder=steps/decode.sh;;
      tri2)  decoder=steps/decode.sh;;
      tri1)  decoder=steps/decode_si.sh;;
      mono*)  decoder=steps/decode_si.sh;;
    esac
    $decoder --nj 12 --cmd "$decode_cmd" --config conf/decode.config \
      $graph_dir $datadir exp/$model/$decodedir

fi

# for tri4a of Viet, 16 is the optimal LMWT
wer_lines=`grep WER exp/$model/$decodedir/wer*`
lmwt=`echo $wer_lines | grep -P -o 'wer_\d+' | grep -P -o '\d+' | paste - <(echo $wer_lines | grep -P -o '\d+\.\d\d+') | awk 'BEGIN{min=10000;id=-1}{if ($2<min) {min=$2;id=$1}} END {print id}'`

if [ ! -f "exp/$model/$decodedir/phone_confusion.$lmwt.txt" ]; then
    echo "Phone confusion file 'exp/$model/$decodedir/phone_confusion.$lmwt.txt' not exists, now training it."
	if [ ! -d "exp/$model/$decodedir/scoring/ali" ]; then
        echo "score_basic.gen_ali.sh ..."
	    czpScripts/utils/score_basic.gen_ali.sh --cmd run.pl $datadir exp/$model/graph_viet_tg exp/$model/$decodedir
	fi
    if [ ! -d "exp/$model/$decodedir/scoring/ali/view.$lmwt" ]; then
    	echo "make-phone-align-readable.pl ..."
    	perl czpScripts/make-phone-align-readable.pl data/lang/phones.txt exp/$model/final.mdl exp/$model/$decodedir/scoring/ali/$lmwt.ali data/lang/phones/align_lexicon.txt exp/$model/$decodedir/scoring/$lmwt.txt exp/$model/$decodedir/scoring/ali/view.$lmwt
	fi
    fadir="exp/${model}_ali_"`basename $datadir`
    if [ ! -f "$fadir/view/.done" ]; then
        if [ ! -f "$fadir/.done" ]; then
            echo "Doing FA to get references"
    	    case $model in
              *nnet*) aligner='steps/nnet2/align.sh --transform-dir exp/tri4a/decode_eval_dev_viet_tg';;
    	      *dnn*) aligner=steps/align_nnet.sh;;
    	      *mmi*) aligner=steps/align_fmllr.sh;;
    	      tri4*) aligner=steps/align_fmllr.sh;;
    	      tri3b)  aligner=steps/align_fmllr.sh;;
    	      *)  aligner=steps/align_si.sh;;  # tri3, tri2, tri1, mono
    	    esac
            $aligner --nj 12 --cmd "$train_cmd" \
              $datadir data/lang exp/$model $fadir;
            touch $fadir/.done
        fi
        echo "make-ref-align-readable.sh ..."
        czpScripts/make-ref-align-readable.sh $fadir $datadir
        touch $fadir/view/.done
    fi
	echo "count-phone-confusion.pl ..."
	perl czpScripts/utils/count-phone-confusion.pl exp/$model/$decodedir/scoring/ali/view.$lmwt/$lmwt.ali.mlf.phone $fadir/view/ali.\*.gz.mlf.phone exp/$model/$decodedir/phone_confusion.$lmwt.txt 12 > exp/$model/$decodedir/log/count_phone_confusion.$lmwt.log
fi

pushd $datadir >/dev/null
ln -sf ../../exp/$model/$decodedir/phone_confusion.$lmwt.txt phone_confusion.$model.$lmwt.txt
popd >/dev/null

echo "Successfully creating phone confusion file."
