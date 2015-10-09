
# TODO append ${ext}
[ ! -d exp/tri5/decode_${dirid} ] && echo "No such directory exp/tri5/decode_${dirid}" && exit 1;

# Set my_nj; typically 64.
my_nj=`cat exp/tri5/decode_${dirid}/num_jobs` || exit 1;

if [ ! -f data_mrasta.hi/${dirid}/.mrasta.done ] || [ ! -f data_mrasta.lo/${dirid}/.mrasta.done ]; then
  mrasta_expdir=exp/make_mrasta/${dirid}
  if [ ! -f $mrasta_expdir/.done.feat ]; then
    czpScripts/steps/make_mrasta_rasr.sh --cmd "$train_cmd" --nj $my_nj data/${dirid} $mrasta_expdir
    touch $mrasta_expdir/.done.feat
  fi

  for t in hi lo; do
    raw_mrasta_datadir=data_mrasta.${t}/${dirid}
    if [ ! -f $raw_mrasta_datadir/.mrasta.done ]; then
      ./czpScripts/steps/convert_mrasta_rasr2kaldi.sh --cmd "$train_cmd" --nj $my_nj $mrasta_expdir/mrasta.${t}.features.cache data/${dirid} $raw_mrasta_datadir $mrasta_expdir/$t/log mrasta/$t
      utils/fix_data_dir.sh $raw_mrasta_datadir
      steps/compute_cmvn_stats.sh $raw_mrasta_datadir $mrasta_expdir/$t/log mrasta/$t
      utils/fix_data_dir.sh $raw_mrasta_datadir
      touch $raw_mrasta_datadir/.mrasta.done
    fi
  done
fi

if $transform_feats; then
  transform_dir_opts=" --transform-dir exp/tri5/decode_${dirid} "
else
  transform_dir_opts=
fi
hi_exp_dir=${exp_dir}.hi
hi_data_bnf_dir=${data_bnf_dir}.hi
hi_param_bnf_dir=${param_bnf_dir}.hi
if [ ! ${hi_data_bnf_dir}/${dirid}_bnf/.done -nt exp/tri5/decode_${dirid}/.done ] || \
   [ ! ${hi_data_bnf_dir}/${dirid}_bnf/.done -nt ${hi_exp_dir}/tri6_bnf/.done ]; then
  # put the archives in $param_bnf_dir/.
  czpScripts/nnet2/dump_bottleneck_features.chenzp.sh --nj $my_nj --cmd "$train_cmd" \
    --feat-type raw \
    $transform_dir_opts data_mrasta.hi/${dirid} ${hi_data_bnf_dir}/${dirid}_bnf ${hi_exp_dir}/tri6_bnf ${hi_param_bnf_dir} ${hi_exp_dir}/dump_bnf
  touch ${hi_data_bnf_dir}/${dirid}_bnf/.done
fi

if [ ! $hi_data_bnf_dir/${dirid}/.done -nt $hi_data_bnf_dir/${dirid}_bnf/.done ]; then
  for data_src in $hi_data_bnf_dir/${dirid}_bnf data_mrasta.lo/${dirid}; do
    utils/split_data.sh $data_src $my_nj || exit 1;
  done
  mkdir -p $hi_data_bnf_dir/${dirid}
  for f in segments spk2utt utt2spk wav.scp text reco2file_and_channel stm; do
    if [ -f $hi_data_bnf_dir/${dirid}_bnf/$f ]; then
      cp $hi_data_bnf_dir/${dirid}_bnf/$f $hi_data_bnf_dir/${dirid}/
    fi
  done
  if [ -f ${hi_data_bnf_dir}/bnf1_splice_opts ]; then
    splice_opts=`cat ${hi_data_bnf_dir}/bnf1_splice_opts`
  else
    splice_opts=  # splice-feats.cc set default splice width to 4
  fi
  hi_feats="ark,s,cs:splice-feats $splice_opts scp:$hi_data_bnf_dir/${dirid}_bnf/split${my_nj}/JOB/feats.scp ark:- |"
  if [ -f $hi_data_bnf_dir/train/hi_bn_lda/lda.mat ]; then
    hi_feats="$hi_feats transform-feats $hi_data_bnf_dir/train/hi_bn_lda/lda.mat ark:- ark:- |" 
  fi
    
  czpScripts/steps/append_feats_ext.sh --cmd "$train_cmd" --nj $my_nj \
    "$hi_feats" "scp:data_mrasta.lo/${dirid}/split${my_nj}/JOB/feats.scp" $hi_data_bnf_dir/${dirid} \
    $hi_exp_dir/append_feats/log $hi_param_bnf_dir/ 
  steps/compute_cmvn_stats.sh --fake $hi_data_bnf_dir/${dirid} \
  $hi_exp_dir/append_feats_cmvn $hi_param_bnf_dir
  touch $hi_data_bnf_dir/${dirid}/.done
fi

if [ ! -f $data_bnf_dir/${dirid}_bnf/.done ]; then
  # put the archives in ${param_bnf_dir}/.
  czpScripts/nnet2/dump_bottleneck_features.chenzp.sh --nj $my_nj --cmd "$train_cmd" \
    --feat-type raw \
    $hi_data_bnf_dir/${dirid} $data_bnf_dir/${dirid}_bnf \
    $exp_dir/tri6_bnf $param_bnf_dir $exp_dir/dump_bnf
  touch $data_bnf_dir/${dirid}_bnf/.done
fi

if [ ! $data_bnf_dir/${dirid}/.done -nt $data_bnf_dir/${dirid}_bnf/.done ]; then
  czpScripts/nnet/make_fmllr_feats.chenzp.sh --cmd "$train_cmd -tc 10" \
    --nj $my_nj --transform-dir exp/tri5/decode_${dirid} $data_bnf_dir/${dirid}_sat data/${dirid} \
    exp/tri5_ali $exp_dir/make_fmllr_feats/log $param_bnf_dir/ 

  # TODO Set length tolerance very large, since frames with mrasta features are often fewer than those with fMLLR.
  # There may be something configurable in RASR to avoid this problem.
  steps/append_feats.sh --cmd "$train_cmd" --nj $my_nj \
    --length_tolerance 999 \
    $data_bnf_dir/${dirid}_bnf $data_bnf_dir/${dirid}_sat $data_bnf_dir/${dirid} \
    $exp_dir/append_feats/log $param_bnf_dir/ 
  steps/compute_cmvn_stats.sh --fake $data_bnf_dir/${dirid} $exp_dir/make_fmllr_feats $param_bnf_dir
  rm -r $data_bnf_dir/${dirid}_sat
  utils/fix_data_dir.sh $data_bnf_dir/${dirid}
  if ! $skip_kws ; then
    cp -r data/${dirid}/*kws* $data_bnf_dir/${dirid}/ || true
    cp -r data/${dirid}/*subset* $data_bnf_dir/${dirid}/ || true
  fi
  touch $data_bnf_dir/${dirid}/.done
fi
if ! $skip_kws ; then
  #rm -rf $data_bnf_dir/${dirid}/*kws*
  cp -r data/${dirid}/*kws* $data_bnf_dir/${dirid}/ || true
  cp -r data/${dirid}/*subset* $data_bnf_dir/${dirid}/ || true
fi

