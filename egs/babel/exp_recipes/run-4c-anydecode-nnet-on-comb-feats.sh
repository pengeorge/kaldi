#!/bin/bash
# Apache 2.0

# decode BNF + sgmm_mmi system 
set -e
set -o pipefail

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;
[ -f local.conf ] && . ./local.conf


dir=dev10h.pem

run_kws_stt_bg=true
# If true, scoring STT and KWS for multiple models will not block this script,
# which utilize CPU resources for next decoding when executing the
# time-consuming lattice-to-ctm.
# Available only when cmd is "queue.pl ..."

expsuffix=concat_4lang10hr.raw_3hid  #suffix for exp dir
append_fmllr=false
fmllr_splice_width=0 # useful only when append_fmllr=true
bnf_input_feat_type=

kind=
data_only=false
fast_path=true

skip_kws=true
skip_stt=false
skip_scoring=false

subset_kws=false
basic_kws=false #      (default in run_kws_stt: false)
extra_kws=true
oov_kws=true
vocab_kws=false
ive_kws=false   # whether to do IV expansion
id=4 # ive type id
self_prior=true
lm_in_expansion=false
use_total_weight=$use_total_weight  # this will override lang.conf

model4cm=tri6_nnet # the model we use for confusion matrix training. MUST have _ali and _denlats generated
                # e.g. sgmm5 /  tri6_nnet

### This parameters is used for IV expansion experiment
nbest_set="1000"
lambda_set="0.5"
#lambda_set="0.0 0.2 0.4 0.5 0.6 0.8 1.0"
### End of IV exp configuration

tmpdir=`pwd`
semisupervised=true
unsup_string=
whole_suffix=    # the whole suffix after *_bnf, if set, this will override expsuffix and unsup_string 
input_feats=   # input feats of BNF NN

transform_feats=

ext= # suffix of various directories, indicating LM type.
ext_pron=  # TODO not implemented in extra_kws.sh and apply_g2p.sh
### For extra beam decoding ###
extra_beam=
extra_lattice_beam=
###############################

. utils/parse_options.sh

type=$dir

if [ $# -ne 0 ]; then
  echo "Usage: $(basename $0) --type (dev10h|dev2h|eval|shadow)"
  echo  "--semisupervised<true>  #set to false to skip unsupervised training."
  exit 1
fi

if [ -z "$unsup_string" ] ; then
  if $semisupervised ; then
    unsup_string="_semisup"
  else
    unsup_string=""  #" ": supervised training, _semi_supervised: unsupervised BNF training
  fi
fi

if [ -z "$expsuffix" ]; then
  echo "expsuffix cannot be empty"
  exit 1;
fi

if [ -z "$transform_feats" ]; then # Guess transform_feats
  if [ -z "$expsuffix" ] && [ -z "$whole_suffix" ]; then
    transform_feats=true
  elif [ ! -z "$expsuffix" ]; then # ml case
    if echo $expsuffix | grep -F '.raw'; then
      transform_feats=false
    else
      transform_feats=true
    fi
  else # unknown case
    echo "Cannot decide --transform-feats option, set it manually."
    exit 1;
  fi
fi

if [ ! -z "$ext" ]; then
  if [ `diff data/lang/words.txt data/lang_${ext}/words.txt | wc -l` -gt 0 ]; then # if lex are extended
    ext_lex=${ext}
  else
    ext_lex=
  fi
  ext=_${ext}
else
  ext_lex=
fi

if [ ! -z "$ext_pron" ]; then
  echo "$ext_pron not supported yet."
  exit 1;
fi

if ! echo {dev10h,dev2h,eval,unsup,shadow,tun3h}{.pem,.uem,.seg} | grep -w "$type" >/dev/null; then
  # note: echo dev10.uem | grep -w dev10h will produce a match, but this
  # doesn't matter because dev10h is also a valid value.
  echo "Invalid variable type=${type}, valid values are " {dev10h,dev2h,eval,unsup}{,.uem,.seg}
  exit 1;
fi

dataset_segments=${dir##*.}
dataset_id=$dir
dataset_type=${dir%%.*}
#By default, we want the script to accept how the dataset should be handled,
#i.e. of  what kind is the dataset
if [ -z ${kind} ] ; then
  if [ "$dataset_type" == "dev2h" ] || [ "$dataset_type" == "dev10h" ] || [ "$dataset_type" == "tun3h" ]; then
    dataset_kind=supervised
  else
    dataset_kind=unsupervised
  fi
else
  dataset_kind=$kind
fi

if [ -z $dataset_segments ]; then
  echo "You have to specify the segmentation type as well"
  echo "If you are trying to decode the PEM segmentation dir"
  echo "such as data/dev10h, specify dev10h.pem"
  echo "The valid segmentations types are:"
  echo "\tpem   #PEM segmentation"
  echo "\tuem   #UEM segmentation in the CMU database format"
  echo "\tseg   #UEM segmentation (kaldi-native)"
fi

if [ "$dataset_kind" == "unsupervised" ]; then
  skip_scoring=true
fi

root_expsuffix=$expsuffix # backup
if $append_fmllr; then
  expsuffix=${expsuffix}_fmllr
  if [ $fmllr_splice_width -gt 0 ]; then
    expsuffix=${expsuffix}X$[2*$fmllr_splice_width+1]
  fi
fi

dirid=${type}
if [ ! -z "$whole_suffix" ]; then
  exp_dir=exp_${whole_suffix}
  data_dir=data_${whole_suffix}
  param_dir=param_${whole_suffix}
else
  if [ ! -z "$expsuffix" ]; then
    expsuffix=_${expsuffix}
  fi
  exp_dir=exp${expsuffix}
  data_dir=data${expsuffix}
  param_dir=param${expsuffix}
fi
datadir=$data_dir/${dirid}    
eval my_nj=\$${dataset_type}_nj

lockfile=.lock.decode.${exp_dir}-${ext}.$dir
if [ -f $lockfile ]; then
  echo "Cannot run decoding because $lockfile exists."
  exit 1;
fi
touch $lockfile

#This seems to be the only functioning way how to ensure the comple
#set of scripts will exit when sourcing several of them together
#Otherwise, the CTRL-C just terminates the deepest sourced script ?
# Let shell functions inherit ERR trap.  Same as `set -E'.
set -o errtrace 
trap "echo Exited!; exit;" SIGINT SIGTERM

if $run_kws_stt_bg && [[ $decode_cmd =~ ^queue ]]; then
  bg_flag='&'
else
  bg_flag=
fi

# Prepare another dataset_dir, because IV/OOV are determined by lexicon.
if [ ! -z $ext_lex ]; then
  datadir_ext=${datadir}_${ext_lex}
else
  datadir_ext=${datadir}
fi
if [ ! -f $datadir_ext/.done ]; then
  mkdir -p $datadir
  mkdir -p $datadir_ext
  for f in segments; do
    if [ ! -L $datadir_ext/../$dataset_id/$f ]; then
      ln -sf `readlink -f data/$dataset_id/$f` $datadir_ext/../$dataset_id/$f
    fi
    if [ ! -L $datadir_ext/$f ]; then
      ln -sf ../$dataset_id/$f $datadir_ext/$f
    fi
  done
fi
if [ ! -f $datadir_ext/kws_common/.done ]; then
  mkdir -p $datadir_ext/kws_common
  # Creates utterance id for each utterance.
  cat $datadir_ext/segments | \
    awk '{print $1}' | \
    sort | uniq | perl -e '
    $idx=1;
    while(<>) {
      chomp;
      print "$_ $idx\n";
      $idx++;
    }' > $datadir_ext/kws_common/utter_id

  # Map utterance to the names that will appear in the rttm file. You have 
  # to modify the commands below accoring to your rttm file
  cat $datadir_ext/segments | awk '{print $1" "$2}' |\
    sort | uniq > $datadir_ext/kws_common/utter_map;

  touch $datadir_ext/kws_common/.done
fi

./run-2c-concate-bnf-feats.sh --exp-concat-dir exp_${root_expsuffix} --bnf-nnet-list "`cat data${expsuffix}/bnf_nnet_list`" --dirid $type --append-fmllr $append_fmllr --fmllr-splice-width $fmllr_splice_width --bnf-input-feat-type "$bnf_input_feat_type"

if $data_only ; then
  echo "Exiting, as data-only was requested... "
fi

. ./czpScripts/clips/decode/functions.sh
if $skip_kws || ! $ive_kws; then
  ive_types=xxx # Arbitrarily set, to make 'for' loop execute only once
else
  ive_types=`get_ive_types $nbest_set $lambda_set`
fi

# Set suffix of decoding dir, indicating extra beams.
if [ ! -z $extra_beam ] && [ ! -z $extra_lattice_beam ]; then
  beam_suffix=-${extra_beam}_${extra_lattice_beam}
elif [ -z $extra_beam ] && [ ! -z $extra_lattice_beam ] || \
     [ ! -z $extra_beam ] && [ -z $extra_lattice_beam ]; then
  echo "ERROR: extra_beam and extra_lattice_beam should be set both or neither."
  exit 1;
else
  beam_suffix=
fi

# Backup beam settings in configuration file
conf_bnf_beam=$bnf_beam
conf_bnf_lat_beam=$bnf_lat_beam
conf_dnn_beam=$dnn_beam
conf_dnn_lat_beam=$dnn_lat_beam


# Get HCLG.fst size
fst_size=`du -sk exp/tri5/graph${ext}/HCLG.fst | cut -f 1` # in KB
if [ $fst_size -gt 600000 ]; then
  request_mem=$(($fst_size * 3))
  decode_cmd=`echo "$decode_cmd" | sed 's:ram_free.*$::'`"ram_free=${request_mem}K,mem_free=${request_mem}K"
  echo "FST HCLG is too large: $fst_size KB"
  echo "Reset decode_cmd to: $decode_cmd"
fi

####################################################################
## SGMM2 decoding 
####################################################################
if [ -f $exp_dir/sgmm7/.done ]; then
  echo "SGMM decoding Code is not ready"
  exit 1;
  decode=$exp_dir/sgmm7/decode_fmllr_${dirid}${ext}
  decode_base=$decode
  if [ ! -z $beam_suffix ]; then
    conf_beam=$conf_bnf_beam         # beam settings in conf file of this model
    conf_lat_beam=$conf_bnf_lat_beam # beam settings in conf file of this model
    . czpScripts/clips/decode/determine_decode_dir.sh
    bnf_beam=$extra_beam
    bnf_lat_beam=$extra_lattice_beam
  fi
  if [ ! -f $decode/.done ]; then
    echo ---------------------------------------------------------------------
    echo "Spawning $decode on" `date`
    echo ---------------------------------------------------------------------
    utils/mkgraph.sh \
      data/lang${ext} $exp_dir/sgmm7 $exp_dir/sgmm7/graph${ext} |tee $exp_dir/sgmm7/mkgraph${ext}.log

    mkdir -p $decode
    steps/decode_sgmm2.sh --skip-scoring true --use-fmllr true --nj $my_nj \
      --beam $bnf_beam --lattice-beam $bnf_lat_beam \
      --acwt $bnf_decode_acwt \
      --cmd "$decode_cmd" --transform-dir $exp_dir/tri6/decode_${dirid}${ext} "${decode_extra_opts[@]}"\
      $exp_dir/sgmm7/graph${ext} ${datadir} $decode |tee $decode/decode.log
    touch $decode/.done
  fi

  if ! $fast_path ; then
    eval "(
    for ive_type in $ive_types ; do
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
        --ive-type \"\$ive_type\" \
        --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt \
        "${shadow_set_extra_opts[@]}" "${lmwt_bnf_extra_opts[@]}" \
        ${datadir} data/lang${ext} ${decode}
    done
    ) $bg_flag"
  fi

  ####################################################################
  ##
  ## SGMM_MMI rescoring
  ##
  ####################################################################

  old_decode=$decode
  old_decode_base=$decode_base
  for iter in 1      ; do
    # Decode SGMM+MMI (via rescoring).
    decode=$exp_dir/sgmm7_mmi_b0.1/decode_fmllr_${dirid}${ext}_it$iter
    if [ $old_decode_base != $old_decode ]; then
      decode=${decode}${beam_suffix}
    fi
    if [ ! -f $decode/.done ]; then
      mkdir -p $decode
      steps/decode_sgmm2_rescore.sh  --skip-scoring true \
        --cmd "$decode_cmd" --iter $iter --transform-dir $exp_dir/tri6/decode_${dirid}${ext} \
        data/lang${ext} ${datadir} $old_decode $decode | tee ${decode}/decode.log

      touch $decode/.done
    fi
  done

  #We are done -- all lattices has been generated. We have to
  #a)Run MBR decoding
  #b)Run KW search
  for iter in 1      ; do
    # Decode SGMM+MMI (via rescoring).
    decode=$exp_dir/sgmm7_mmi_b0.1/decode_fmllr_${dirid}${ext}_it$iter
    if [ $old_decode_base != $old_decode ]; then
      decode=${decode}${beam_suffix}
    fi
    eval "(
    for ive_type in $ive_types ; do
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
        --ive-type \"\$ive_type\" \
        --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt \
        "${shadow_set_extra_opts[@]}" "${lmwt_bnf_extra_opts[@]}" \
        ${datadir} data/lang${ext} ${decode}
    done
    ) $bg_flag"
  done
fi

suffixes=".no_lda.vector_mix .no_lda.full_conn .no_lda.scalar_mix"
for suffix in '' $suffixes; do
  if [ -f $exp_dir/tri7_nnet${suffix}/.done ]; then
  #    [[ ( ! $exp_dir/tri7_nnet/decode_${dirid}/.done -nt $datadir/.done)  || \
  #       (! $exp_dir/tri7_nnet/decode_${dirid}/.done -nt $exp_dir/tri7_nnet/.done ) ]]; then
    
    # Assuming tri6/graph${ext} has been built

    decode=$exp_dir/tri7_nnet${suffix}/decode_${dirid}${ext}
    if [ ! -z $beam_suffix ]; then
      conf_beam=$conf_dnn_beam         # beam settings in conf file of this model
      conf_lat_beam=$conf_dnn_lat_beam # beam settings in conf file of this model
      . czpScripts/clips/decode/determine_decode_dir.sh
      dnn_beam=$extra_beam
      dnn_lat_beam=$extra_lattice_beam
    fi
    if [ ! -f $decode/.done ]; then
      echo ---------------------------------------------------------------------
      echo "Decoding hybrid system on top of combined features on" `date`
      echo ---------------------------------------------------------------------

      mkdir -p $decode
      steps/nnet2/decode.sh --cmd "$decode_cmd" --nj $my_nj \
        --beam $dnn_beam --lattice-beam $dnn_lat_beam \
        --skip-scoring true "${decode_extra_opts[@]}" \
        --feat-type raw --minimize $minimize \
        exp/tri5/graph${ext} ${datadir} $decode | tee $decode/decode.log

      touch $decode/.done
    fi

    eval "(
    for ive_type in $ive_types ; do
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
        --ive-type \"\$ive_type\" \
        --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt \
        "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
        ${datadir} data/lang${ext} ${decode}
    done
    ) $bg_flag"
  fi
done

####################################################################
##
## LSTM decoding
##
####################################################################
  for d in lstm4f ; do
    mdldir=$exp_dir/$d
    if [ -f $mdldir/.done ]; then
      # decoding
      decode=$mdldir/decode_${dirid}${ext}
      if [ ! -z $beam_suffix ]; then
        conf_beam=$conf_lstm_beam         # beam settings in conf file of this model
        conf_lat_beam=$conf_lstm_lat_beam # beam settings in conf file of this model
        . czpScripts/clips/decode/determine_decode_dir.sh
        lstm_beam=$extra_beam
        lstm_lat_beam=$extra_lattice_beam
      fi
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet/decode.sh --nj $my_nj --cmd "$decode_cmd" --config conf/decode_lstm.config \
          --beam $lstm_beam --lattice-beam $lstm_lat_beam \
          --skip-scoring true "${decode_extra_opts[@]}" \
          $exp_dir/tri6/graph${ext} $datadir $decode | tee $decode/decode.log
        touch $decode/.done
      fi

      eval "(
      for ive_type in $ive_types; do
        czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
          --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
          --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
          --ive-type \"\$ive_type\" \
          --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
          --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
          "${shadow_set_extra_opts[@]}" "${lmwt_lstm_extra_opts[@]}" \
          ${datadir} data/lang${ext} $decode
      done
      ) $bg_flag"
    fi
  done
wait

[ -e $lockfile ] && rm $lockfile
echo "$0: Everything looking good...." 
exit 0
