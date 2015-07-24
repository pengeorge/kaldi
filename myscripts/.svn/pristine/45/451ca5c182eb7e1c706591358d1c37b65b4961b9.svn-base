#This script is not really supposed to be run directly 
#Instead, it should be sourced from the decoding script
#It makes many assumption on existence of certain environmental
#variables as well as certain directory structure.

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

echo "dataset_dir is $dataset_dir"
if [ ! -f ${dataset_dir}/kws/.done ] ; then
  if [ ! -f ${base_dataset_dir}${lex_ext_suffix}/kws/.done ]; then
    # This will work for both supervised and unsupervised dataset kinds
    kws_flags=( --use-icu true)  # add '', otherwise would report 'unbounded variable' error due to 'set -u' (chenzp Feb 28,2014)
    if $use_rttm ; then
      kws_flags+=(--rttm-file $my_rttm_file )
    fi
    if $my_subset_ecf ; then
      kws_flags+=(--subset-ecf $my_data_list)
    fi
    local/kws_setup.chenzp.sh --case_insensitive $case_insensitive \
      "${kws_flags[@]}" "${icu_opt[@]}" \
      $my_ecf_file $my_kwlist_file $lang_dir ${base_dataset_dir}${lex_ext_suffix} || exit 1
    touch ${base_dataset_dir}${lex_ext_suffix}/kws/.done
  fi
  if [ "${base_dataset_dir}${lex_ext_suffix}" != "${dataset_dir}" ]; then
    ln -sf ../`basename ${base_dataset_dir}${lex_ext_suffix}`/kws $dataset_dir/kws
  fi
fi
