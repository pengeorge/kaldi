#!/bin/bash

[ ! -f ./lang.conf ] && echo 'Language configuration does not exist! Use the configurations in conf/lang/* as a startup' && exit 1
[ ! -f ./conf/common_vars.sh ] && echo 'the file conf/common_vars.sh does not exist!' && exit 1

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;

[ -f local.conf ] && . ./local.conf

. ./utils/parse_options.sh

set -e           #Exit on non-zero return code from any command
set -o pipefail  #Exit if any of the commands in the pipeline will 
                 #return non-zero return code
#set -u           #Fail on an undefined variable

data_type=train
expdir=exp/make_mrasta/${data_type}

if [ ! -f $expdir/.done.feat ]; then
  czpScripts/steps/make_mrasta_rasr.sh --cmd "$train_cmd" --nj $train_nj data/$data_type $expdir
  touch $expdir/.done.feat
fi

for t in hi lo; do
  datadir=data_mrasta.${t}/${data_type}
  if [ ! -f $datadir/.mrasta.done ]; then
    ./czpScripts/steps/convert_mrasta_rasr2kaldi.sh --cmd "$train_cmd" --nj $train_nj $expdir/mrasta.${t}.features.cache data/${data_type} $datadir $expdir/$t/log mrasta/$t
    utils/fix_data_dir.sh $datadir
    steps/compute_cmvn_stats.sh $datadir $expdir/$t/log mrasta/$t
    utils/fix_data_dir.sh $datadir
    touch $datadir/.mrasta.done
  fi
done

