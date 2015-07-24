#!/bin/bash 
set -e
set -o pipefail

. conf/common_vars_leave1q.sh || exit 1;
. ./lang.conf || exit 1;


dir=dev10h.pem

force_score=false 

beam=10
lattice_beam=4

dev2shadow=dev10h.uem
eval2shadow=eval.uem
kind=
skip_scoring=false
max_states=150000

wip=0.5
shadow_set_extra_opts=( --wip $wip )

echo "run-1b-tri-decode.sh $@"

. utils/parse_options.sh

if [ $# -ne 0 ]; then
  echo "Usage: $(basename $0) --type (dev10h|dev2h|eval|shadow)"
  exit 1
fi

. ./czpScripts/prep_conf_and_data_for_decoding.sh

####################################################################
##
##  tri1 decoding 
##
####################################################################
decode=exp/tri1/decode_${dataset_id}-${beam}_${lattice_beam}
if [ ! -f ${decode}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning decoding with tri1 models (beam $beam, lat_beam $lattice_beam) on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang exp/tri1 exp/tri1/graph |tee exp/tri1/mkgraph.log

  mkdir -p $decode
  {
  steps/decode_si.sh --skip-scoring false --beam $beam --lattice-beam ${lattice_beam} \
    --nj $my_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
    exp/tri1/graph ${dataset_dir} ${decode} |tee ${decode}/decode.log
  touch ${decode}/.done
  echo ---------------------------------------------------------------------
  echo "Finished decoding with tri1 models (beam $beam, lat_beam $lattice_beam) on" `date`
  echo ---------------------------------------------------------------------
  } &
fi
####################################################################
##
##  tri2 decoding 
##
####################################################################
decode=exp/tri2/decode_${dataset_id}-${beam}_${lattice_beam}
if [ ! -f ${decode}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning decoding with tri2 models (beam $beam, lat_beam $lattice_beam) on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang exp/tri2 exp/tri2/graph |tee exp/tri2/mkgraph.log

  mkdir -p $decode
  {
  steps/decode.sh --skip-scoring false --beam $beam --lattice-beam ${lattice_beam} \
    --nj $my_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
    exp/tri2/graph ${dataset_dir} ${decode} |tee ${decode}/decode.log
  touch ${decode}/.done
  echo ---------------------------------------------------------------------
  echo "Finished decoding with tri2 models (beam $beam, lat_beam $lattice_beam) on" `date`
  echo ---------------------------------------------------------------------
  } &
fi
####################################################################
##
##  tri3 decoding 
##
####################################################################
decode=exp/tri3/decode_${dataset_id}-${beam}_${lattice_beam}
if [ ! -f ${decode}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning decoding with tri3 models (beam $beam, lat_beam $lattice_beam) on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang exp/tri3 exp/tri3/graph |tee exp/tri3/mkgraph.log

  mkdir -p $decode
  {
  steps/decode.sh --skip-scoring false --beam $beam --lattice-beam ${lattice_beam} \
    --nj $my_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
    exp/tri3/graph ${dataset_dir} ${decode} |tee ${decode}/decode.log
  touch ${decode}/.done
  echo ---------------------------------------------------------------------
  echo "Finished decoding with tri3 models (beam $beam, lat_beam $lattice_beam) on" `date`
  echo ---------------------------------------------------------------------
  } &
fi
####################################################################
##
##  tri4 (LDA+MLLT) decoding 
##
####################################################################
decode=exp/tri4/decode_${dataset_id}-${beam}_${lattice_beam}
if [ ! -f ${decode}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning decoding with LDA+MLLT models (beam $beam, lat_beam $lattice_beam) on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang exp/tri4 exp/tri4/graph |tee exp/tri4/mkgraph.log

  mkdir -p $decode
  {
  steps/decode.sh --skip-scoring false --beam $beam --lattice-beam ${lattice_beam} \
    --nj $my_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
    exp/tri4/graph ${dataset_dir} ${decode} |tee ${decode}/decode.log
  touch ${decode}/.done
  echo ---------------------------------------------------------------------
  echo "Finished decoding with LDA+MLLT models (beam $beam, lat_beam $lattice_beam) on" `date`
  echo ---------------------------------------------------------------------
  } &
fi

wait;

####################################################################
##
## FMLLR decoding 
##
####################################################################
decode_base=exp/tri5/decode_${dataset_id}
decode_full=${decode_base}-${beam}_${lattice_beam}
if [ ! -f ${decode_full}/.done ]; then
  if [ -f ${decode_base}/.done ]; then
    default_beam_conf=`sed -n '3p' $decode_base/log/decode2.1.log | grep -Po '\-\-beam=[\d\.]+ \-\-lattice\-beam=[\d\.]+'`
    default_beam=`echo $default_beam_conf | grep -Po '(?<=\-\-beam=)[\d\.]+'`
    default_lattice_beam=`echo $default_beam_conf | grep -Po '(?<=\-\-lattice\-beam=)[\d\.]+'`
  else
    default_beam=$sat_beam
    default_lattice_beam=$sat_lat_beam
  fi
  if [ $beam -eq $default_beam ] && [ $lattice_beam -eq $default_lattice_beam ]; then
    # If beam configuration is by default, results in $decode_base
    # would be used.
    ln -s `basename $decode_base` $decode_full
    decode=$decode_base
  else
    decode=$decode_full
  fi
  if [ ! -f ${decode}/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Spawning decoding with SAT models (beam $beam, lat_beam $lattice_beam) on" `date`
    echo ---------------------------------------------------------------------
    utils/mkgraph.sh \
      data/lang exp/tri5 exp/tri5/graph |tee exp/tri5/mkgraph.log

    mkdir -p $decode
    #By default, we do not care about the lattices for this step -- we just want the transforms
    #Therefore, we will reduce the beam sizes, to reduce the decoding times
    steps/decode_fmllr_extra.sh --skip-scoring false --beam ${beam} --lattice-beam ${lattice_beam} \
      --nj $my_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
      exp/tri5/graph ${dataset_dir} ${decode} |tee ${decode}/decode.log
    touch ${decode}/.done
    echo ---------------------------------------------------------------------
    echo "Finished decoding with SAT models (beam $beam, lat_beam $lattice_beam) on" `date`
    echo ---------------------------------------------------------------------
  fi
fi

echo "Everything looking good...." 
exit 0
