#!/bin/bash
. path.sh
. cmd.sh
. lang.conf
mkdir -p exp_bnf_semisup/best_path_weights/unsup.seg_ext

sys=" ./exp/dnn_scratch_6langFLPNN.raw_cont_mpe/decode_unsup.seg_ext_epoch1
  ./exp/cnn4c_pretrain-dbn_dnn_smbr/decode_unsup.seg_ext_it2
  ./exp/sgmm5_mmi_b0.1/decode_fmllr_unsup.seg_ext_it1
  ./exp_bnf_6langFLPNN.raw_ft/sgmm7_mmi_b0.1/decode_fmllr_unsup.seg_ext_it1
  ./exp_bnf_6langFLPNN.raw_ft/tri7_nnet/decode_unsup.seg_ext"

echo $sys > exp_bnf_semisup/best_path_weights/unsup.seg_ext/sys.list
./local/best_path_weights.sh --cmd "$train_cmd" data/unsup.seg_ext  data/lang_ext \
  $sys \
  exp_bnf_semisup/best_path_weights/unsup.seg_ext
