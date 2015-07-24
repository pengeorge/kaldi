#This script is not really supposed to be run directly 
#Instead, it should be sourced from the decoding script
#It makes many assumption on existence of certain environmental
#variables as well as certain directory structure.

echo '--------------------------'
echo 'basic_kws_subword.chenzp.sh'
echo '--------------------------'

if $force_score || ([ "${dataset_kind}" == "supervised" ] && [[ ! "${dataset_type}" =~ tun ]]) ; then
  use_rttm=true
  mandatory_variables="my_ecf_file my_kwlist_file my_rttm_file" 
  optional_variables="my_subset_ecf"
else
  use_rttm=false
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

    local/kws_data_prep_subword.chenzp.sh --case_insensitive $case_insensitive \
      "${icu_opt[@]}" \
      $w2sfile \
      $word_system_root/data/lang${ext_word_lm_suffix} $lang_dir ${dataset_dir} ${datadir}/kws || exit 1
    utils/fix_data_dir.sh ${dataset_dir}

  else # This will work for both supervised and unsupervised dataset kinds
    kws_flags=()  # add '', otherwise would report 'unbounded variable' error due to 'set -u' (chenzp Feb 28,2014)
    set +u
    if $use_rttm ; then
      kws_flags+=(--rttm-file $my_rttm_file )
    fi
    if $my_subset_ecf ; then
      kws_flags+=(--subset-ecf $my_data_list)
    fi
    local/kws_setup_subword.chenzp.sh --case_insensitive $case_insensitive \
      "${kws_flags[@]}" "${icu_opt[@]}" \
      $my_ecf_file $my_kwlist_file \
      $w2sfile \
      $word_system_root/data/lang${ext_word_lm_suffix} $lang_dir ${dataset_dir} || exit 1
    set -u
  fi
  touch ${dataset_dir}/kws/.done 
fi
