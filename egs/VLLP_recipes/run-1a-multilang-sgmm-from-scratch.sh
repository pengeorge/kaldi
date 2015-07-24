#!/bin/bash

# Main training recipe for VLLP in the official LPDefs
# This is not necessarily the top-level run.sh as it is in other directories.   see README.txt first.
sgmm5_only=true
mlsuffix=4lang10hr
langres='101LLP 104LLP 105LLP 106LLP'
init_ali=exp/tri3_ali
#langres='101N 104N 105N 106N 107N 204N'

[ ! -f ./lang.conf ] && echo 'Language configuration does not exist! Use the configurations in conf/lang/* as a startup' && exit 1
[ ! -f ./conf/common_vars.sh ] && echo 'the file conf/common_vars.sh does not exist!' && exit 1

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;
. conf/multilang_resource.conf

[ -f local.conf ] && . ./local.conf

. ./utils/parse_options.sh

set -e           #Exit on non-zero return code from any command
set -o pipefail  #Exit if any of the commands in the pipeline will 
                 #return non-zero return code
#set -u           #Fail on an undefined variable

multilang_opt=
for l in $langres; do
  egs_dir=${mlresource[$l]}
  lroot=$(dirname `dirname $egs_dir`)
  alidir=$lroot/$init_ali
  multilang_opt="$multilang_opt $lroot/data/train $lroot/data/lang $alidir"
done

mldir=sgmm_${mlsuffix}
mkdir -p $mldir

################################################################################
# Ready to start SGMM training
################################################################################

if [ ! -f exp/$mldir/ubm5/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/ubm5_ml on" `date`
  echo ---------------------------------------------------------------------
  ./czpScripts/ml_sgmm/train_ubm_multilang.sh \
    --cmd "$train_cmd" $numGaussUBM \
    $multilang_opt exp/$mldir/ubm5
  touch exp/$mldir/ubm5/.done
fi

if [ ! -f exp/$mldir/sgmm5/.done.ml ]; then
  echo ---------------------------------------------------------------------
  echo "Starting multilingual SGMM training in exp/$mldir/sgmm5 on" `date`
  echo ---------------------------------------------------------------------
  ./czpScripts/ml_sgmm/train_sgmm2_multilang.sh --spk-dim 0 --stage 4 \
    --cmd "$train_cmd" $numLeavesSGMM $numGaussSGMM \
    $multilang_opt exp/$mldir/ubm5/final.ubm exp/$mldir/sgmm5
  #steps/train_sgmm2_group.sh \
  #  --cmd "$train_cmd" "${sgmm_group_extra_opts[@]-}" $numLeavesSGMM $numGaussSGMM \
  #  data/train data/lang exp/tri5_ali exp/ubm5/final.ubm exp/sgmm5
  touch exp/$mldir/sgmm5/.done.ml
fi
if [ ! -f exp/$mldir/sgmm5/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting SGMM fine tuning in exp/$mldir/sgmm5 on" `date`
  echo ---------------------------------------------------------------------
  ./czpScripts/ml_sgmm/train_sgmm2_finetune.sh --stage 5 \
    --beam 8 --retry-beam 40 \
    --cmd "$train_cmd" $numLeavesSGMM $numGaussSGMM \
    data/train data/lang exp/tri3_ali exp/$mldir/sgmm5/0/final.mdl exp/$mldir/sgmm5_ft
  touch exp/$mldir/sgmm5/.done
fi

if $sgmm5_only ; then
  echo "Exiting after stage SGMM5, as requested. "
  echo "Everything went fine. Done"
  exit 0;
fi
################################################################################
# Ready to start discriminative SGMM training
################################################################################

if [ ! -f exp/$mldir/sgmm5_ali/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/$mldir/sgmm5_ali on" `date`
  echo ---------------------------------------------------------------------
  steps/align_sgmm2.sh \
    --nj $train_nj --cmd "$train_cmd" --transform-dir exp/tri5_ali \
    --use-graphs true --use-gselect true \
    data/train data/lang exp/$mldir/sgmm5 exp/$mldir/sgmm5_ali
  touch exp/$mldir/sgmm5_ali/.done
fi


if [ ! -f exp/$mldir/sgmm5_denlats/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/$mldir/sgmm5_denlats on" `date`
  echo ---------------------------------------------------------------------
  steps/make_denlats_sgmm2.sh \
    --nj $train_nj --sub-split 4 "${sgmm_denlats_extra_opts[@]}" \
    --beam 10.0 --lattice-beam 6 --cmd "$decode_cmd" --transform-dir exp/tri5_ali \
    data/train data/lang exp/$mldir/sgmm5_ali exp/$mldir/sgmm5_denlats
  touch exp/$mldir/sgmm5_denlats/.done
fi

if [ ! -f exp/$mldir/sgmm5_mmi_b0.1/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/$mldir/sgmm5_mmi_b0.1 on" `date`
  echo ---------------------------------------------------------------------
  steps/train_mmi_sgmm2.chenzp.sh \
    --cmd "$train_cmd" "${sgmm_mmi_extra_opts[@]}" \
    --drop-frames true --transform-dir exp/tri5_ali --boost 0.1 \
    data/train data/lang exp/$mldir/sgmm5_ali exp/$mldir/sgmm5_denlats \
    exp/$mldir/sgmm5_mmi_b0.1
  touch exp/$mldir/sgmm5_mmi_b0.1/.done
fi

echo ---------------------------------------------------------------------
echo "Finished successfully on" `date`
echo ---------------------------------------------------------------------

exit 0
