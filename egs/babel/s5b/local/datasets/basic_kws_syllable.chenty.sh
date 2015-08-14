#This script is not really supposed to be run directly 
#Instead, it should be sourced from the decoding script
#It makes many assumption on existence of certain environmental
#variables as well as certain directory structure.

if $force_score || [ "${dataset_kind}" == "supervised" ] ; then
  mandatory_variables="my_ecf_file my_kwlist_file my_rttm_file" 
  optional_variables="my_subset_ecf"
else
  mandatory_variables="my_ecf_file my_kwlist_file" 
  optional_variables="my_subset_ecf"
fi

check_variables_are_set

if [ ! -f ${dataset_dir}/kws/.done ] ; then
  if [ "$dataset_kind" == "shadow" ]; then
    # we expect that the ${dev2shadow} as well as ${eval2shadow} already exist
    if [ ! -f data/${dev2shadow}/kws/.done ]; then
      echo "Error: data/${dev2shadow}/kws/.done does not exist."
      echo "Create the directory data/${dev2shadow} first, by calling $0 --dir $dev2shadow --dataonly"
      exit 1
    fi
    if [ ! -f data/${eval2shadow}/kws/.done ]; then
      echo "Error: data/${eval2shadow}/kws/.done does not exist."
      echo "Create the directory data/${eval2shadow} first, by calling $0 --dir $eval2shadow --dataonly"
      exit 1
    fi

    local/kws_data_prep_syllables.chenty.sh \
      data/lang ${dataset_dir} data/local/filtered_lexicon.w2s.txt ${datadir}/kws || exit 1
    utils/fix_data_dir.sh ${dataset_dir}

    touch ${dataset_dir}/kws/.done
  else # This will work for both supervised and unsupervised dataset kinds
    kws_flags=()  # add '', otherwise would report 'unbounded variable' error due to 'set -u' (chenzp Feb 28,2014)
    set +u
    if $force_score || [  "${dataset_kind}" == "supervised"  ] ; then
      kws_flags+=(--rttm-file $my_rttm_file )
    fi
    if $my_subset_ecf ; then
      kws_flags+=(--subset-ecf $my_data_list)
    fi
    local/kws_setup_syllable.chenty.sh --case-insensitive $case_insensitive \
      --silence-word sil "${kws_flags[@]}" "${icu_opt[@]}" \
      $my_ecf_file $my_kwlist_file data/lang ${dataset_dir} || exit 1
    set -u
  fi
  touch ${dataset_dir}/kws/.done 
fi
