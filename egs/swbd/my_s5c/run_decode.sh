#!/bin/bash

. cmd.sh
. path.sh

# This setup was modified from egs/swbd/s5b, with the following changes:
# 1. added more training data for early stages
# 2. removed SAT system (and later stages) on the 100k utterance training data
# 3. reduced number of LM rescoring, only sw1_tg and sw1_fsh_fg remain
# 4. mapped swbd transcription to fisher style, instead of the other way around 

set -e # exit on error
has_fisher=false
nj1=80
nj2=80

# If you have the Fisher data, you can set this "fisher_dir" variable.
fisher_dirs=
# fisher_dirs="/home/dpovey/data/LDC2004T19/fe_03_p1_tran/"
# fisher_dirs="/data/corpora0/LDC2004T19/fe_03_p1_tran/"
# fisher_dirs="/exports/work/inf_hcrc_cstr_general/corpora/fisher/transcripts" # Edinburgh,
# fisher_dirs="/mnt/matylda2/data/FISHER/fe_03_p1_tran /mnt/matylda2/data/FISHER/fe_03_p2_tran" # BUT,

# Data preparation and formatting for eval2000 (note: the "text" file
# is not very much preprocessed; for actual WER reporting we'll use
# sclite.

# local/eval2000_data_prep.sh /data/corpora0/LDC2002S09/hub5e_00 /data/corpora0/LDC2002T43
# local/eval2000_data_prep.sh /mnt/matylda2/data/HUB5_2000/ /mnt/matylda2/data/HUB5_2000/2000_hub5_eng_eval_tr
# local/eval2000_data_prep.sh /exports/work/inf_hcrc_cstr_general/corpora/switchboard/hub5/2000 /exports/work/inf_hcrc_cstr_general/corpora/switchboard/hub5/2000/transcr
# local/eval2000_data_prep.sh /home/dpovey/data/LDC2002S09/hub5e_00 /home/dpovey/data/LDC2002T43
local/eval2000_data_prep.sh /home/kaldi/data/eval2000 /home/kaldi/data/eval2000/LDC2002T43/2000_hub5_eng_eval_tr

# Now make MFCC features.
# mfccdir should be some place with a largish disk where you
# want to store MFCC features.
mfccdir=mfcc
for x in eval2000; do
  steps/make_mfcc.sh --nj $nj2 --cmd "$train_cmd" \
    data/$x exp/make_mfcc/$x $mfccdir
  steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x $mfccdir 
  utils/fix_data_dir.sh data/$x
done

# tri1
graph_dir=exp/tri1/graph_nosp_sw1_tg
$train_cmd $graph_dir/mkgraph.log \
  utils/mkgraph.sh data/lang_nosp_sw1_tg exp/tri1 $graph_dir
steps/decode_si.sh --nj $nj1 --cmd "$decode_cmd" --config conf/decode.config \
  $graph_dir data/eval2000 exp/tri1/decode_eval2000_nosp_sw1_tg
  
# tri2
# The previous mkgraph might be writing to this file.  If the previous mkgraph
# is not running, you can remove this loop and this mkgraph will create it.
while [ ! -s data/lang_nosp_sw1_tg/tmp/CLG_3_1.fst ]; do sleep 60; done
sleep 20; # in case still writing.
graph_dir=exp/tri2/graph_nosp_sw1_tg
$train_cmd $graph_dir/mkgraph.log \
  utils/mkgraph.sh data/lang_nosp_sw1_tg exp/tri2 $graph_dir
steps/decode.sh --nj $nj1 --cmd "$decode_cmd" --config conf/decode.config \
  $graph_dir data/eval2000 exp/tri2/decode_eval2000_nosp_sw1_tg

# tri3
graph_dir=exp/tri3/graph_nosp_sw1_tg
$train_cmd $graph_dir/mkgraph.log \
  utils/mkgraph.sh data/lang_nosp_sw1_tg exp/tri3 $graph_dir
steps/decode.sh --nj $nj1 --cmd "$decode_cmd" --config conf/decode.config \
  $graph_dir data/eval2000 exp/tri3/decode_eval2000_nosp_sw1_tg

# tri3 (sp)
graph_dir=exp/tri3/graph_sw1_tg
$train_cmd $graph_dir/mkgraph.log \
  utils/mkgraph.sh data/lang_sw1_tg exp/tri3 $graph_dir
steps/decode.sh --nj $nj1 --cmd "$decode_cmd" --config conf/decode.config \
  $graph_dir data/eval2000 exp/tri3/decode_eval2000_sw1_tg

# tri4j
graph_dir=exp/tri4/graph_sw1_tg
$train_cmd $graph_dir/mkgraph.log \
  utils/mkgraph.sh data/lang_sw1_tg exp/tri4 $graph_dir
steps/decode_fmllr.sh --nj $nj1 --cmd "$decode_cmd" \
  --config conf/decode.config \
  $graph_dir data/eval2000 exp/tri4/decode_eval2000_sw1_tg

if $has_fisher; then
  steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
    data/lang_sw1_{tg,fsh_fg} data/eval2000 \
    exp/tri4/decode_eval2000_sw1_{tg,fsh_fg}
fi

# 4 iterations of MMI seems to work well overall. The number of iterations is
# used as an explicit argument even though train_mmi.sh will use 4 iterations by
# default.
num_mmi_iters=4
for iter in 1 2 3 4; do
  graph_dir=exp/tri4/graph_sw1_tg
  decode_dir=exp/tri4_mmi_b0.1/decode_eval2000_${iter}.mdl_sw1_tg
  steps/decode.sh --nj $nj2 --cmd "$decode_cmd" \
    --config conf/decode.config --iter $iter \
    --transform-dir exp/tri4/decode_eval2000_sw1_tg \
    $graph_dir data/eval2000 $decode_dir
done

if $has_fisher; then
  for iter in 1 2 3 4;do
    steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
      data/lang_sw1_{tg,fsh_fg} data/eval2000 \
      exp/tri4_mmi_b0.1/decode_eval2000_${iter}.mdl_sw1_{tg,fsh_fg}
  done
fi

for iter in 4 5 6 7 8; do
  graph_dir=exp/tri4/graph_sw1_tg
  decode_dir=exp/tri4_fmmi_b0.1/decode_eval2000_it${iter}_sw1_tg
  steps/decode_fmmi.sh --nj $nj1 --cmd "$decode_cmd" --iter $iter \
    --transform-dir exp/tri4/decode_eval2000_sw1_tg \
    --config conf/decode.config $graph_dir data/eval2000 $decode_dir
done
wait

if $has_fisher; then
  for iter in 4 5 6 7 8; do
    steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
      data/lang_sw1_{tg,fsh_fg} data/eval2000 \
      exp/tri4_fmmi_b0.1/decode_eval2000_it${iter}_sw1_{tg,fsh_fg}
  done
fi

# this will help find issues with the lexicon.
# steps/cleanup/debug_lexicon.sh --nj 300 --cmd "$train_cmd" data/train_nodev data/lang exp/tri4 data/local/dict/lexicon.txt exp/debug_lexicon

# SGMM system.
# local/run_sgmm2.sh $has_fisher

# Karel's DNN recipe on top of fMLLR features
# local/nnet/run_dnn.sh --has-fisher $has_fisher

# Dan's nnet recipe
# local/nnet2/run_nnet2.sh --has-fisher $has_fisher

# Dan's nnet recipe with online decoding.
# local/online/run_nnet2_ms.sh --has-fisher $has_fisher

# demonstration script for resegmentation.
# local/run_resegment.sh

# demonstration script for raw-fMLLR.  You should probably ignore this.
# local/run_raw_fmllr.sh

# getting results (see RESULTS file)
# for x in 1 2 3a 3b 4a; do grep 'Percent Total Error' exp/tri$x/decode_eval2000_sw1_tg/score_*/eval2000.ctm.filt.dtl | sort -k5 -g | head -1; done
