# Author: chenzp
# weighted IV Expansion

#This script is not really supposed to be run directly 
#Instead, it should be sourced from the decoding script
#It makes many assumption on existence of certain environmental
#variables as well as certain directory structure.

#set -x;
debug=

if [ -z $model4cm ]; then
  model4cm=sgmm5
  graph_model4cm=sgmm5
fi

if [[ $model4cm =~ ^tri6_nnet ]]; then
  graph_model4cm=tri5
else
  graph_model4cm=$model4cm
fi

if [ -z $lambda ]; then
  lambda=$original_weight
fi

if [ -z $nbest ]; then
  nbest=$proxy_nbest  # if not defined, read from conf/common
fi

id=4

if [ "$id" == "0" ]; then
  use_case=true
  use_log=true
  cm_type=.chenzp
fi
if [ "$id" == "1" ]; then
  use_case=false
  use_log=false
  cm_type=
fi
if [ "$id" == "2" ]; then
  use_case=true
  use_log=true
  cm_type=
fi
if [ "$id" == "3" ]; then
  use_case=true
  use_log=false
  cm_type=.chenzp
fi
if [ "$id" == "4" ]; then
  use_case=true
  use_log=false
  cm_type=
fi

suffix="ive-$id-${model4cm}-${nbest}-${iv_phone_cutoff}-${lambda}"
if $use_total_weight; then
  suffix=${suffix}-t
fi
if ! $make_proxy_stochastic; then
  suffix=${suffix}-ns
  echo "Non-stochastic expansion is not supported in subword version."
  exit 1;
fi
if $self_prior; then
  suffix=${suffix}-sp
fi

if $force_score || [ "${dataset_kind}" == "supervised" ] ; then
  mandatory_variables="my_ecf_file my_kwlist_file my_rttm_file" 
  optional_variables="my_subset_ecf"
else
  mandatory_variables="my_ecf_file my_kwlist_file" 
  optional_variables="my_subset_ecf"
fi

check_variables_are_set

function setup_proxy_search_subword {
  #local nbest=500
  local g2p_nbest=10
  local g2p_mass=0.95
  local beam=5
  local phone_beam=4
  local phone_nbest=-1
  local phone_cutoff=$oov_phone_cutoff  # This is only for OOV. IV's phone_cutoff will be reset later

  local proxy_log_weight=`perl -e "if ('$lambda' eq '1') {print 'Inf';} elsif ($lambda == 1) {print 99;} else {print -log(1-$lambda);}"`
  local original_log_weight=`perl -e "if ('$lambda' eq '0') { print 'Inf'; } elsif ($lambda == 0) { print 99; } else {print -log($lambda);}"`
  # we permit the sum of proxy weight and original weight > 1.0
  local total_log_weight=0  #`perl -e "print -log($original_weight + $proxy_weight);"`

  echo "proxy_log_weight=$proxy_log_weight"
  echo "original_log_weight=$original_log_weight"
  local data_dir=$1
  local source_dir=$2
  local is_oov=$3  # default: true
  set +u
  local extraid=$4
  set -u
  
  if [ ! -z $extraid ]; then
    extraid=${extraid}_
  fi
  local kwsdatadir=${source_dir}_${suffix}
  mkdir -p $kwsdatadir

  for f in $source_dir/kwlist*.xml $source_dir/ecf.xml $source_dir/utter_*; do
    if [ ! -f $kwsdatadir/`basename $f` ]; then
      cp $f $kwsdatadir/
    fi
  done
  [ -f $source_dir/rttm -a ! -f $kwsdatadir/rttm ] && cp $source_dir/rttm $kwsdatadir
  chmod u+w $kwsdatadir/*

  echo "========================================================"
  echo "Preparing $kwsdatadir  `date`"
  echo "========================================================"
  # We hope to use the existing proxy fsts
  proxy_dir=proxy_$id-${model4cm}-${nbest}
  if [ -z $is_oov ] || $is_oov ; then
    proxy_dir=oov_$proxy_dir
  elif $self_prior; then # for IV, if we wish to include the original keyword in the proxies
    proxy_dir=${proxy_dir}-sp
  fi
  proxy_dir=$data_dir/${extraid}$proxy_dir
  if [ ! -d $proxy_dir ]; then
    mkdir -p $proxy_dir
  fi
  # check if we have already generated proxies
  if [ ! -f $proxy_dir/.done ]; then # here we need to generate proxies
    echo "Now generating $proxy_dir: `date`"
    cp $source_dir/kwlist*.xml $proxy_dir/
    chmod u+w $proxy_dir/*
    oovkwlist=$source_dir/kwlist_outvocab.xml
    #Get the KW list
    paste \
      <(cat $oovkwlist |  grep -o -P "(?<=kwid=\").*(?=\")") \
      <(cat $oovkwlist | grep -o -P "(?<=<kwtext>).*(?=</kwtext>)" | uconv -f utf-8 -t utf-8 -x Any-Lower) \
      >$proxy_dir/keywords_oov.txt 
    cut -f 2 $proxy_dir/keywords_oov.txt | \
      sed 's/\s\s*/\n/g' | sort -u > $proxy_dir/oov.txt

    #Generate the confusion matrix
    #NB, this has to be done only once, as it is training corpora dependent,
    #instead of search collection dependent
    if [ ! -f exp/conf_matrix${ext_lm_suffix}/$model4cm/.done ] ; then
      echo "Now train a confusion matrix using $model4cm and ${graph_model4cm}'s graph"
      if [ ! -d exp/$graph_model4cm/graph${ext_lm_suffix} ]; then
        utils/mkgraph.sh \
          $lang_dir exp/$graph_model4cm exp/$graph_model4cm/graph${ext_lm_suffix} |tee exp/$graph_model4cm/mkgraph${ext_lm_suffix}.log
      fi
      local/generate_confusion_matrix.sh --cmd "$decode_cmd" --nj $my_nj  \
        exp/$graph_model4cm/graph${ext_lm_suffix} exp/$model4cm exp/${model4cm}_ali exp/${model4cm}_denlats  exp/conf_matrix${ext_lm_suffix}/$model4cm
      touch exp/conf_matrix${ext_lm_suffix}/$model4cm/.done 
    fi
    confusion=exp/conf_matrix${ext_lm_suffix}/$model4cm/confusions.txt

    if [ ! -f $word_system_root/exp/g2p${ext_word_lm_suffix}/.done ] ; then
      echo "[ERROR] G2P should first be trained in word system: $word_system_root"
      exit 1;
    fi
    #if [ ! -f exp/g2p/.done ] ; then
    #  local/train_g2p.sh  data/local exp/g2p
    #  touch exp/g2p/.done
    #fi
    L2_lex=$data_dir/${extraid}oov_kws/g2p/lexicon.lex
    if [ ! -f $L2_lex ]; then
      local/apply_g2p.chenzp.sh --nj $my_nj --cmd "$decode_cmd" \
        --var-counts $g2p_nbest --var-mass $g2p_mass \
        $proxy_dir/oov.txt exp/g2p $proxy_dir/g2p
    else
      mkdir -p $proxy_dir/g2p
      cp $L2_lex $proxy_dir/g2p/
    fi
    L2_lex=$proxy_dir/g2p/lexicon.lex
    L1_lex=data/local${ext_lex_suffix}/lexiconp.txt
    Lw2p_lex=$word_system_root/data/local${ext_word_lex_suffix}/lexiconp.txt

    if [ -z $is_oov ] || $is_oov ; then
      #phone_cutoff=$oov_phone_cutoff
  #    cut -f 1 $data_dir/${extraid}oov_kws/keywords.txt > $kwsdatadir/proxy_set.list
      cp ${source_dir}/keywords${debug}.txt $proxy_dir/keywords_to_proc.txt
    else
      #phone_cutoff=$iv_phone_cutoff
  #    grep -v -f <(cut -f 1 $data_dir/${extraid}oov_kws/keywords.txt) $data_dir/${extraid}kws/keywords.txt | cut -f 1 > $kwsdatadir/proxy_set.list
      if [ ! -z $debug ]; then
        grep -f <(cut -f 1 ${source_dir}/keywords_debug.txt) $data_dir/${extraid}oov_kws/keywords_all.txt > $proxy_dir/keywords_to_proc.txt
      else
        grep -v -f <(cut -f 1 $data_dir/${extraid}oov_kws/keywords.txt) $data_dir/${extraid}oov_kws/keywords_all.txt > $proxy_dir/keywords_to_proc.txt
      fi
      if $case_insensitive; then
        paste <(cut -f 1 -d ' ' $data_dir/${extraid}oov_kws/tmp/L_w2p.lex |\
                uconv -f utf8 -t utf8 -x Any-Lower) \
          <(cut -f 2 -d ' ' $data_dir/${extraid}oov_kws/tmp/L_w2p.lex) \
          <(cut -f 3- -d ' ' $data_dir/${extraid}oov_kws/tmp/L_w2p.lex) |\
          sed 's: \+: :g' | sort -u > $proxy_dir/L2_from_Lw2p.lex # in IV case, L2 is the same as Lw2p but all lower-case
      else
        cp $data_dir/${extraid}oov_kws/tmp/L_w2p.lex $proxy_dir/L2_from_Lw2p.lex
      fi
      L2_lex=$proxy_dir/L2_from_Lw2p.lex 
    fi
    cat $proxy_dir/keywords_to_proc.txt | cut -f 1 > $proxy_dir/keywords_to_proc.list
    echo "Now generating proxies: `date`"
    if [ -z "$proxy_cmd" ]; then
      proxy_cmd=$decode_cmd
    fi
    local/kws_data_prep_proxy_subword.chenzp.sh \
      --cmd "$proxy_cmd" --nj $my_nj \
      --case-insensitive $case_insensitive \
      --confusion-matrix $confusion \
      --phone-cutoff 1 \
      --pron-probs true --beam $beam --nbest $nbest \
      --phone-beam $phone_beam --phone-nbest $phone_nbest \
      --make-proxy-stochastic "$make_proxy_stochastic" \
      --use-log $use_log --use-case $use_case --cm-type "$cm_type" \
      --self-prior $self_prior \
      --proxy-set $proxy_dir/keywords_to_proc.list \
      $word_system_root/data/lang${ext_word_lm_suffix} $lang_dir  $data_dir \
      $Lw2p_lex $L1_lex $L2_lex $proxy_dir
    mv $proxy_dir/keywords.fsts $proxy_dir/keywords_proxy.fsts
    touch $proxy_dir/.done
   # end of generating proxies
  else
    L1_lex=data/local${ext_lex_suffix}/lexiconp.txt
    if [ -z $is_oov ] || $is_oov ; then
      L2_lex=$proxy_dir/g2p/lexicon.lex
    else
      L2_lex=$proxy_dir/L2_from_Lw2p.lex
    fi
    confusion=exp/conf_matrix${ext_lm_suffix}/$model4cm/confusions.txt
  fi
  if [ -z $is_oov ] || $is_oov ; then
    phone_cutoff=$oov_phone_cutoff
  else
    phone_cutoff=$iv_phone_cutoff
  fi

  # split into proxy set and non-proxy set
  echo "L2_lex is: $L2_lex"
  cat $proxy_dir/keywords_to_proc.txt | perl -e '
    open(W, "<'$L2_lex'") ||
      die "Fail to open L2 lexicon: '$L2_lex'\n";
    open(NOP, ">'$kwsdatadir/keywords_no_proxy_set.txt'") ||
      die "Fail to open output file: '$kwsdatadir/keywords_no_proxy_set.txt'\n";
    my %lexicon;
    while (<W>) {
      chomp;
      my @col = split();
      @col >= 2 || die "'$0': Bad line in lexicon: $_\n";
      if ("true" eq "false") {
        $lexicon{$col[0]} = scalar(@col)-1;
      } else {
        $lexicon{$col[0]} = scalar(@col)-2;
      }
    }
    close(W);
    while (<STDIN>) {
      chomp;
      my $line = $_;
      my @col = split();
      @col >= 2 || die "Bad line in keywords file: $_\n";
      my $len = 0;
      my $ignore = 0;
      for (my $i = 1; $i < scalar(@col); $i ++) {
        if (defined($lexicon{$col[$i]})) {
          $len += $lexicon{$col[$i]};
        } else {
          print STDERR "'$0': [WARNING] No pronunciation found for word: $col[$i]\n";
          $ignore = 1;
          last;
        }
      }
      if ($ignore) {
        next;
      }
      if ($len >= '$phone_cutoff') {
        print "$line\n";
      } else {
        print NOP "$line\n";
      }
    }
    close(NOP);' > $kwsdatadir/keywords_proxy_set.txt
  cat $kwsdatadir/keywords_proxy_set.txt | cut -f 1 > $kwsdatadir/proxy_set.list
  cat $kwsdatadir/keywords_no_proxy_set.txt | cut -f 1 > $kwsdatadir/no_proxy_set.list
  fstcopysubset --subset-key-file=$kwsdatadir/proxy_set.list ark:$proxy_dir/keywords_proxy.fsts ark:$kwsdatadir/keywords_proxy_long.fsts
  fstcopysubset --subset-key-file=$kwsdatadir/no_proxy_set.list ark:$proxy_dir/keywords_proxy.fsts ark:$kwsdatadir/keywords_proxy_short.fsts

  # Now we will scale the FSTs 
  echo "Now scale FSTs: `date`"
  if [ -z $is_oov ] || $is_oov ; then 
    cat > $kwsdatadir/conf << EOF
    make_proxy_stochastic=$make_proxy_stochastic
    oov_phone_cutoff=$oov_phone_cutoff
    proxy_weight=$proxy_weight
    nbest=$nbest
    lambda=$lambda
    use_total_weight=$use_total_weight
    self_prior=$self_prior
EOF
#   TODO should we do something special for short keywords which are not expanded?
    touch $kwsdatadir/keywords_original.fsts
    # for OOV, we ignore keywords_proxy_short and keywords_original
    if $make_proxy_stochastic; then
      if ! $use_total_weight; then
        ## Method 1) scale KWs by proxy_weight even when they have only proxy 
        fstscale --factor=$proxy_log_weight ark:$kwsdatadir/keywords_proxy_long.fsts ark:$kwsdatadir/keywords_proxy_scaled.fsts
      else
        ## Method 2) if KWs only have proxy, assign total weight to them
        fstscale --factor=$total_log_weight ark:$kwsdatadir/keywords_proxy_long.fsts ark:$kwsdatadir/keywords_proxy_scaled.fsts
      fi
      touch $kwsdatadir/keywords_original_scaled.fsts
    else
      cp $kwsdatadir/keywords_proxy_long.fsts $kwsdatadir/keywords_proxy_scaled.fsts
      cp $kwsdatadir/keywords_original.fsts $kwsdatadir/keywords_original_scaled.fsts
    fi
  else
    cat > $kwsdatadir/conf << EOF
    make_proxy_stochastic=$make_proxy_stochastic
    iv_phone_cutoff=$oov_phone_cutoff
    proxy_weight=$proxy_weight
    original_weight=$original_weight
    nbest=$nbest
    lambda=$lambda
    use_total_weight=$use_total_weight
    self_prior=$self_prior
EOF
      
    # TODO add a option to determine whether to use original keyword for the proxied ones. (won't do this,it's much worse)
    # if true; then
      # For those too-short-phone-seq keywords, we don't use proxies but use the original.
    #  grep -f $kwsdatadir/no_proxy_set.list $source_dir/keywords.int > $kwsdatadir/keywords_no_proxy.int
    #else
    # in this case, We also keep the original phone sequences of those not-too-short keywords.
    cp $source_dir/keywords.int $kwsdatadir/keywords_original.int
    #fi

#    set +u
#    if [ -z $silence_word ]; then
#      transcripts-to-fsts ark:$kwsdatadir/keywords_original.int ark,t:$kwsdatadir/keywords_original.fsts
#    else
#      silence_int=`grep -w $silence_word data/lang/words.txt | awk '{print $2}'`
#      [ -z $silence_int ] && \
#         echo "$0: Error: could not find integer representation of silence word $silence_word" && exit 1;
#      transcripts-to-fsts ark:$kwsdatadir/keywords_original.int ark,t:- | \
#        awk -v 'OFS=\t' -v silint=$silence_int '{if (NF == 4 && $1 != 0) { print $1, $1, silint, silint; } print; }' \
#         > $kwsdatadir/keywords_original.fsts
#    fi
#    set -u
    # The way we get original FSTs is different from that in word-based system (commented as followed): 
    #   we copy from the non-expansion version kwsdatadir
    kwsdatabasedir=`echo $kwsdatadir | grep -Po '^.*kws'`
    cp $kwsdatabasedir/keywords.fsts $kwsdatadir/keywords_original.fsts

    # Split into two FSTs, one is for 'long' kw, the other is for 'short' kw
    fstcopysubset --subset-key-file=$kwsdatadir/proxy_set.list ark:$kwsdatadir/keywords_original.fsts ark:$kwsdatadir/keywords_original_long.fsts
    fstcopysubset --subset-key-file=$kwsdatadir/no_proxy_set.list ark:$kwsdatadir/keywords_original.fsts ark:$kwsdatadir/keywords_original_short.fsts

    if $make_proxy_stochastic; then
      if [ $proxy_log_weight == "Inf" ]; then
        touch $kwsdatadir/keywords_proxy_long_scaled.fsts
        touch $kwsdatadir/keywords_proxy_short_scaled.fsts # short keywords have been cut off
        cp $kwsdatadir/keywords_original_long.fsts $kwsdatadir/keywords_original_long_scaled.fsts
      elif [ $original_log_weight == "Inf" ]; then
        cp $kwsdatadir/keywords_proxy_long.fsts $kwsdatadir/keywords_proxy_long_scaled.fsts
        touch $kwsdatadir/keywords_proxy_short_scaled.fsts # short keywords have been cut off
        touch $kwsdatadir/keywords_original_long_scaled.fsts
      else
        fstscale --factor=$proxy_log_weight ark:$kwsdatadir/keywords_proxy_long.fsts ark:$kwsdatadir/keywords_proxy_long_scaled.fsts 
        # fstmakestochastic --total-weight=$proxy_log_weight ark:$kwsdatadir/keywords_proxy_short.fsts ark:$kwsdatadir/keywords_proxy_short_scaled.fsts
        touch $kwsdatadir/keywords_proxy_short_scaled.fsts # short keywords have been cut off
        fstscale --factor=$original_log_weight ark:$kwsdatadir/keywords_original_long.fsts ark:$kwsdatadir/keywords_original_long_scaled.fsts
      fi
      if [ $original_log_weight == "Inf" ]; then
        if ! $use_total_weight; then
          touch $kwsdatadir/keywords_original_short_scaled.fsts
        else
          cp $kwsdatadir/keywords_original_short.fsts $kwsdatadir/keywords_original_short_scaled.fsts
        fi
      else
        if ! $use_total_weight; then
          fstscale --factor=$original_log_weight ark:$kwsdatadir/keywords_original_short.fsts ark:$kwsdatadir/keywords_original_short_scaled.fsts
        else
          fstscale --factor=$total_log_weight ark:$kwsdatadir/keywords_original_short.fsts ark:$kwsdatadir/keywords_original_short_scaled.fsts
        fi
      fi
      cat $kwsdatadir/keywords_proxy_short_scaled.fsts $kwsdatadir/keywords_proxy_long_scaled.fsts > $kwsdatadir/keywords_proxy_scaled.fsts
      cat $kwsdatadir/keywords_original_short_scaled.fsts $kwsdatadir/keywords_original_long_scaled.fsts > $kwsdatadir/keywords_original_scaled.fsts
    else
      cp $kwsdatadir/keywords_proxy_long.fsts $kwsdatadir/keywords_proxy_scaled.fsts
      cp $kwsdatadir/keywords_original.fsts $kwsdatadir/keywords_original_scaled.fsts
    fi
  fi
  cat $kwsdatadir/keywords_original_scaled.fsts $kwsdatadir/keywords_proxy_scaled.fsts > $kwsdatadir/keywords.fsts

}


if [ "$dataset_kind" == "shadow" ]; then
  true #we do not support multiple kw lists for shadow set system
   
else # This will work for both supervised and unsupervised dataset kinds
  kws_flags=()
  if $force_score || [  "${dataset_kind}" == "supervised"  ] ; then
    #The presence of the file had been already verified, so just 
    #add the correct switches
    kws_flags+=(--rttm-file $my_rttm_file )
  fi
  if $my_subset_ecf ; then
    kws_flags+=(--subset-ecf $my_data_list)
  fi

  if [ ! -f $dataset_dir/kws_${suffix}/.done ] ; then
    setup_proxy_search_subword $dataset_dir $dataset_dir/kws false
    touch $dataset_dir/kws_${suffix}/.done
  fi
  if [ ! -f $dataset_dir/oov_kws_${suffix}/.done ] ; then
    setup_proxy_search_subword $dataset_dir $dataset_dir/oov_kws true
    touch $dataset_dir/oov_kws_${suffix}/.done
  fi
  if [ ${#my_more_kwlists[@]} -ne 0  ] ; then
    
    touch $dataset_dir/extra_kws_tasks
    
    for extraid in "${!my_more_kwlists[@]}" ; do
      [ -f $dataset_dir/${extraid}_kws_${suffix}/.done ] && continue;
      setup_proxy_search_subword $dataset_dir $dataset_dir/${extraid}_kws false $extraid
      touch $dataset_dir/${extraid}_kws_${suffix}/.done
    done
    for extraid in "${!my_more_kwlists[@]}" ; do
      [ -f $dataset_dir/${extraid}_oov_kws_${suffix}/.done ] && continue;
      setup_proxy_search_subword $dataset_dir $dataset_dir/${extraid}_oov_kws true $extraid
      touch $dataset_dir/${extraid}_oov_kws_${suffix}/.done
    done
  fi
fi

