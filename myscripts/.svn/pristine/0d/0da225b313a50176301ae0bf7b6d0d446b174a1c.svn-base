#!/bin/bash

# datadir=data-fmllr-tri4b/eval2000_new_text
# phoneconfusion=data-fmllr-tri4b/train_dev/phone_confusion

cmd=run.pl
pos_depend_phone=true
phone_cutoff=5

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
    echo "Usage: $0 <data-dir> <kws-dir> <phone-confusion>"
    echo " e.g. $0 data-fmllr-tri4b/eval2000_new_text data-fmllr-tri4b/eval2000_new_text/kws data-fmllr-tri4b/train_dev/phone_confusion"
    echo "if <phone-confusion> is '-', phone confusion will not be used." 
    echo "[Options]"
    echo "  --pos-depend-phone true/false (default: true)"
    echo "  --phone-cutoff number (default: 5)"
    exit 1;
fi

datadir=$1
kwsdir=$2
if [ $3 != '-' ]; then
    phoneconfusion=$3
else
    phoneconfusion=
fi

czpScripts/kws/kws_data_prep.chenzp.sh data/lang $datadir $kwsdir || exit 1 # generate IV index
czpScripts/kws/generate_oov_lex.sh --pos-depend-phone $pos_depend_phone $kwsdir || exit 1
czpScripts/kws/generate_proxy_keywords.chenzp.sh --cmd "$cmd" --phone-cutoff $phone_cutoff ${phoneconfusion:+ --confusion-matrix $phoneconfusion} $kwsdir $kwsdir/oov.lex data/local/lang/align_lexicon.txt data/lang/words.txt || exit 1 # generate OOV index

echo "Successfully generating keywords fsts."

