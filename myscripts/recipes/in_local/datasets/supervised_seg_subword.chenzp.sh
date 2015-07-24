#This script is not really supposed to be run directly 
#Instead, it should be sourced from the decoding script
#It makes many assumption on existence of certain environmental
#variables as well as certain directory structure.
if [ ${dataset_type} != "supervised" ] ; then
  mandatory_variables="my_data_dir my_data_list my_nj"
  optional_variables=""
else
  mandatory_variables="my_data_dir my_data_list my_nj"
  optional_variables="my_stm_file"
fi

check_variables_are_set

if [ ! -f $word_system_root/${dataset_dir}/.done ] ; then
  echo "[ERROR] ${dataset_dir} should first be generated in word system: $word_system_root"
  exit 1;
fi
if [ ! -f $word_system_root/${dataset_dir}/.plp.done ] ; then
  echo "[ERROR] PLP features of ${dataset_dir} should first be generated in word system: $word_system_root"
  exit 1;
fi

mkdir -p ${dataset_dir}
touch ${dataset_dir}/.plp.done
for file in {reco2file_and_channel,spk2utt,wav.scp,segments,cmvn.scp,utt2spk,feats.scp}; do
  if [ ! -f $word_system_root/${dataset_dir}/$file ]; then
    echo "[ERROR] $file of ${dataset_dir} should exist in word system: $word_system_root"
    exit 1;
  fi
  cp $word_system_root/${dataset_dir}/$file ${dataset_dir}/$file
done

num_hours=`cat ${dataset_dir}/segments | \
  awk '{secs+= $4-$3;} END{print(secs/3600);}'`

echo "Number of hours of the newly segmented data: $num_hours"

if [ "$dataset_kind" == "supervised" ]; then
  echo ---------------------------------------------------------------------
  echo "Preparing ${dataset_id} stm files in ${dataset_dir} on" `date`
  echo ---------------------------------------------------------------------
  if [ ! -z $my_stm_file ] ; then
    local/augment_original_stm.pl $my_stm_file ${dataset_dir}
  else
    local/prepare_stm.pl --fragmentMarkers \-\*\~ ${dataset_dir}
  fi
fi
touch ${dataset_dir}/.done

