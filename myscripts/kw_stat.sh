#!/bin/bash

set -e

pre=NIST_
kwlist=/home/kaldi/data/babel/scoring/more_kwlists/IARPA-babel202b-v1.0d_conv-dev.kwlist2
#kwlist=/home/kaldi/data/babel/scoring/more_kwlists/IARPA-babel204b-v1.1b_conv-eval.kwlist5
data=dev10h.pem_ext
dir=exp/keywords_stat/$data/kwlist2
#dir=exp/keywords_stat/$data/kwlist5

mkdir -p $dir

grep -Po "(?<=kwid=\")[^\"]*(?=\")" data/$data/${pre}kws/kwlist_invocab.xml > $dir/ivs.txt
grep -Po "(?<=kwid=\")[^\"]*(?=\")" data/$data/${pre}kws/kwlist_outvocab.xml > $dir/oovs.txt
grep -Po "(?<=kwid=\")[^\"]*(?=\")" ${kwlist}.1gram.xml > $dir/1gram.txt
grep -Po "(?<=kwid=\")[^\"]*(?=\")" ${kwlist}.mgram.xml > $dir/mgram.txt
grep KW exp/sgmm5_mmi_b0.1/decode_fmllr_${data}_it1/${pre}kws_12/bsum.txt | grep '\.' |\
  cut -d '|' -f 1-3 | sed '1s:^Keyword \+::' |\
  sed 's:^ *::' | sed 's: *| *:	:g' > $dir/kw_occur_cnt.txt

grep -f $dir/1gram.txt $dir/ivs.txt > $dir/iv_1gram.txt
grep -f $dir/mgram.txt $dir/ivs.txt > $dir/iv_mgram.txt
grep -f $dir/oovs.txt $dir/1gram.txt > $dir/oov_1gram.txt
grep -f $dir/oovs.txt $dir/mgram.txt > $dir/oov_mgram.txt

echo "All keywords"
echo "	"`cat $dir/iv_1gram.txt|wc -l`"	"`cat $dir/iv_mgram.txt|wc -l`
echo "	"`cat $dir/oov_1gram.txt|wc -l`"	"`cat $dir/oov_mgram.txt|wc -l`
echo

grep -f $dir/iv_1gram.txt $dir/kw_occur_cnt.txt > $dir/occur_iv_1gram.txt
grep -f $dir/iv_mgram.txt $dir/kw_occur_cnt.txt > $dir/occur_iv_mgram.txt
grep -f $dir/oov_1gram.txt $dir/kw_occur_cnt.txt > $dir/occur_oov_1gram.txt
grep -f $dir/oov_mgram.txt $dir/kw_occur_cnt.txt > $dir/occur_oov_mgram.txt
echo "Keywords with occurance in $data"
echo "	"`cat $dir/occur_iv_1gram.txt|wc -l`"	"`cat $dir/occur_iv_mgram.txt|wc -l`
echo "	"`cat $dir/occur_oov_1gram.txt|wc -l`"	"`cat $dir/occur_oov_mgram.txt|wc -l`
echo "Occurances"
echo "	"`awk -F '\t' 'BEGIN{cnt=0}{cnt=cnt+$3}END{print cnt}' $dir/occur_iv_1gram.txt`"	"`awk -F '\t' 'BEGIN{cnt=0}{cnt=cnt+$3}END{print cnt}' $dir/occur_iv_mgram.txt`
echo "	"`awk -F '\t' 'BEGIN{cnt=0}{cnt=cnt+$3}END{print cnt}' $dir/occur_oov_1gram.txt`"	"`awk -F '\t' 'BEGIN{cnt=0}{cnt=cnt+$3}END{print cnt}' $dir/occur_oov_mgram.txt`
# grep -Po 'KW\d+-\d+' > keywords_stat/appear.txt

