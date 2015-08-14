#This script is not really supposed to be run directly 
#Instead, it should be sourced from the decoding script
#It makes many assumption on existence of certain environmental
#variables as well as certain directory structure.

if [ -z $model4cm ]; then
  model4cm=sgmm5
  graph_model4cm=sgmm5
fi

if [[ $model4cm =~ ^tri6 ]]; then
  graph_model4cm=tri5
else
  graph_model4cm=$model4cm
fi

if [ ! -z "$ext_pron" ]; then
  suffix=_ep-`basename $ext_pron`
else
  suffix=
fi

#if $force_score || [ "${dataset_kind}" == "supervised" ] ; then
if $force_score || ([ "${dataset_kind}" == "supervised" ] && [[ ! "${dataset_type}" =~ tun ]]) ; then
  use_rttm=true
  mandatory_variables="my_ecf_file my_rttm_file" 
  optional_variables="my_subset_ecf"
else
  use_rttm=false
  mandatory_variables="my_ecf_file " 
  optional_variables="my_subset_ecf"
fi

check_variables_are_set

function register_extraid {
  local dataset_dir=$1
  local extraid=$2
  echo "Registering $extraid"
  echo $extraid >> $dataset_dir/extra_kws_tasks;  
  sort -u $dataset_dir/extra_kws_tasks -o $dataset_dir/extra_kws_tasks
}

function setup_oov_search {
  local nbest=$proxy_nbest
  local g2p_nbest=10
  local g2p_mass=0.95
  local beam=5
  local phone_beam=4
  local phone_nbest=-1
  local phone_cutoff=5

  local data_dir=$1
  local source_dir=$2
  local extraid=$3
  
  local kwsdatadir=$data_dir/${extraid}_kws${suffix}

  mkdir -p $kwsdatadir
  cp -f $source_dir/kwlist*.xml $kwsdatadir
  cp -f $source_dir/ecf.xml $kwsdatadir
  #cp $source_dir/utter_* $kwsdatadir
  [ -f $source_dir/rttm ] && cp -f $source_dir/rttm $kwsdatadir

  kwlist=$source_dir/kwlist_outvocab.xml
  #Get the KW list
  paste \
    <(cat $kwlist |  grep -o -P "(?<=kwid=\").*(?=\")") \
    <(cat $kwlist | grep -o -P "(?<=<kwtext>).*(?=</kwtext>)" | uconv -f utf-8 -t utf-8 -x Any-Lower) \
    >$kwsdatadir/keywords.txt 
  cut -f 2 $kwsdatadir/keywords.txt | \
    sed 's/\s\s*/\n/g' | sort -u > $kwsdatadir/oov.txt


  #Generate the confusion matrix
  #NB, this has to be done only once, as it is training corpora dependent,
  #instead of search collection dependent
  if [ ! -f exp/conf_matrix${ext_lm_suffix}/$model4cm/.done ] ; then
    if [ ! -d exp/$graph_model4cm/graph${ext_lm_suffix} ]; then
      utils/mkgraph.sh \
        $lang_dir exp/$graph_model4cm exp/$graph_model4cm/graph${ext_lm_suffix} |tee exp/$graph_model4cm/mkgraph${ext_lm_suffix}.log
    fi
    local/generate_confusion_matrix.sh --cmd "$decode_cmd" --nj $my_nj  \
      exp/$graph_model4cm/graph${ext_lm_suffix} exp/$model4cm exp/${model4cm}_ali exp/${model4cm}_denlats  exp/conf_matrix${ext_lm_suffix}/$model4cm
    touch exp/conf_matrix${ext_lm_suffix}/$model4cm/.done 
  fi
  confusion=exp/conf_matrix${ext_lm_suffix}/$model4cm/confusions.txt

  if ! $is_graphemic_lex; then
    if [ ! -f exp/g2p${lex_ext_suffix}/.done ] ; then
      local/train_g2p.sh ./data/local${lex_ext_suffix}/lexicon.txt exp/g2p${lex_ext_suffix}
      touch exp/g2p${lex_ext_suffix}/.done
    fi
    if [ -z "${lex_ext_suffix}" ] && [ ! -z "${ext_lm_suffix}" ]; then
      ln -sf g2p exp/g2p${ext_lm_suffix}
    fi
    local/apply_g2p.chenzp.sh --nj $my_nj --cmd "$decode_cmd" \
      --var-counts $g2p_nbest --var-mass $g2p_mass \
      --ext-pron "$ext_pron" \
      $kwsdatadir/oov.txt exp/g2p${lex_ext_suffix} $kwsdatadir/g2p
    L2_lex=$kwsdatadir/g2p/lexicon.lex
  else # is_graphemic_lex
    L2_lex=$kwsdatadir/oov_graphemic_lex/lexicon.lex
    mkdir -p `dirname $L2_lex`
    cat $kwsdatadir/oov.txt |\
      ./czpScripts/prep_lex/gen_graphemic_lex.pl \
      --phonemap="$phoneme_mapping" --phoneset="data/local/nonsilence_phones.txt" |\
      awk -F"\t" '{printf("%s\t%f\t%s\n", $1, 1.0, $2);}' \
      > $L2_lex
  fi

  L1_lex=data/local${lex_ext_suffix}/lexiconp.txt
  local/kws_data_prep_proxy.chenzp.sh \
    --cmd "$decode_cmd" --nj $my_nj \
    --case-insensitive true \
    --confusion-matrix $confusion \
    --phone-cutoff $phone_cutoff \
    --pron-probs true --beam $beam --nbest $nbest \
    --phone-beam $phone_beam --phone-nbest $phone_nbest \
    --existing-proxy-fsts "$existing_proxy_fsts" \
    $lang_dir  $data_dir $L1_lex $L2_lex $kwsdatadir

}


if [ "$dataset_kind" == "shadow" ]; then
  true #we do not support multiple kw lists for shadow set system
   
else # This will work for both supervised and unsupervised dataset kinds
  kws_flags=()
  if $use_rttm; then
    #The presence of the file had been already verified, so just 
    #add the correct switches
    kws_flags+=(--rttm-file $my_rttm_file )
  fi
  if $my_subset_ecf ; then
    kws_flags+=(--subset-ecf $my_data_list)
  fi

  if $basic_kws && $oov_kws && [ ! -f $dataset_dir/.done.kws.oov${suffix} ] && [ ! -f $dataset_dir/oov_kws${suffix}/.done ]; then
    if [ ! -f ${base_dataset_dir}${lex_ext_suffix}/.done.kws.oov${suffix} ]; then
      setup_oov_search ${base_dataset_dir}${lex_ext_suffix} ${base_dataset_dir}${lex_ext_suffix}/kws oov
    fi
    if [ "${base_dataset_dir}${lex_ext_suffix}" != "${dataset_dir}" ]; then
      ln -sf ../`basename ${base_dataset_dir}${lex_ext_suffix}`/oov_kws${suffix} ${dataset_dir}/oov_kws${suffix}
    fi
    register_extraid $dataset_dir oov
    touch $dataset_dir/.done.kws.oov${suffix}
  fi
  if [ ${#my_more_kwlists[@]} -ne 0  ] ; then
    
    touch $dataset_dir/extra_kws_tasks
    
    for extraid in "${!my_more_kwlists[@]}" ; do
      #The next line will help us in running only one. We don't really
      #know in which directory the KWS setup will reside in, so we will 
      #place  the .done file directly into the data directory
      ([ -f $dataset_dir/.done.kws.$extraid ] || [ -f $dataset_dir/${extraid}_kws/.done ]) && continue;
      if [ ! -f ${base_dataset_dir}${lex_ext_suffix}/.done.kws.${extraid} ]; then
        kwlist=${my_more_kwlists[$extraid]}

        local/kws_setup.chenzp.sh  --extraid $extraid --case_insensitive $case_insensitive \
          "${kws_flags[@]}" "${icu_opt[@]}" \
          $my_ecf_file $kwlist $lang_dir ${base_dataset_dir}${lex_ext_suffix} || exit 1
      fi
      if [ "${base_dataset_dir}${lex_ext_suffix}" != "${dataset_dir}" ]; then
        ln -sf ../`basename ${base_dataset_dir}${lex_ext_suffix}`/${extraid}_kws $dataset_dir/${extraid}_kws
      fi
      #Register the dataset for default running...
      #We can do it without any problem here -- the kws_stt_tasks will not
      #run it, unless called with --run-extra-tasks true switch
      register_extraid $dataset_dir $extraid
      touch $dataset_dir/${extraid}_kws/.done
    done
    if $oov_kws; then
      for extraid in "${!my_more_kwlists[@]}" ; do
        #The next line will help us in running only one. We don't really
        #know in which directory the KWS setup will reside in, so we will 
        #place  the .done file directly into the data directory
        [ -f $dataset_dir/.done.kws.${extraid}_oov${suffix} ] && continue;
        ([ -f $dataset_dir/.done.kws.${extraid}_oov${suffix} ] || [ -f $dataset_dir/${extraid}_oov_kws${suffix}/.done ]) && continue;
        if [ ! -f ${base_dataset_dir}${lex_ext_suffix}/.done.kws.${extraid}_oov${suffix} ]; then
          setup_oov_search ${base_dataset_dir}${lex_ext_suffix} ${base_dataset_dir}${lex_ext_suffix}/${extraid}_kws ${extraid}_oov
        fi
        if [ "${base_dataset_dir}${lex_ext_suffix}" != "${dataset_dir}" ]; then
          ln -sf ../`basename ${base_dataset_dir}${lex_ext_suffix}`/${extraid}_oov_kws${suffix} $dataset_dir/${extraid}_oov_kws${suffix}
        fi
        register_extraid $dataset_dir ${extraid}_oov
        touch $dataset_dir/${extraid}_oov_kws${suffix}/.done
      done
    fi
  fi
fi

