#!/bin/bash

# This is not necessarily the top-level run.sh as it is in other directories.   see README.txt first.

set -e
set -o pipefail

[ ! -f ./lang.conf ] && echo 'Language configuration does not exist! Use the configurations in conf/lang/* as a startup' && exit 1
[ ! -f ./conf/common_vars.sh ] && echo 'the file conf/common_vars.sh does not exist!' && exit 1

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;

[ -f local.conf ] && . ./local.conf

dir=dev10h.pem

boost_silence_in_vad=1.0 # used for *.seg

# Systems for semisup data selection
sys_to_decode="" # " sgmm_mmi tri6_nnet_mpe cnn_dnn_smbr lstm " # sat is always needed decoding
sys_to_kws_stt=" "
if [ -z $final_mdl ]; then
  final_mdl=exp/dnn_scratch_6langFLPNN.raw_cont
fi
# For quick validation
#sys_to_kws_stt=" sat "

run_kws_stt_bg=true
# If true, scoring STT and KWS for multiple models will not block this script,
# which utilize CPU resources for next decoding when executing the
# time-consuming lattice-to-ctm.
# Available only when cmd is "queue.pl ..."

force_score=false # By default, eval data would not be scored due to lack of 
                  # references. If you really want to score, set it true.
                  # chenzp   Mar 2,2014

dev2shadow=dev10h.uem
eval2shadow=eval.uem

### For LM extension ##########
lm_only=false # Stop after ext LM is created.
ext= # suffix of various directories, indicating LM type.
merge_text=false # [true] use both train text and ext text; [false] use only ext text.
###############################
ext_pron=  # not implemented in ive4_kws.sh
           # using extended pronunciation seems to lead to worse performance
is_graphemic_lex=true # 

### For lexicon extension #####
do_ext_lexicon=true # ext for lexicon is the same as that for LM
merge_lexicon=true   # useful only when do_ext_lexicon is true
###############################

subword=false
ext_for_word_lm= # useful only when subword is true
ext_for_word_lex= # useful only when subword is true

### For LM mixture ############
ext_for_mix=
org_lm_lambda=
lm_dev=
lm_dev_for_mix=
###############################

### For extra beam decoding ###
extra_beam=
extra_lattice_beam=
###############################

kind=
data_only=false
tri5_only=false
final_epoch=1
multilang_test=false # This is for exploring effective multilingual training
cnn_test=true
lstm_test=false

skip_kws=true
skip_stt=false
skip_scoring=false
max_states=150000

subset_kws=true
basic_kws=false #      (default in run_kws_stt: false)
extra_kws=true
oov_kws=false
vocab_kws=false
tmp_kws_key=
tmp_kwlist=
ive_kws=false   # whether to do IV expansion

existing_proxy_fsts=
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

wip=0.5
shadow_set_extra_opts=( --wip $wip )

echo "$0 $@"

. utils/parse_options.sh

if [ $# -ne 0 ]; then
  echo "Usage: $(basename $0) --type (dev10h|dev2h|eval|shadow)"
  exit 1
fi

if [ ! -z "$ext" ]; then
  ext_suffix=_$ext
else
  ext_suffix=
fi

lockfile=.lock.decode${ext_suffix}-${ext_for_mix}.$dir
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

# If ext is not specified, force do_ext_lexicon to be false
if [ -z "$ext" ] && $do_ext_lexicon; then
  do_ext_lexicon=false
  echo "Warning: ext is empty, but you specify do_ext_lexicon as true, which is meaningless. It has been reset as false"
fi

dataset_segments=${dir##*.}
dataset_dir=data/$dir
dataset_fb_dir=data-fbank/$dir
dataset_id=$dir
dataset_type=${dir%%.*}
#By default, we want the script to accept how the dataset should be handled,
#i.e. of  what kind is the dataset
if [ -z ${kind} ] ; then
  if [ "$dataset_type" == "dev2h" ] || [ "$dataset_type" == "dev10h" ] || [ "$dataset_type" == "tun3h" ]; then
    dataset_kind=supervised
  elif [ "$dataset_type" == "shadow" ] ; then
    dataset_kind=shadow
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

# Has been moved (chenzp Mar 4,2014)
#if [ "$dataset_kind" == "unsupervised" ]; then
#  skip_scoring=true
#fi

#The $dataset_type value will be the dataset name without any extrension
eval my_data_dir=( "\${${dataset_type}_data_dir[@]}" )
eval my_data_list=( "\${${dataset_type}_data_list[@]}" )
eval my_ecf_file=\$${dataset_type}_ecf_file 
if [ -z $my_data_dir ]; then
  eval my_data_audio_dir=( "\${${dataset_type}_data_audio_dir[@]}" )
  # Multiple audio directories
  if [[ $my_data_audio_dir =~ : ]]; then
    first=true
    for d in `echo $my_data_audio_dir | sed 's/:/ /g'`; do
      if $first; then
        target_dir=$d
        first=false
      else
        cp -sn $d/* $target_dir/
      fi
    done
    my_data_audio_dir=$target_dir
  fi
  eval my_data_trans_dir=( "\${${dataset_type}_data_trans_dir[@]}" )
  if [ -z $my_data_trans_dir ]; then # for eval/unsup
    my_data_dir=`dirname $my_ecf_file`
  else
    my_data_dir=`dirname $my_data_trans_dir`
  fi
fi
if [ -z $my_data_list ]; then
  if [ -f $my_data_dir/${dataset_type}.list ]; then
    my_data_list=$my_data_dir/${dataset_type}.list
  elif [ ! -z $my_ecf_file ]; then
    grep -Po '(?<=audio_filename=")[^"]*(?=")' $my_ecf_file |sort -u > $my_data_dir/${dataset_type}.list
    my_data_list=$my_data_dir/${dataset_type}.list
  fi
fi
if [ -z $my_data_dir ] || [ -z $my_data_list ] ; then
  echo "Error: The dir you specified ($dataset_id) does not have existing config";
  exit 1
fi

#eval my_seg_file=\$${dataset_type}_seg_file
eval my_stm_file=\$${dataset_type}_stm_file
eval my_kwlist_file=\$${dataset_type}_kwlist_file 
eval my_rttm_file=\$${dataset_type}_rttm_file
eval my_nj=\$${dataset_type}_nj  #for shadow, this will be re-set when appropriate

my_subset_ecf=false
eval ind=\${${dataset_type}_subset_ecf+x}
if [ "$ind" == "x" ] ; then
  eval my_subset_ecf=\$${dataset_type}_subset_ecf
fi

declare -A my_more_kwlists
if $extra_kws; then 
  eval my_more_kwlist_keys="\${!${dataset_type}_more_kwlists[@]}"
  for key in $my_more_kwlist_keys  # make sure you include the quotes there
  do
    eval my_more_kwlist_val="\${${dataset_type}_more_kwlists[$key]}"
    my_more_kwlists["$key"]="${my_more_kwlist_val}"
  done
fi

if [ ! -z $tmp_kws_key ]; then
  my_more_kwlists["$tmp_kws_key"]=$tmp_kwlist
  extra_kws=true
fi

declare -A my_subset_kwlists
eval my_subset_kwlist_keys="\${!${dataset_type}_subset_kwlists[@]}"
for key in $my_subset_kwlist_keys  # make sure you include the quotes there
do
  eval my_subset_kwlist_val="\${${dataset_type}_subset_kwlists[$key]}"
  my_subset_kwlists["$key"]="${my_subset_kwlist_val}"
done

#Just a minor safety precaution to prevent using incorrect settings
#The dataset_* variables should be used.
set -e
set -o pipefail
#set -u # cause unbouded variables error (chenzp Mar 1,2014)
unset dir
unset kind

function make_plp {
  target=$1
  logdir=$2
  output=$3
  if $use_pitch; then
    steps/make_plp_pitch.sh --cmd "$decode_cmd" --nj $my_nj $target $logdir $output
  else
    steps/make_plp.sh --cmd "$decode_cmd" --nj $my_nj $target $logdir $output
  fi
  utils/fix_data_dir.sh $target
  steps/compute_cmvn_stats.sh $target $logdir $output
  utils/fix_data_dir.sh $target
}

function check_variables_are_set {
  for variable in $mandatory_variables ; do
    eval my_variable=\$${variable}
    if [ -z $my_variable ] ; then
      echo "Mandatory variable ${variable/my/$dataset_type} is not set! " \
           "You should probably set the variable in the config file "
      exit 1
    else
      echo "$variable=$my_variable"
    fi
  done

  if [ ! -z ${optional_variables+x} ] ; then
    for variable in $optional_variables ; do
      eval my_variable=\$${variable}
      echo "$variable=$my_variable"
    done
  fi
}

. ./czpScripts/clips/decode/functions.sh

if [ ! -f data/raw_${dataset_type}_data/.done ]; then
echo ---------------------------------------------------------------------
echo "Subsetting the ${dataset_type} set"
echo ---------------------------------------------------------------------

l1=${#my_data_dir[*]}
l2=${#my_data_list[*]}
if [ "$l1" -ne "$l2" ]; then
  echo "Error, the number of source files lists is not the same as the number of source dirs!"
  exit 1
fi

resource_string=""
if [ "$dataset_kind" == "unsupervised" ]; then
  resource_string+=" --ignore-missing-txt true"
fi

for i in `seq 0 $(($l1 - 1))`; do
  resource_string+=" ${my_data_dir[$i]} "
  resource_string+=" ${my_data_list[$i]} "
done
local/make_corpus_subset.sh $resource_string ./data/raw_${dataset_type}_data
touch data/raw_${dataset_type}_data/.done
fi
my_data_dir=`readlink -f ./data/raw_${dataset_type}_data`
[ -f $my_data_dir/filelist.list ] && my_data_list=$my_data_dir/filelist.list
nj_max=`cat $my_data_list | wc -l` || nj_max=`ls $my_data_dir/audio | wc -l`

if [ "$nj_max" -lt "$my_nj" ] ; then
echo "Number of jobs ($my_nj) is too big!"
echo "The maximum reasonable number of jobs is $nj_max"
my_nj=$nj_max
fi

if $subword; then
  kws_prep_suffix=_subword
  do_ext_lexicon=true
  merge_lexicon=false
  echo "Force setting do_ext_lexicon to TRUE and merge_lexicon to FALSE because if specify subword as TRUE"
fi
#####################################################################
#
# Audio data directory preparation
#
#####################################################################
echo ---------------------------------------------------------------------
echo "Preparing ${dataset_kind} data files in ${dataset_dir} on" `date`
echo ---------------------------------------------------------------------
if [ ! -f  $dataset_dir/.done ] ; then
if [ "$dataset_kind" == "supervised" ]; then
  if [ "$dataset_segments" == "seg" ]; then
    . ./local/datasets/supervised_seg${kws_prep_suffix}.chenzp.sh
  elif [ "$dataset_segments" == "uem" ]; then
    . ./local/datasets/supervised_uem.sh
  elif [ "$dataset_segments" == "man" ] ; then
    . ./local/datasets/supervised_man.chenzp.sh
  elif [ "$dataset_segments" == "pem" ]; then
    . ./local/datasets/supervised_pem.chenzp.sh
  else
    echo "Unknown type of the dataset: \"$dataset_segments\"!";
    echo "Valid dataset types are: seg, uem, pem";
    exit 1
  fi
elif [ "$dataset_kind" == "unsupervised" ] ; then
  if [ "$dataset_segments" == "seg" ] ; then
    . ./local/datasets/unsupervised_seg${kws_prep_suffi}.chenzp.sh 
  elif [ "$dataset_segments" == "uem" ] ; then
    . ./local/datasets/unsupervised_uem.sh
  elif [ "$dataset_segments" == "man" ] ; then
    . ./local/datasets/unsupervised_man.chenzp.sh
  elif [ "$dataset_segments" == "pem" ] ; then
    ##This combination does not really makes sense,
    ##Because the PEM is that we get the segmentation 
    ##and because of the format of the segment files
    ##the transcript as well
    echo "ERROR: $dataset_segments combined with $dataset_type"
    echo "does not really make any sense!"
    exit 1
    #. ./local/datasets/unsupervised_pem.sh
  else
    echo "Unknown type of the dataset: \"$dataset_segments\"!";
    echo "Valid dataset types are: seg, uem, pem";
    exit 1
  fi
else
  echo "Unknown kind of the dataset: \"$dataset_kind\"!";
  echo "Valid dataset kinds are: supervised, unsupervised, shadow";
  exit 1
fi

if [ ! -f ${dataset_dir}/.plp.done ]; then
  echo ---------------------------------------------------------------------
  echo "Preparing ${dataset_kind} parametrization files in ${dataset_dir} on" `date`
  echo ---------------------------------------------------------------------
  make_plp ${dataset_dir} exp/make_plp/${dataset_id} plp
  touch ${dataset_dir}/.plp.done
fi
touch $dataset_dir/.done 
fi
if [ "$dataset_kind" == "unsupervised" ]; then
  if ! $force_score; then
      skip_scoring=true
  else
    echo ---------------------------------------------------------------------
    echo "Preparing ${dir} stm files in ${dataset_dir} on" `date`
    echo ---------------------------------------------------------------------
    if [ ! -z $my_stm_file ] ; then
      local/augment_original_stm.pl $my_stm_file ${dataset_dir}
    elif [[ $dataset_kind == shadow || $dataset_kind == eval ]]; then
      echo "Not doing anything for the STM file!"
    else
      local/prepare_stm.pl --fragmentMarkers \-\*\~ ${dataset_dir}
    fi
  fi
fi
                 #return non-zero return code
#set -u           #Fail on an undefined variable

# We will simply override the default G.fst by the G.fst generated using SRILM
if [ -z $lm_dev ]; then
  if $subword; then
    lm_dev=data/extra_text/dev_$ext
  else
    lm_dev=data/dev2h/text
  fi
  if [ ! -f $lm_dev ]; then
    if $subword; then
      echo "lm dev not exist: $lm_dev"
    else
      lm_dev=data/tun3h_noUnk/text
    fi
  fi
fi
if [ -z "$ext" ]; then
  lex_ext_suffix=
else
  lex_ext=${ext%%+*}
  lex_ext_suffix=${ext_suffix%%+*} # exts with the same lex_ext will share kwsdatadirs
fi
if [ ! -z "$ext" ]; then
  mkdir -p data/lang${ext_suffix}

  if $do_ext_lexicon; then
    if [[ ! -f data/lang${ext_suffix}/L.fst || data/lang${ext_suffix}/L.fst -ot data/local${lex_ext_suffix}/lexicon.txt ]]; then
      mkdir -p data/local${lex_ext_suffix}
      if [[ ! -f data/local${lex_ext_suffix}/lexicon.txt || data/local${lex_ext_suffix}/lexicon.txt -ot "$lexicon_file" ]]; then
        echo ---------------------------------------------------------------------
        echo "Preparing lexicon in data/local${lex_ext_suffix} on" `date`
        echo ---------------------------------------------------------------------
        #local/make_lexicon_subset.sh $train_data_dir/transcription $lexicon_file data/local/filtered_lexicon.txt  # no filtering
        if $merge_lexicon; then # merge original lexicon
            cp $lexicon_file data/local${lex_ext_suffix}/original_lexicon.txt
            czpScripts/local/merge_lexicon.pl data/local${lex_ext_suffix}/original_lexicon.txt data/extra_lexicon/${lex_ext} | sort > data/local${lex_ext_suffix}/merged_lexicon.txt
        else # only use ext lexicon
            cp data/extra_lexicon/${lex_ext} data/local${lex_ext_suffix}/merged_lexicon.txt
        fi
        local/prepare_lexicon.pl  --phonemap "$phoneme_mapping" \
          $lexiconFlags data/local${lex_ext_suffix}/merged_lexicon.txt data/local${lex_ext_suffix}
      fi
      echo ---------------------------------------------------------------------
      echo "Creating L.fst etc in data/lang${ext_suffix} on" `date`
      echo ---------------------------------------------------------------------
      utils/prepare_lang.sh \
        --share-silence-phones true \
        data/local${lex_ext_suffix} $oovSymbol data/local${lex_ext_suffix}/tmp.lang data/lang${ext_suffix}
    fi
  else  # use original lexicon
    if [[ ! -f data/lang${ext_suffix}/L.fst ]]; then
      cp -r data/lang/* data/lang${ext_suffix}/
      rm data/lang${ext_suffix}/G.fst
    fi
  fi

  if [[ ! -f data/srilm${ext_suffix}/lm.gz || data/srilm${ext_suffix}/lm.gz -ot data/extra_text/${ext} ]]; then
    echo ---------------------------------------------------------------------
    echo "Training SRILM language models for ${ext} on" `date`
    echo ---------------------------------------------------------------------
    mkdir -p data/srilm${ext_suffix}
    if $merge_text; then
      cat data/train/text <(sed 's/^/TMP_COL /' data/extra_text/${ext}) > data/srilm${ext_suffix}/raw_train_text
      echo "raw_train_text contains both data/train/text and data/extra_text/${ext}" \
        > data/srilm${ext_suffix}/note.txt
    else
      sed 's/^/TMP_COL /' data/extra_text/${ext} > data/srilm${ext_suffix}/raw_train_text
      echo "raw_train_text contains only data/extra_text/${ext}" \
        > data/srilm${ext_suffix}/note.txt
    fi
    local/train_lms_srilm.sh --dev-text $lm_dev --words-file data/lang${ext_suffix}/words.txt \
      --train-text data/srilm${ext_suffix}/raw_train_text data data/srilm${ext_suffix}
  fi
fi

# If we want to mix two LMs
if [ -z $lm_dev_for_mix ]; then
  lm_dev_for_mix=data/dev2h_noUnk/text
  if [ ! -f $lm_dev_for_mix ]; then
    lm_dev_for_mix=data/tun3h_noUnk/text
  fi
fi
if [ ! -z "$ext_for_mix" ]; then
  # In LM mixing, we simply use the lexicon of $ext
  # Set the base LM ext
  if [ -z "$ext" ]; then
    ext_base=
  else
    ext_base=${ext_suffix}
  fi
  if [[ ! -f data/srilm_${ext_for_mix}/lm.gz || data/srilm_${ext_for_mix}/lm.gz -ot data/extra_text/${ext_for_mix} ]]; then
    echo ---------------------------------------------------------------------
    echo "Training SRILM language models for ${ext_for_mix} (for mixture) on" `date`
    echo ---------------------------------------------------------------------
    local/train_lms_srilm.sh --dev-text $lm_dev_for_mix --words-file data/lang${ext_base}/words.txt \
      --train-text data/extra_text/${ext_for_mix} data data/srilm_${ext_for_mix}
  else
    # TODO If the lexicon in existing ext_for_mix LM is different from the base one, can we do mixing ?
    diff data/srilm${ext_base}/vocab data/srilm_${ext_for_mix}/vocab >/dev/null || (echo "Two lexicon differs" && exit 1)
  fi
  new_ext=${ext}-${ext_for_mix}-${org_lm_lambda}
  if [[ ! -f data/srilm_${new_ext}/lm.gz || data/srilm_${new_ext}/lm.gz -ot data/srilm${ext_base}/lm.gz || data/srilm_${new_ext}/lm.gz -ot data/srilm_${ext_for_mix}/lm.gz ]]; then
    echo ---------------------------------------------------------------------
    echo "Mix SRILM language models: ${ext_for_mix} and ${ext} on" `date`
    echo ---------------------------------------------------------------------
    local/mix_lms_srilm.chenzp.sh --lambda ${org_lm_lambda} --dev-text $lm_dev \
      data/srilm${ext_base}/lm.gz data/srilm_${ext_for_mix}/lm.gz \
      data/srilm_${new_ext}
      cp data/srilm${ext_base}/vocab data/srilm_${new_ext}/
      mkdir -p data/lang_${new_ext}
      cp -r data/lang${ext_base}/* data/lang_${new_ext}/
      [ -e data/lang_${new_ext}/G.fst ] && rm data/lang_${new_ext}/G.fst
  fi
  ext=$new_ext
fi

if $lm_only; then
  echo "Exit because lm_only=true"
  [ -e $lockfile ] && rm $lockfile
  exit 0;
fi

if [[ ! -f data/lang${ext_suffix}/G.fst || data/lang${ext_suffix}/G.fst -ot data/srilm${ext_suffix}/lm.gz ]]; then
  echo ---------------------------------------------------------------------
  echo "Creating G.fst for ${ext} on " `date`
  echo ---------------------------------------------------------------------
  local/arpa2G.sh data/srilm${ext_suffix}/lm.gz data/lang${ext_suffix} data/lang${ext_suffix}
fi

#####################################################################
#
# KWS data directory preparation
#
#####################################################################
echo ---------------------------------------------------------------------
echo "Preparing kws data files (for $ext) in ${dataset_dir}${ext_suffix} on" `date`
echo ---------------------------------------------------------------------
if ! $skip_kws; then
  base_dataset_dir=$dataset_dir
  if [ -z "$ext" ]; then
    lang_dir=data/lang
  else
    dataset_dir=${dataset_dir}${ext_suffix}
    lang_dir=data/lang${ext_suffix}
    # In lexicon/LM extension case, suffixes are needed somewhere...
    ext_lm_suffix=_$ext
    if $do_ext_lexicon; then
      ext_lex_suffix=_$ext
    else
      ext_lex_suffix=
    fi
    if $subword; then
      if [ ! -z "$ext_for_word_lm" ]; then
        ext_word_lm_suffix=_${ext_for_word_lm}
      else
        ext_word_lm_suffix=
      fi
      if [ ! -z "$ext_for_word_lex" ]; then
        ext_word_lex_suffix=_${ext_for_word_lex}
      else
        ext_word_lex_suffix=
      fi
    fi
    if $subword; then
      #w2sfile="data/local${lex_ext_suffix}/filtered_lexicon.w2s.txt"
      w2sfile="exp/${ext}_gen/lexicon.w2s.txt"
      if [ ! -f $w2sfile ]; then
        if [ ! -z $ext ]; then
          w2sfile="data/extra_w2s/${ext%%.*}"
        else
          echo "ERROR $w2sfile not exist and ext is empty"
          exit 1;
        fi
      fi
      if [ ! -f $w2sfile ]; then
        echo "ERROR $w2sfile not exist"
        exit 1;
      fi
    fi
    # Prepare another dataset_dir, because IV/OOV are determined by lexicon.
    if [ ! -f $dataset_dir/.done ]; then
      if $do_ext_lexicon; then
        mkdir -p ${base_dataset_dir}${lex_ext_suffix}
        if [ ${base_dataset_dir}${lex_ext_suffix} != $dataset_dir ]; then
          ln -s `basename ${base_dataset_dir}${lex_ext_suffix}` $dataset_dir
        fi
        pushd $dataset_dir
        for f in segments reco2file_and_channel; do  # reco2file_and_channel is used in system combination
          ln -sf ../$dataset_id/$f $f
        done
        popd
        touch $dataset_dir/.done
      else
        pushd data
        ln -s `basename $base_dataset_dir` `basename $dataset_dir`
        popd
      fi
    fi
  fi
  if  $basic_kws; then
    . ./local/datasets/basic_kws${kws_prep_suffix}.chenzp.sh
  fi
  if  $extra_kws; then 
    . ./local/datasets/extra_kws${kws_prep_suffix}.chenzp.sh
  fi
  if  $vocab_kws; then 
    . ./local/datasets/vocab_kws${kws_prep_suffix}.chenzp.sh
  fi
  if  $ive_kws; then 
   #  . ./local/datasets/ive_kws.chenzp.sh
   # . ./local/datasets/ive2_kws.chenzp.sh
   # . ./local/datasets/ive3_kws.chenzp.sh
     for nbest in `echo "$nbest_set" | sed 's: \+:\n:g'`; do
       for lambda in `echo "$lambda_set" | sed 's: \+:\n:g'`; do
        . ./local/datasets/ive4_kws${kws_prep_suffix}.chenzp.sh
       done
     done
  fi
  if [ ${#my_subset_kwlists[@]} -ne 0  ] ; then
    touch $dataset_dir/subset_kws_tasks
    mkdir -p $dataset_dir/subsets
    for subsetid in "${!my_subset_kwlists[@]}" ; do
      [ -f $dataset_dir/.done.kws.subset.$subsetid ] && continue;
      kwlist=${my_subset_kwlists[$subsetid]}
      echo $subsetid >> $dataset_dir/subset_kws_tasks
      cp $kwlist $dataset_dir/subsets/$subsetid.xml
      touch $dataset_dir/.done.kws.subset.$subsetid
    done
  fi
  if [ ! -f $dataset_dir/kws_common/.done ]; then
    mkdir -p $dataset_dir/kws_common
    # Creates utterance id for each utterance.
    cat $dataset_dir/segments | \
      awk '{print $1}' | \
      sort | uniq | perl -e '
      $idx=1;
      while(<>) {
        chomp;
        print "$_ $idx\n";
        $idx++;
      }' > $dataset_dir/kws_common/utter_id

    # Map utterance to the names that will appear in the rttm file. You have 
    # to modify the commands below accoring to your rttm file
    cat $dataset_dir/segments | awk '{print $1" "$2}' |\
      sort | uniq > $dataset_dir/kws_common/utter_map;

    touch $dataset_dir/kws_common/.done
  fi
  dataset_dir=$base_dataset_dir
fi

if $skip_kws || ! $ive_kws; then
  ive_types=xxx # Arbitrarily set, to make 'for' loop execute only once
else
  ive_types=`get_ive_types "$nbest_set" "$lambda_set"`
  echo "IVE types: $ive_types"
fi

if $data_only ; then
  echo "Exiting, as data-only was requested..."
  [ -e $lockfile ] && rm $lockfile
  exit 0;
fi

if [ ! -z "$ext" ] && [ `diff data/lang/words.txt data/lang${ext_suffix}/words.txt | wc -l` -gt 0 ]; then # if lex are extended
  ext_lex=${ext}
else
  ext_lex=
fi

# Fix sys_to_decode, all systems in sys_to_kws_stt should be in sys_to_decode
for s in $sys_to_kws_stt; do
  if [[ ! "$sys_to_decode" =~ " $s " ]]; then
    sys_to_decode="$sys_to_decode $s "
  fi
done

echo "Systems to be decoded: $sys_to_decode"
echo "Systems to run kws and stt: $sys_to_kws_stt"

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
conf_sat_beam=$sat_beam
conf_sat_lat_beam=$sat_lat_beam
conf_dnn_beam=$dnn_beam
conf_dnn_lat_beam=$dnn_lat_beam
conf_sgmm_beam=$sgmm_beam
conf_sgmm_lat_beam=$sgmm_lat_beam
conf_cnn_beam=$cnn_beam
conf_cnn_lat_beam=$cnn_lat_beam
conf_lstm_beam=$lstm_beam
conf_lstm_lat_beam=$lstm_lat_beam

# Building graph in tri5
if [ ! -f exp/tri5/graph${ext_suffix}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Building FST graph in tri5  on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang${ext_suffix} exp/tri5 exp/tri5/graph${ext_suffix} |tee exp/tri5/mkgraph${ext_suffix}.log
  touch exp/tri5/graph${ext_suffix}/.done
fi

# Get HCLG.fst size
fst_size=`du -sk exp/tri5/graph${ext_suffix}/HCLG.fst | cut -f 1` # in KB
if [ $fst_size -gt 600000 ]; then
  request_mem=$(($fst_size * 3))
  decode_cmd=`echo "$decode_cmd" | sed 's:ram_free.*$::'`"ram_free=${request_mem}K,mem_free=${request_mem}K"
  echo "FST HCLG is too large: $fst_size KB"
  echo "Reset decode_cmd to: $decode_cmd"
fi

####################################################################
##
## FMLLR decoding 
##
####################################################################
decode=exp/tri5/decode_${dataset_id}${ext_suffix}
if [ ! -z $beam_suffix ]; then
  conf_beam=$conf_sat_beam         # beam settings in conf file of this model
  conf_lat_beam=$conf_sat_lat_beam # beam settings in conf file of this model
  . czpScripts/clips/decode/determine_decode_dir.sh
  sat_beam=$extra_beam
  sat_lat_beam=$extra_lattice_beam
fi

if [ ! -f ${decode}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning decoding with SAT models  on" `date`
  echo ---------------------------------------------------------------------
  mkdir -p $decode
  #By default, we do not care about the lattices for this step -- we just want the transforms
  #Therefore, we will reduce the beam sizes, to reduce the decoding times
  steps/decode_fmllr_extra.sh --skip-scoring true --beam $sat_beam --lattice-beam $sat_lat_beam \
    --nj $my_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
    exp/tri5/graph${ext_suffix} ${dataset_dir} ${decode} |tee ${decode}/decode.log
  touch ${decode}/.done
fi
if [[ "$sys_to_kws_stt" =~ " sat " ]] || [[ "$sys_to_kws_stt" =~ " exp/tri5 " ]]; then
  eval "(
    czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
      --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
      --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
      --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
      --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
      "${shadow_set_extra_opts[@]}" "${lmwt_sat_extra_opts[@]}" \
      ${dataset_dir} data/lang${ext_suffix}  ${decode}
  ) $bg_flag"
fi
if $tri5_only; then
    wait
    [ -e $lockfile ] && rm $lockfile
    echo "Exit after tri5 decoding, as requested."
    exit 0;
fi


####################################################################
## SGMM2 decoding 
## We Include the SGMM_MMI inside this, as we might only have the DNN systems
## trained and not PLP system. The DNN systems build only on the top of tri5 stage
####################################################################
if [[ "$sys_to_decode" =~ " sgmm_mmi " ]] || [[ "$sys_to_decode" =~ " sgmm " ]] \
   || [[ "$sys_to_decode" =~ " exp/sgmm5 " ]] || [[ "$sys_to_decode" =~ " exp/sgmm5_mmi_b0.1 " ]]; then
  if [ -f exp/sgmm5/.done ]; then
    decode=exp/sgmm5/decode_fmllr_${dataset_id}${ext_suffix}
    decode_base=$decode
    if [ ! -z $beam_suffix ]; then
      conf_beam=$conf_sgmm_beam         # beam settings in conf file of this model
      conf_lat_beam=$conf_sgmm_lat_beam # beam settings in conf file of this model
      . czpScripts/clips/decode/determine_decode_dir.sh
      sgmm_beam=$extra_beam
      sgmm_lat_beam=$extra_lattice_beam
    fi
    if [ ! -f $decode/.done ]; then
      echo ---------------------------------------------------------------------
      echo "Spawning $decode on" `date`
      echo ---------------------------------------------------------------------
      utils/mkgraph.sh \
        data/lang${ext_suffix} exp/sgmm5 exp/sgmm5/graph${ext_suffix} |tee exp/sgmm5/mkgraph${ext_suffix}.log

      mkdir -p $decode
      steps/decode_sgmm2.sh --skip-scoring true --use-fmllr true --nj $my_nj \
        --beam $sgmm_beam --lattice-beam $sgmm_lat_beam \
        --cmd "$decode_cmd" --transform-dir exp/tri5/decode_${dataset_id}${ext_suffix} "${decode_extra_opts[@]}"\
        exp/sgmm5/graph${ext_suffix} ${dataset_dir} $decode |tee $decode/decode.log
      touch $decode/.done
    fi
    
    if [[ "$sys_to_kws_stt" =~ " sgmm " ]] || [[ "$sys_to_kws_stt" =~ " exp/sgmm5 " ]]; then
      eval "(
        for ive_type in $ive_types ; do
          czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
            --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
            --ive-type \"\$ive_type\" \
            --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
            --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
            --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
            "${shadow_set_extra_opts[@]}" "${lmwt_sgmm_extra_opts[@]}" \
            ${dataset_dir} data/lang${ext_suffix}  ${decode}
        done
          ) $bg_flag"
    fi

    if [[ "$sys_to_decode" =~ " sgmm_mmi " ]] || [[ "$sys_to_decode" =~ " exp/sgmm5_mmi_b0.1 " ]]; then
      ####################################################################
      ##
      ## SGMM_MMI rescoring
      ##
      ####################################################################

      old_decode=$decode
      old_decode_base=$decode_base
      for iter in 1; do
        # Decode SGMM+MMI (via rescoring).
        decode=exp/sgmm5_mmi_b0.1/decode_fmllr_${dataset_id}${ext_suffix}_it$iter
        if [ $old_decode_base != $old_decode ]; then
          decode=${decode}${beam_suffix}
        fi
        if [ ! -f $decode/.done ]; then
          mkdir -p $decode
          steps/decode_sgmm2_rescore.sh  --skip-scoring true \
            --cmd "$decode_cmd" --iter $iter --transform-dir exp/tri5/decode_${dataset_id}${ext_suffix} \
            data/lang${ext_suffix} ${dataset_dir} $old_decode $decode | tee ${decode}/decode.log

          touch $decode/.done
        fi
      done

      if [[ "$sys_to_kws_stt" =~ " sgmm_mmi " ]] || [[ "$sys_to_kws_stt" =~ " exp/sgmm5_mmi_b0.1 " ]]; then
        #We are done -- all lattices has been generated. We have to
        #a)Run MBR decoding
        #b)Run KW search
        for iter in 1; do
          # Decode SGMM+MMI (via rescoring).
          decode=exp/sgmm5_mmi_b0.1/decode_fmllr_${dataset_id}${ext_suffix}_it$iter
          if [ $old_decode_base != $old_decode ]; then
            decode=${decode}${beam_suffix}
          fi
          eval "(
          czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
            --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
            --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
            --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
            --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
            "${shadow_set_extra_opts[@]}" "${lmwt_sgmm_extra_opts[@]}" \
            ${dataset_dir} data/lang${ext_suffix} $decode
          ) $bg_flag"
        done
      fi
    fi
  fi
fi

sgmmdirs='' # TODO multilang SGMM training has bug, don't decode!!!
for sgmmdir in $sgmmdirs; do
  if [ -f exp/$sgmmdir/sgmm5/.done.ml ]; then
    decode=exp/$sgmmdir/sgmm5/0/decode_fmllr_${dataset_id}${ext_suffix}
    decode_base=$decode
    if [ ! -z $beam_suffix ]; then
      conf_beam=$conf_sgmm_beam         # beam settings in conf file of this model
      conf_lat_beam=$conf_sgmm_lat_beam # beam settings in conf file of this model
      . czpScripts/clips/decode/determine_decode_dir.sh
      sgmm_beam=$extra_beam
      sgmm_lat_beam=$extra_lattice_beam
    fi
    if [ ! -f $decode/.done ]; then
      echo ---------------------------------------------------------------------
      echo "Multilang SGMM decoding $decode on" `date`
      echo ---------------------------------------------------------------------
      utils/mkgraph.sh \
        data/lang${ext_suffix} exp/$sgmmdir/sgmm5/0 exp/$sgmmdir/sgmm5/0/graph${ext_suffix} |tee exp/$sgmmdir/sgmm5/0/mkgraph${ext_suffix}.log

      mkdir -p $decode
      czpScripts/steps/decode_sgmm2.chenzp.sh --skip-scoring true --use-fmllr true --nj $my_nj \
        --beam $sgmm_beam --lattice-beam $sgmm_lat_beam \
        --no-spk true \
        --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
        exp/$sgmmdir/sgmm5/0/graph${ext_suffix} ${dataset_dir} $decode |tee $decode/decode.log
      #--transform-dir exp/tri5/decode_${dataset_id}${ext_suffix}
      touch $decode/.done
    fi

    eval "(
    czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
      --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
      --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
      --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
      --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
      "${shadow_set_extra_opts[@]}" "${lmwt_sgmm_extra_opts[@]}" \
      ${dataset_dir} data/lang${ext_suffix}  ${decode}
    ) $bg_flag"
  fi
done

####################################################################
##
## DNN ("compatibility") decoding -- also, just decode the "default" net
##
####################################################################
tri6_nnet_suffixes="_3hid"
for tri6_nnet_suffix in '' $tri6_nnet_suffixes; do
if [[ "$sys_to_decode" =~ " tri6_nnet${tri6_nnet_suffix} " ]] || [[ "$sys_to_decode" =~ " exp/tri6_nnet${tri6_nnet_suffix} " ]]; then
  if [ `basename $(readlink -f exp/tri6_nnet${tri6_nnet_suffix})` != "tri6b_nnet" ] \
     && [ -f exp/tri6_nnet${tri6_nnet_suffix}/.done ]; then
    decode=exp/tri6_nnet${tri6_nnet_suffix}/decode_${dataset_id}${ext_suffix}
    if [ ! -z $beam_suffix ]; then
      conf_beam=$conf_dnn_beam         # beam settings in conf file of this model
      conf_lat_beam=$conf_dnn_lat_beam # beam settings in conf file of this model
      . czpScripts/clips/decode/determine_decode_dir.sh
      dnn_beam=$extra_beam
      dnn_lat_beam=$extra_lattice_beam
    fi
    if [ ! -f $decode/.done ]; then
      mkdir -p $decode
      steps/nnet2/decode.sh \
        --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
        --beam $dnn_beam --lattice-beam $dnn_lat_beam \
        --skip-scoring true "${decode_extra_opts[@]}" \
        --transform-dir exp/tri5/decode_${dataset_id}${ext_suffix} \
        exp/tri5/graph${ext_suffix} ${dataset_dir} $decode | tee $decode/decode.log

      touch $decode/.done
    fi
    if [[ "$sys_to_kws_stt" =~ " tri6_nnet${tri6_nnet_suffix} " ]] || [[ "$sys_to_kws_stt" =~ " exp/tri6_nnet${tri6_nnet_suffix} " ]]; then
      eval "(
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
        --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
        "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
        ${dataset_dir} data/lang${ext_suffix} $decode
      ) $bg_flag"
    fi
  fi
fi
done

####################################################################
##
## DNN ("compatibility") decoding -- also, just decode the "default" net
##
####################################################################
tri6_nnet_raw_suffixes=
for tri6_nnet_suffix in '' $tri6_nnet_raw_suffixes; do
if [[ "$sys_to_decode" =~ " tri6_nnet.raw${tri6_nnet_suffix} " ]] || [[ "$sys_to_decode" =~ " exp/tri6_nnet.raw${tri6_nnet_suffix} " ]]; then
  if [ -f exp/tri6_nnet.raw${tri6_nnet_suffix}/.done ]; then
    decode=exp/tri6_nnet.raw${tri6_nnet_suffix}/decode_${dataset_id}${ext_suffix}
    if [ ! -z $beam_suffix ]; then
      conf_beam=$conf_dnn_beam         # beam settings in conf file of this model
      conf_lat_beam=$conf_dnn_lat_beam # beam settings in conf file of this model
      . czpScripts/clips/decode/determine_decode_dir.sh
      dnn_beam=$extra_beam
      dnn_lat_beam=$extra_lattice_beam
    fi
    if [ ! -f $decode/.done ]; then
      mkdir -p $decode
      steps/nnet2/decode.sh \
        --feat-type raw \
        --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
        --beam $dnn_beam --lattice-beam $dnn_lat_beam \
        --skip-scoring true "${decode_extra_opts[@]}" \
        exp/tri5/graph${ext_suffix} ${dataset_dir} $decode | tee $decode/decode.log

      touch $decode/.done
    fi
    if [[ "$sys_to_kws_stt" =~ " tri6_nnet.raw${tri6_nnet_suffix} " ]] || [[ "$sys_to_kws_stt" =~ " exp/tri6_nnet.raw${tri6_nnet_suffix} " ]]; then
      eval "(
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
        --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
        "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
        ${dataset_dir} data/lang${ext_suffix} $decode
      ) $bg_flag"
    fi
  fi
fi
done

####################################################################
##
## DNN ("Multi-lang", CE) final tuning (*_cont) decoding (RAW feature)
##
####################################################################
if [[ "$sys_to_decode" =~ " ml_dnn " ]]; then
  suffixes='scratch_101LLP__tri6_nnet.raw_5hid.no_lda_cont scratch_104LLP__tri6_nnet.raw_5hid.no_lda_cont scratch_105LLP__tri6_nnet.raw_5hid.no_lda_cont scratch_106LLP__tri6_nnet.raw_5hid.no_lda_cont scratch_107LLP__tri6_nnet.raw_5hid.no_lda_cont scratch_204LLP__tri6_nnet.raw_5hid.no_lda_cont scratch_4lang10hr_5hid.raw_cont'
  if $multilang_test; then 
    suffixes="$suffixes "
  fi
  for suffix in $suffixes; do
    if [ -f exp/dnn_${suffix}/.done ]; then
      decode=exp/dnn_${suffix}/decode_${dataset_id}${ext_suffix}
      if [ ! -z $beam_suffix ]; then
        conf_beam=$conf_dnn_beam         # beam settings in conf file of this model
        conf_lat_beam=$conf_dnn_lat_beam # beam settings in conf file of this model
        . czpScripts/clips/decode/determine_decode_dir.sh
        dnn_beam=$extra_beam
        dnn_lat_beam=$extra_lattice_beam
      fi
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet2/decode.sh --feat-type raw \
          --beam $dnn_beam --lattice-beam $dnn_lat_beam \
          --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
          --skip-scoring true "${decode_extra_opts[@]}" \
          exp/tri5/graph${ext_suffix} ${dataset_dir} $decode | tee $decode/decode.log

        touch $decode/.done
      fi
      
      if [[ "$sys_to_kws_stt" =~ " ml_dnn " ]]; then
        eval "(
        for ive_type in $ive_types ; do
          czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
            --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
            --ive-type \"\$ive_type\" \
            --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
            --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
            --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
            "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
            ${dataset_dir} data/lang${ext_suffix} $decode
        done
        ) $bg_flag"
      fi
    fi
  done
fi

####################################################################
##
## DNN (ensemble) decoding
##
####################################################################
if [[ "$sys_to_decode" =~ " tri6b_nnet " ]] || [[ "$sys_to_decode" =~ " exp/tri6b_nnet " ]]; then
  if [ -f exp/tri6b_nnet/.done ]; then
    decode=exp/tri6b_nnet/decode_${dataset_id}${ext_suffix}
    if [ ! -z $beam_suffix ]; then
      conf_beam=$conf_dnn_beam         # beam settings in conf file of this model
      conf_lat_beam=$conf_dnn_lat_beam # beam settings in conf file of this model
      . czpScripts/clips/decode/determine_decode_dir.sh
      dnn_beam=$extra_beam
      dnn_lat_beam=$extra_lattice_beam
    fi
    if [ ! -f $decode/.done ]; then
      mkdir -p $decode
      steps/nnet2/decode.sh \
        --minimize $minimize --cmd "$decode_cmd" --nj $my_nj \
        --beam $dnn_beam --lattice-beam $dnn_lat_beam \
        --skip-scoring true "${decode_extra_opts[@]}" \
        --transform-dir exp/tri5/decode_${dataset_id}${ext_suffix} \
        exp/tri5/graph${ext_suffix} ${dataset_dir} $decode | tee $decode/decode.log

      touch $decode/.done
    fi

    if [[ "$sys_to_kws_stt" =~ " tri6b_nnet " ]] || [[ "$sys_to_kws_stt" =~ " exp/tri6b_nnet " ]]; then
      eval "(
      czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
        --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
        --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
        --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
        --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
        "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
        ${dataset_dir} data/lang${ext_suffix} $decode
      ) $bg_flag"
    fi
  fi
fi

if [[ "$sys_to_decode" =~ "cnn" ]] || [[ "$sys_to_decode" =~ "exp/cnn4c" ]]; then
  # Extract filter-bank features for CNN
  if [ ! -f $dataset_fb_dir/.fbank.done ]; then
    # Test set
    mkdir -p $dataset_fb_dir && cp $dataset_dir/* $dataset_fb_dir && rm $dataset_fb_dir/{feats,cmvn}.scp
    steps/make_fbank_pitch.sh --nj $my_nj --cmd "$train_cmd" \
       $dataset_fb_dir $dataset_fb_dir/log $dataset_fb_dir/data || exit 1;
    steps/compute_cmvn_stats.sh $dataset_fb_dir $dataset_fb_dir/log $dataset_fb_dir/data || exit 1;
    touch $dataset_fb_dir/.fbank.done
  fi
fi

####################################################################
##
## CNN decoding
##
####################################################################
if [[ "$sys_to_decode" =~ " cnn " ]] || [[ "$sys_to_decode" =~ " exp/cnn4c " ]]; then
  mdldir=exp/cnn4c
  if [ -f $mdldir/.done ]; then
    # decoding
    decode=$mdldir/decode_${dataset_id}${ext_suffix}
    if [ ! -z $beam_suffix ]; then
      conf_beam=$conf_cnn_beam         # beam settings in conf file of this model
      conf_lat_beam=$conf_cnn_lat_beam # beam settings in conf file of this model
      . czpScripts/clips/decode/determine_decode_dir.sh
      cnn_beam=$extra_beam
      cnn_lat_beam=$extra_lattice_beam
    fi
    if [ ! -f $decode/.done ]; then
      mkdir -p $decode
      steps/nnet/decode.sh --nj $my_nj --cmd "$decode_cmd" \
        --beam $cnn_beam --lattice-beam $cnn_lat_beam \
        --skip-scoring true "${decode_extra_opts[@]}" \
        exp/tri5/graph${ext_suffix} $dataset_fb_dir $decode | tee $decode/decode.log
      touch $decode/.done
    fi

    if [[ "$sys_to_kws_stt" =~ " cnn " ]] || [[ "$sys_to_kws_stt" =~ " exp/cnn4c " ]]; then
      eval "(
      for ive_type in $ive_types ; do
        czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
          --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
          --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
          --ive-type \"\$ive_type\" \
          --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
          --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
          "${shadow_set_extra_opts[@]}" "${lmwt_cnn_extra_opts[@]}" \
          ${dataset_dir} data/lang${ext_suffix} $decode
      done
      ) $bg_flag"
    fi
  fi
fi

####################################################################
##
## CNN RBM-DNN decoding
##
####################################################################
if [[ "$sys_to_decode" =~ " cnn_dnn " ]] || [[ "$sys_to_decode" =~ " exp/cnn4c_pretrain-dbn_dnn " ]]; then
  mdldir=exp/cnn4c_pretrain-dbn_dnn
  if [ -f $mdldir/.done ]; then
    decode=$mdldir/decode_${dataset_id}${ext_suffix}
    if [ ! -z $beam_suffix ]; then
      conf_beam=$conf_cnn_beam         # beam settings in conf file of this model
      conf_lat_beam=$conf_cnn_lat_beam # beam settings in conf file of this model
      . czpScripts/clips/decode/determine_decode_dir.sh
      cnn_beam=$extra_beam
      cnn_lat_beam=$extra_lattice_beam
    fi
    if [ ! -f $decode/.done ]; then
      mkdir -p $decode
      steps/nnet/decode.sh --nj $my_nj --cmd "$decode_cmd" \
        --beam $cnn_beam --lattice-beam $cnn_lat_beam \
        --skip-scoring true "${decode_extra_opts[@]}" \
        exp/tri5/graph${ext_suffix} $dataset_fb_dir $decode | tee $decode/decode.log
      touch $decode/.done
    fi
    if [[ "$sys_to_kws_stt" =~ " cnn_dnn " ]] || [[ "$sys_to_kws_stt" =~ " exp/cnn4c_pretrain-dbn_dnn " ]]; then
      eval "(
      for ive_type in $ive_types; do
        czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
          --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
          --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
          --ive-type \"\$ive_type\" \
          --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
          --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
          "${shadow_set_extra_opts[@]}" "${lmwt_cnn_extra_opts[@]}" \
          ${dataset_dir} data/lang${ext_suffix} $decode
      done
      ) $bg_flag"
    fi
  fi
fi

####################################################################
##
## CNN_MPE decoding
##
####################################################################
if [[ "$sys_to_decode" =~ " cnn_dnn_smbr " ]] || [[ "$sys_to_decode" =~ " exp/cnn4c_pretrain-dbn_dnn_smbr " ]]; then
  mdldir=exp/cnn4c_pretrain-dbn_dnn_smbr
  if [ -f $mdldir/.done ]; then
    for iter in 2; do
      decode=$mdldir/decode_${dataset_id}${ext_suffix}_it$iter
      if [ ! -z $beam_suffix ]; then
        conf_beam=$conf_cnn_beam         # beam settings in conf file of this model
        conf_lat_beam=$conf_cnn_lat_beam # beam settings in conf file of this model
        . czpScripts/clips/decode/determine_decode_dir.sh
        cnn_beam=$extra_beam
        cnn_lat_beam=$extra_lattice_beam
      fi
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        # Note: in CNN recipe, "--acwt 0.2", here we use default 0.1 and see what happened. (chenzp, Jan 23,2015)
        steps/nnet/decode.sh --nj $my_nj --cmd "$decode_cmd" \
          --beam $cnn_beam --lattice-beam $cnn_lat_beam \
          --nnet $mdldir/${iter}.nnet \
          --skip-scoring true "${decode_extra_opts[@]}" \
          exp/tri5/graph${ext_suffix} $dataset_fb_dir $decode | tee $decode/decode.log
        touch $decode/.done
      fi

      if [[ "$sys_to_kws_stt" =~ " cnn_dnn_smbr " ]] || [[ "$sys_to_kws_stt" =~ " exp/cnn4c_pretrain-dbn_dnn_smbr " ]]; then
        eval "(
        for ive_type in $ive_types; do
          czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
            --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
            --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
            --ive-type \"\$ive_type\" \
            --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
            --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
            "${shadow_set_extra_opts[@]}" "${lmwt_cnn_extra_opts[@]}" \
            ${dataset_dir} data/lang${ext_suffix} $decode
        done
        ) $bg_flag"
      fi
    done
  fi
fi


####################################################################
##
## LSTM decoding
##
####################################################################
if [[ "$sys_to_decode" =~ " lstm " ]] || [[ "$sys_to_decode" =~ " exp/lstm4f " ]]; then
  for d in lstm4f ; do
    mdldir=exp/$d
    if [ -f $mdldir/.done ]; then
      # Extract filter-bank features for LSTM
      if [ ! -f $dataset_fb_dir/.fbank.done ]; then
        # Dev set
        utils/copy_data_dir.sh $dataset_dir $dataset_fb_dir || exit 1; rm $dataset_fb_dir/{cmvn,feats}.scp
        steps/make_fbank_pitch.sh --nj $my_nj --cmd "$train_cmd" \
           $dataset_fb_dir $dataset_fb_dir/log $dataset_fb_dir/data || exit 1;
        steps/compute_cmvn_stats.sh $dataset_fb_dir $dataset_fb_dir/log $dataset_fb_dir/data || exit 1;
        touch $dataset_fb_dir/.fbank.done
      fi
      # decoding
      decode=$mdldir/decode_${dataset_id}${ext_suffix}
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
          exp/tri5/graph${ext_suffix} $dataset_fb_dir $decode | tee $decode/decode.log
        touch $decode/.done
      fi

      if [[ "$sys_to_kws_stt" =~ " lstm " ]] || [[ "$sys_to_kws_stt" =~ " exp/lstm4f " ]]; then
        eval "(
        for ive_type in $ive_types; do
          czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
            --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
            --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
            --ive-type \"\$ive_type\" \
            --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
            --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
            "${shadow_set_extra_opts[@]}" "${lmwt_lstm_extra_opts[@]}" \
            ${dataset_dir} data/lang${ext_suffix} $decode
        done
        ) $bg_flag"
      fi
    fi
  done
fi

####################################################################
##
## DNN_MPE (no ext in denlats) decoding
##
####################################################################
if [[ "$sys_to_decode" =~ " tri6_nnet_mpe " ]] || [[ "$sys_to_decode" =~ " exp/tri6_nnet_mpe " ]]; then
  if [ -f exp/tri6_nnet_mpe/.done ]; then
    for epoch in 1; do
      decode=exp/tri6_nnet_mpe/decode_${dataset_id}${ext_suffix}_epoch$epoch
      if [ ! -z $beam_suffix ]; then
        conf_beam=$conf_dnn_beam         # beam settings in conf file of this model
        conf_lat_beam=$conf_dnn_lat_beam # beam settings in conf file of this model
        . czpScripts/clips/decode/determine_decode_dir.sh
        dnn_beam=$extra_beam
        dnn_lat_beam=$extra_lattice_beam
      fi
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet2/decode.sh --minimize $minimize \
          --cmd "$decode_cmd" --nj $my_nj --iter epoch$epoch \
          --beam $dnn_beam --lattice-beam $dnn_lat_beam \
          --skip-scoring true "${decode_extra_opts[@]}" \
          --transform-dir exp/tri5/decode_${dataset_id}${ext_suffix} \
          exp/tri5/graph${ext_suffix} ${dataset_dir} $decode | tee $decode/decode.log

        touch $decode/.done
      fi
      if [[ "$sys_to_kws_stt" =~ " tri6_nnet_mpe " ]] || [[ "$sys_to_kws_stt" =~ " exp/tri6_nnet_mpe " ]]; then
        echo "Now run kws and stt for final"
        eval "(
        for ive_type in $ive_types; do
          czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
            --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
            --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
            --ive-type \"\$ive_type\" \
            --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
            --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
            "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
            ${dataset_dir} data/lang${ext_suffix} $decode
        done
        ) $bg_flag"
      fi
    done
  fi
fi
####################################################################
##
## DNN_MPE (use ext in denlats) decoding
##
####################################################################
if [[ "$sys_to_decode" =~ " tri6_nnet_mpe_ext " ]]; then
  if [ -f exp/tri6_nnet_mpe_$ext/.done ]; then
    for epoch in 1; do
      decode=exp/tri6_nnet_mpe_$ext/decode_${dataset_id}${ext_suffix}_epoch$epoch
      if [ ! -z $beam_suffix ]; then
        conf_beam=$conf_dnn_beam         # beam settings in conf file of this model
        conf_lat_beam=$conf_dnn_lat_beam # beam settings in conf file of this model
        . czpScripts/clips/decode/determine_decode_dir.sh
        dnn_beam=$extra_beam
        dnn_lat_beam=$extra_lattice_beam
      fi
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet2/decode.sh --minimize $minimize \
          --cmd "$decode_cmd" --nj $my_nj --iter epoch$epoch \
          --beam $dnn_beam --lattice-beam $dnn_lat_beam \
          --skip-scoring true "${decode_extra_opts[@]}" \
          --transform-dir exp/tri5/decode_${dataset_id}${ext_suffix} \
          exp/tri5/graph${ext_suffix} ${dataset_dir} $decode | tee $decode/decode.log

        touch $decode/.done
      fi
      if [[ "$sys_to_kws_stt" =~ " tri6_nnet_mpe_ext " ]]; then
        echo "Now run kws and stt for final"
        eval "(
        for ive_type in $ive_types; do
          czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
            --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
            --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
            --ive-type \"\$ive_type\" \
            --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
            --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
            "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
            ${dataset_dir} data/lang${ext_suffix} $decode
        done
        ) $bg_flag"
      fi
    done
  fi
fi

####################################################################
##
## Multilingual DNN_MPE (no ext in denlats) decoding
##    Raw features
##
####################################################################
for mdl in $final_mdl; do
  if [ -f ${mdl}_mpe/.done ]; then
    for epoch in 1; do
      if [ $epoch -ne $final_epoch ]; then
        continue
      fi
      decode=${mdl}_mpe/decode_${dataset_id}${ext_suffix}_epoch$epoch
      if [ ! -z $beam_suffix ]; then
        conf_beam=$conf_dnn_beam         # beam settings in conf file of this model
        conf_lat_beam=$conf_dnn_lat_beam # beam settings in conf file of this model
        . czpScripts/clips/decode/determine_decode_dir.sh
        dnn_beam=$extra_beam
        dnn_lat_beam=$extra_lattice_beam
      fi
      if [ ! -f $decode/.done ]; then
        mkdir -p $decode
        steps/nnet2/decode.sh --minimize $minimize \
          --feat-type raw \
          --cmd "$decode_cmd" --nj $my_nj --iter epoch$epoch \
          --beam $dnn_beam --lattice-beam $dnn_lat_beam \
          --skip-scoring true "${decode_extra_opts[@]}" \
          exp/tri5/graph${ext_suffix} ${dataset_dir} $decode | tee $decode/decode.log

        touch $decode/.done
      fi
      echo "Now run kws and stt for final"

      eval "(
      for ive_type in $ive_types ; do
        echo ==================================
        echo \"IVE type: \$ive_type\"
        echo ==================================
        czpScripts/local/run_kws_stt_task.chenzp.sh --cer $cer --max-states $max_states \
          --basic-kws $basic_kws --subset-kws $subset_kws --ive-kws $ive_kws --oov-kws $oov_kws \
          --ext-lexicon \"${ext_lex}\" --ext-pron \"${ext_pron}\" \
          --ive-type \"\$ive_type\" \
          --skip-scoring $skip_scoring --extra-kws $extra_kws --wip $wip \
          --cmd \"$decode_cmd\" --skip-kws $skip_kws --skip-stt $skip_stt  \
          "${shadow_set_extra_opts[@]}" "${lmwt_dnn_extra_opts[@]}" \
          ${dataset_dir} data/lang${ext_suffix} $decode
      done
      ) $bg_flag"
    done
  fi
done



wait;
[ -e $lockfile ] && rm $lockfile
echo "Job Finished"
exit 0
