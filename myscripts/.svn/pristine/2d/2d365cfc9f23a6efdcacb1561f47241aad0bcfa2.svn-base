# should be include in scripts like:
# . run-norm-test.sh
  if [ -f $decode/.done.kws$suffix_flag ]\
     && [ ! -f $decode/norm-$method/.done.kws$suffix_flag ]; then 
    czpScripts/kws/renorm.chenzp.sh --cmd "$train_cmd" ${lmwt_extra_opts} --suffix "$suffix" \
        --method $method ${dataset_dir} $decode
    touch $decode/norm-$method/.done.kws$suffix_flag
  fi
  if $extra_kws && [ -f ${dataset_dir}/extra_kws_tasks ]; then
    for extraid in `cat ${dataset_dir}/extra_kws_tasks` ; do
    {
      ([ ! -f $decode/.done.kws$suffix_flag.$extraid ] || [ -f $decode/norm-$method/.done.kws$suffix_flag.$extraid ]) && continue;
      czpScripts/kws/renorm.chenzp.sh --cmd "$train_cmd" ${lmwt_extra_opts} --suffix "$suffix" \
          --extraid $extraid --method $method ${dataset_dir} $decode
      touch $decode/norm-$method/.done.kws$suffix_flag.$extraid
    } &
    done
  fi
  wait;
  if $subset_kws && [ -f $dataset_dir/subset_kws_tasks ]; then
    for subsetid in `cat $dataset_dir/subset_kws_tasks` ; do
    {
      [ -f $decode/norm-$method/.done.kws$suffix_flag.subset.$subsetid ] && continue;
      czpScripts/kws/kws_subset_eval.chenzp.sh --cmd "$train_cmd" --suffix "$suffix" \
        ${lmwt_extra_opts} --subdir norm-$method --norm-method $method \
        $subsetid $dataset_dir $decode &
      czpScripts/kws/kws_subset_eval.chenzp.sh --cmd "$train_cmd" --extraid oov --suffix "$suffix" \
        ${lmwt_extra_opts} --subdir norm-$method --norm-method $method\
        $subsetid $dataset_dir $decode &
      wait;
      touch $decode/norm-$method/.done.kws$suffix_flag.subset.$subsetid
    } &
    done
  fi
  wait;
