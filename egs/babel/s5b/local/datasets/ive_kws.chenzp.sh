# Author: chenzp
# Basic IV Expansion


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

function setup_proxy_search {
  local nbest=500
  local g2p_nbest=10
  local g2p_mass=0.95
  local beam=5
  local phone_beam=4
  local phone_nbest=-1
  local phone_cutoff=$oov_phone_cutoff  # for oov, iv's phone_cutoff will be reset later

  local data_dir=$1
  local source_dir=$2
  local is_oov=$3
  local extraid=$4
  
  if [ ! -z $extraid ]; then
    extraid=${extraid}_
  fi
  local kwsdatadir=${source_dir}_ive
  mkdir -p $kwsdatadir

  cp $source_dir/kwlist*.xml $kwsdatadir
  cp $source_dir/ecf.xml $kwsdatadir
  cp $source_dir/utter_* $kwsdatadir
  [ -f $source_dir/rttm ] && cp $source_dir/rttm $kwsdatadir

  oovkwlist=$source_dir/kwlist_outvocab.xml
  #Get the KW list
  paste \
    <(cat $oovkwlist |  grep -o -P "(?<=kwid=\").*(?=\")") \
    <(cat $oovkwlist | grep -o -P "(?<=<kwtext>).*(?=</kwtext>)" | uconv -f utf-8 -t utf-8 -x Any-Lower) \
    >$kwsdatadir/keywords_oov.txt 
  cut -f 2 $kwsdatadir/keywords_oov.txt | \
    sed 's/\s\s*/\n/g' | sort -u > $kwsdatadir/oov.txt


  #Generate the confusion matrix
  #NB, this has to be done only once, as it is training corpora dependent,
  #instead of search collection dependent
  if [ ! -f exp/conf_matrix/.done ] ; then
    local/generate_confusion_matrix.sh --cmd "$decode_cmd" --nj $my_nj  \
      exp/sgmm5/graph exp/sgmm5 exp/sgmm5_ali exp/sgmm5_denlats  exp/conf_matrix
    touch exp/conf_matrix/.done 
  fi
  confusion=exp/conf_matrix/confusions.txt

  if [ ! -f exp/g2p/.done ] ; then
    local/train_g2p.sh  data/local exp/g2p
    touch exp/g2p/.done
  fi
  L2_lex=$data_dir/${extraid}oov_kws/g2p/lexicon.lex
  if [ ! -f $L2_lex ]; then
    local/apply_g2p.chenzp.sh --nj $my_nj --cmd "$decode_cmd" \
      --var-counts $g2p_nbest --var-mass $g2p_mass \
      $kwsdatadir/oov.txt exp/g2p $kwsdatadir/g2p
  else
    mkdir -p $kwsdatadir/g2p
    cp $L2_lex $kwsdatadir/g2p/
  fi
  L2_lex=$kwsdatadir/g2p/lexicon.lex
  L1_lex=data/local/lexiconp.txt

  if [ -z $is_oov ] || $is_oov ; then
    phone_cutoff=$oov_phone_cutoff
#    cut -f 1 $data_dir/${extraid}oov_kws/keywords.txt > $kwsdatadir/proxy_set.list
    cp ${source_dir}/keywords.txt $kwsdatadir/keywords_to_proc.txt
  else
    phone_cutoff=$iv_phone_cutoff
#    grep -v -f <(cut -f 1 $data_dir/${extraid}oov_kws/keywords.txt) $data_dir/${extraid}kws/keywords.txt | cut -f 1 > $kwsdatadir/proxy_set.list
    grep -v -f <(cut -f 1 $data_dir/${extraid}oov_kws/keywords.txt) $data_dir/${extraid}oov_kws/keywords_all.txt > $kwsdatadir/keywords_to_proc.txt
    if $case_insensitive; then
      paste <(cut -f 1 -d ' ' $data_dir/${extraid}oov_kws/tmp/L1.lex |\
              uconv -f utf8 -t utf8 -x Any-Lower) \
        <(cut -f 2 -d ' ' $data_dir/${extraid}oov_kws/tmp/L1.lex) \
        <(cut -f 3- -d ' ' $data_dir/${extraid}oov_kws/tmp/L1.lex) |\
        sed 's:  : :g' > $kwsdatadir/L2_from_L1.lex # in IV case, L2 is the same as L1 but all lower-case
    else
      cp $data_dir/${extraid}oov_kws/tmp/L1.lex $kwsdatadir/L2_from_L1.lex
    fi
    L2_lex=$kwsdatadir/L2_from_L1.lex 
  fi
  cat $kwsdatadir/keywords_to_proc.txt | perl -e '
    open(W, "<'$L2_lex'") ||
      die "Fail to open L2 lexicon: '$L2_lex'\n";
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
    while (<STDIN>) {
      chomp;
      my $line = $_;
      my @col = split();
      @col >= 2 || die "Bad line in keywords file: $_\n";
      my $len = 0;
      for (my $i = 1; $i < scalar(@col); $i ++) {
        if (defined($lexicon{$col[$i]})) {
          $len += $lexicon{$col[$i]};
        } else {
          die "'$0': No pronunciation found for word: $col[$i]\n";
        }
      }
      if ($len >= '$phone_cutoff') {
        print "$line\n";
      } else {
        print STDERR "$line\n";
      }
    }' > $kwsdatadir/keywords_proxy_set.txt 2> $kwsdatadir/keywords_no_proxy_set.txt
    cat $kwsdatadir/keywords_proxy_set.txt | cut -f 1 > $kwsdatadir/proxy_set.list
    cat $kwsdatadir/keywords_no_proxy_set.txt | cut -f 1 > $kwsdatadir/no_proxy_set.list
  local/kws_data_prep_proxy.chenzp.sh \
    --cmd "$decode_cmd" --nj $my_nj \
    --case-insensitive true \
    --confusion-matrix $confusion \
    --phone-cutoff $phone_cutoff \
    --pron-probs true --beam $beam --nbest $nbest \
    --phone-beam $phone_beam --phone-nbest $phone_nbest \
    --make-proxy-stochastic "$make_proxy_stochastic" \
    --proxy-set $kwsdatadir/proxy_set.list \
    data/lang  $data_dir $L1_lex $L2_lex $kwsdatadir
  mv $kwsdatadir/keywords.fsts $kwsdatadir/keywords_proxy.fsts
  if [ -z $is_oov ] || $is_oov ; then 
#   TODO should we do something special for short keywords which are not expanded?
    touch $kwsdatadir/keywords_no_proxy.fsts
  else
    # For those too-short-phone-seq keywords, we don't use proxies but use the original.
    # grep -f $kwsdatadir/no_proxy_set.list $source_dir/keywords.int > $kwsdatadir/keywords_no_proxy.int
    # We also keep the original phone sequences of those not too short keywords.
    cp $source_dir/keywords.int $kwsdatadir/keywords_no_proxy.int
    if [ -z $silence_word ]; then
      transcripts-to-fsts ark:$kwsdatadir/keywords_no_proxy.int ark,t:$kwsdatadir/keywords_no_proxy.fsts
    else
      silence_int=`grep -w $silence_word data/lang/words.txt | awk '{print $2}'`
      [ -z $silence_int ] && \
         echo "$0: Error: could not find integer representation of silence word $silence_word" && exit 1;
      transcripts-to-fsts ark:$kwsdatadir/keywords_no_proxy.int ark,t:- | \
        awk -v 'OFS=\t' -v silint=$silence_int '{if (NF == 4 && $1 != 0) { print $1, $1, silint, silint; } print; }' \
         > $kwsdatadir/keywords_no_proxy.fsts
    fi
  fi
  cat $kwsdatadir/keywords_no_proxy.fsts $kwsdatadir/keywords_proxy.fsts > $kwsdatadir/keywords.fsts

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

  if [ ! -f $dataset_dir/.done.kws_ive ] ; then
    setup_proxy_search $dataset_dir $dataset_dir/kws false
    touch $dataset_dir/.done.kws_ive
  fi
  if [ ! -f $dataset_dir/.done.oov_kws_ive ] ; then
    setup_proxy_search $dataset_dir $dataset_dir/oov_kws true
    touch $dataset_dir/.done.oov_kws_ive
  fi
  if [ ${#my_more_kwlists[@]} -ne 0  ] ; then
    
    touch $dataset_dir/extra_kws_tasks
    
    for extraid in "${!my_more_kwlists[@]}" ; do
      [ -f $dataset_dir/.done.kws_ive.${extraid} ] && continue;
      setup_proxy_search $dataset_dir $dataset_dir/${extraid}_kws false $extraid
      touch $dataset_dir/.done.kws_ive.${extraid}
    done
    for extraid in "${!my_more_kwlists[@]}" ; do
      [ -f $dataset_dir/.done.oov_kws_ive.${extraid} ] && continue;
      setup_proxy_search $dataset_dir $dataset_dir/${extraid}_oov_kws true $extraid
      touch $dataset_dir/.done.oov_kws_ive.${extraid}
    done
  fi
fi

