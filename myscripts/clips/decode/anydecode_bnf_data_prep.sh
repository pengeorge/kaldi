
[ ! -d data/${dirid} ] && echo "No such directory data/${dirid}" && exit 1;
[ ! -d exp/tri5/decode_${dirid}${ext} ] && echo "No such directory exp/tri5/decode_${dirid}${ext}" && exit 1;

# Set my_nj; typically 64.
my_nj=`cat exp/tri5/decode_${dirid}${ext}/num_jobs` || exit 1;


if [ ! $data_bnf_dir/${dirid}_bnf/.done -nt exp/tri5/decode_${dirid}${ext}/.done ] || \
   [ ! $data_bnf_dir/${dirid}_bnf/.done -nt $exp_dir/tri6_bnf/.done ]; then
  # put the archives in $param_bnf_dir/.
  if $transform_feats; then
    transform_dir_opts=" --transform-dir exp/tri5/decode_${dirid}${ext} "
  else
    transform_dir_opts=
  fi
  czpScripts/nnet2/dump_bottleneck_features.chenzp.sh --nj $my_nj --cmd "$train_cmd" \
    $transform_dir_opts data/${dirid} $data_bnf_dir/${dirid}_bnf $exp_dir/tri6_bnf $param_bnf_dir $exp_dir/dump_bnf
  touch $data_bnf_dir/${dirid}_bnf/.done
fi

if [ ! $data_bnf_dir/${dirid}/.done -nt $data_bnf_dir/${dirid}_bnf/.done ]; then
  czpScripts/nnet/make_fmllr_feats.chenzp.sh --cmd "$train_cmd -tc 10" \
    --nj $my_nj --transform-dir exp/tri5/decode_${dirid}${ext} $data_bnf_dir/${dirid}_sat data/${dirid} \
    exp/tri5_ali $exp_dir/make_fmllr_feats/log $param_bnf_dir/ 

  steps/append_feats.sh --cmd "$train_cmd" --nj 4 \
    $data_bnf_dir/${dirid}_bnf $data_bnf_dir/${dirid}_sat $data_bnf_dir/${dirid} \
    $exp_dir/append_feats/log $param_bnf_dir/ 
  steps/compute_cmvn_stats.sh --fake $data_bnf_dir/${dirid} $exp_dir/make_fmllr_feats $param_bnf_dir
  rm -r $data_bnf_dir/${dirid}_sat
  touch $data_bnf_dir/${dirid}/.done
fi
if ! $skip_kws ; then
  #rm -rf $data_bnf_dir/${dirid}/*kws*
  cp -r data/${dirid}${ext}/*kws* $data_bnf_dir/${dirid}${ext}/ || true
  cp -r data/${dirid}${ext}/*subset* $data_bnf_dir/${dirid}${ext}/ || true
fi

