#!/bin/bash

set -e
set -u

lmwt=10  # vi: 9   ta: 10    sw: 11

. conf/common_vars.sh || exit 1;
. ./utils/parse_options.sh


if [ $# -ne 1 ]; then
  echo "Usage: $0 <decode-dir>"
  exit 1;
fi

decode_dir=$1

mdldir=`dirname $decode_dir`
if [[ `basename $mdldir` =~ ^dnn_scratch.*_mpe$ ]]; then
  final_mdl=`echo $mdldir | sed 's/_mpe$//'`
  mdldir=
else
  final_mdl=
fi

datatype=`basename $decode_dir | grep -Po '(?<=^decode_).*\.(pem|seg)'`
dataset=${datatype%%.*}
ext_raw=`basename $decode_dir | sed 's/^decode_.*\.\(pem\|seg\)//' | sed 's/_epoch.*$//' | sed 's/^_//' `

if [ -z $ext_raw ]; then
  echo "ext is empty, cannot do OOC kws"
  exit 1;
fi

kwlist_id=${ext_raw%%+*}-exc-VLLP

echo "ext_raw=$ext_raw"
echo "kwlist_id=$kwlist_id"
echo "mdldir=$mdldir"
echo "final_mdl=$final_mdl"

if [ ! -f $decode_dir/.done.kws.${kwlist_id} ]; then
  ./czpScripts/prep_lex/lexicon_subtraction.pl \
    data/lang_${ext_raw}/words.txt ./data/extra_lexicon/VLLP |\
    grep -v -F "<" | grep -v -F "#"  | \
    awk "{printf \"KW-NEWVOCAB-%05d %s\\n\", \$2, \$1 }" \
    > data/extra_kwlist/${kwlist_id}.txt

  if [ `cat data/extra_kwlist/${kwlist_id}.txt | wc -l` -eq 0 ]; then
    echo "There's no OOC for ext=$ext_raw"
    exit 1;
  fi
  (
   echo '<kwlist ecf_filename="kwlist.xml" language="" encoding="UTF-8" compareNormalize="lowercase" version="" >'
   awk '{ printf("  <kw kwid=\"%s\">\n", $1);
          printf("    <kwtext>"); for (n=2;n<=NF;n++){ printf("%s", $n); if(n<NF){printf(" ");} }
          printf("</kwtext>\n");
          printf("  </kw>\n"); }' < data/extra_kwlist/${kwlist_id}.txt
   echo '</kwlist>'
  ) > data/extra_kwlist/${kwlist_id}.xml || exit 1

  kws_options=" --oov-kws false "
  kws_options="$kws_options --vocab-kws false --extra-kws false --tmp-kws-key ${kwlist_id} --tmp-kwlist data/extra_kwlist/${kwlist_id}.xml "
  ./run-4-ext-LEX-mix-LM-decode.sh --dir ${datatype} --ext ${ext_raw} \
    --do-ext-lexicon true --merge-lexicon true \
    --sys-to-decode " $mdldir " --sys-to-kws-stt " $mdldir " --final-mdl "$final_mdl" \
    --skip-kws false $kws_options
fi

kwsoutdir=$decode_dir/${kwlist_id}_kws_${lmwt}
if [ ! -f $kwsoutdir/Ntrue.txt ]; then
  nj=`ls $kwsoutdir | grep split | head -n 1 | sed 's/split//'`
  if [ -z $nj ]; then
    ./czpScripts/kws/est_Ntrue.pl data/${datatype}_${ext_raw}/${kwlist_id}_kws/keywords.txt \
      $kwsoutdir/kwslist.unnormalized.xml \
      $kwsoutdir/Ntrue.txt
  else
    $decode_cmd JOB=1:$nj $kwsoutdir/log/est_Ntrue.JOB.log \
      ./czpScripts/kws/est_Ntrue.pl data/${datatype}_${ext_raw}/${kwlist_id}_kws/keywords.txt \
        $kwsoutdir/split$nj/kwslist.unnormalized.JOB.xml \
        $kwsoutdir/split$nj/Ntrue.JOB.txt
    cat $kwsoutdir/split$nj/Ntrue.*.txt |\
      sort -n -k 2 | perl -e '
        while (<STDIN>) {
          chomp;
          @col = split(/\t/, $_);
          $kw = "$col[0]\t$col[1]";
          if(!defined($ntrue{$kw})) {
            $ntrue{$kw} = 0;
            $max_score{$kw} = -1;
            $candNum{$kw} = 0;
          }
          $ntrue{$kw} += $col[2];
          if ($col[3] > $max_score{$kw}) {
            $max_score{$kw} = $col[3];
          }
          $candNum{$kw} += $col[4];
        }
        foreach my $kw (sort {$ntrue{$b}<=>$ntrue{$a}} keys %ntrue) {
          print "$kw\t$ntrue{$kw}\n";
        }' > $kwsoutdir/Ntrue.txt
  fi
fi
echo "Calculating OOV cover num"
perl ./mark_truth_on_sorted_OOC_list.pl data/extra_lexicon/$dataset $kwsoutdir/oov_cover.txt \
  < $kwsoutdir/Ntrue.txt  > $kwsoutdir/Ntrue_mark.txt
#max_k=`cat $kwsoutdir/Ntrue.txt | wc -l | grep -Po '^\d+\d\d\d$'`
#max_k=$[max_k+1];
#for k in `seq $max_k`; do
#  ./czpScripts/prep_lex/lexicon_intersection.pl <(head -n ${k}000 $kwsoutdir/Ntrue.txt | cut -f 2) \
#    data/extra_lexicon/$dataset | wc -l 
#done > $kwsoutdir/oov_cover.txt
