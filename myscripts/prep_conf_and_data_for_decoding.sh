# This script is the common part of different decoding scripts,
# including environmental variables and data preparation.

#This script is not really supposed to be run directly 
#Instead, it should be sourced from the decoding script
#It makes many assumption on existence of certain environmental
#variables as well as certain directory structure.


#This seems to be the only functioning way how to ensure the comple
#set of scripts will exit when sourcing several of them together
#Otherwise, the CTRL-C just terminates the deepest sourced script ?
# Let shell functions inherit ERR trap.  Same as `set -E'.
set -o errtrace 
trap "echo Exited!; exit;" SIGINT SIGTERM

dataset_segments=${dir##*.}
dataset_dir=data/$dir
dataset_id=$dir
dataset_type=${dir%%.*}
#By default, we want the script to accept how the dataset should be handled,
#i.e. of  what kind is the dataset
if [ -z ${kind} ] ; then
  if [ "$dataset_type" == "dev2h" ] || [ "$dataset_type" == "dev10h" ] ; then
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
if [ -z $my_data_dir ] || [ -z $my_data_list ] ; then
  echo "Error: The dir you specified ($dataset_id) does not have existing config";
  exit 1
fi

eval my_stm_file=\$${dataset_type}_stm_file
eval my_ecf_file=\$${dataset_type}_ecf_file 
eval my_kwlist_file=\$${dataset_type}_kwlist_file 
eval my_rttm_file=\$${dataset_type}_rttm_file
eval my_nj=\$${dataset_type}_nj  #for shadow, this will be re-set when appropriate

my_subset_ecf=false
eval ind=\${${dataset_type}_subset_ecf+x}
if [ "$ind" == "x" ] ; then
  my_subset_ecf=\$${dataset_type}_subset_ecf
fi

declare -A my_more_kwlists
eval my_more_kwlist_keys="\${!${dataset_type}_more_kwlists[@]}"
for key in $my_more_kwlist_keys  # make sure you include the quotes there
do
  eval my_more_kwlist_val="\${${dataset_type}_more_kwlists[$key]}"
  my_more_kwlists["$key"]="${my_more_kwlist_val}"
done

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


if  [ "$dataset_kind" == "shadow" ] ; then
  # we expect that the ${dev2shadow} as well as ${eval2shadow} already exist
  if [ ! -f data/${dev2shadow}/.done ]; then
    echo "Error: data/${dev2shadow}/.done does not exist."
    echo "Create the directory data/${dev2shadow} first"
    echo "e.g. by calling $0 --type $dev2shadow --dataonly"
    exit 1
  fi
  if [ ! -f data/${eval2shadow}/.done ]; then
    echo "Error: data/${eval2shadow}/.done does not exist."
    echo "Create the directory data/${eval2shadow} first."
    echo "e.g. by calling $0 --type $eval2shadow --dataonly"
    exit 1
  fi
  
  local/create_shadow_dataset.sh ${dataset_dir} \
    data/${dev2shadow} data/${eval2shadow}
  utils/fix_data_dir.sh ${datadir}
  nj_max=`cat $dataset_dir/wav.scp | wc -l`
  my_nj=64
else
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
fi
if [ "$nj_max" -lt "$my_nj" ] ; then
  echo "Number of jobs ($my_nj) is too big!"
  echo "The maximum reasonable number of jobs is $nj_max"
  my_nj=$nj_max
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
  if [ "$dataset_kind" == "supervised" ]  ; then
    if [ "$dataset_segments" == "seg" ] ; then
      . ./local/datasets/supervised_seg.sh
    elif [ "$dataset_segments" == "uem" ] ; then
      . ./local/datasets/supervised_uem.sh
    elif [ "$dataset_segments" == "pem" ] ; then
      . ./local/datasets/supervised_pem.sh
    else
      echo "Unknown type of the dataset: \"$dataset_segments\"!";
      echo "Valid dataset types are: seg, uem, pem";
      exit 1
    fi
  elif [ "$dataset_kind" == "unsupervised" ] ; then
    if [ "$dataset_segments" == "seg" ] ; then
      . ./local/datasets/unsupervised_seg.sh 
    elif [ "$dataset_segments" == "uem" ] ; then
      . ./local/datasets/unsupervised_uem.sh
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
  elif  [ "$dataset_kind" == "shadow" ] ; then
    #We don't actually have to do anything here
    #The shadow dir is already set...
    true  
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
if ! $force_score ; then
  if [ "$dataset_kind" == "unsupervised" ]; then
    skip_scoring=true
  fi
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

