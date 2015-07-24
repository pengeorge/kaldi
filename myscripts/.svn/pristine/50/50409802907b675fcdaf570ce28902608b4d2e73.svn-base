#!/bin/bash
set -e
set -u

wlist=./data/extra_lexicon/bbnucoluc100w5EXCVLLP
corpus=./data/extra_text/bbnucoluc100w5
test_set=tun3h.pem
ntrue_file=./exp/dnn_scratch_6langFLPNN.raw_cont_mpe/decode_tun3h.pem_bbnucoluc100w5+.kn_epoch1/bbnucoluc100w5-exc-VLLP_kws_11/Ntrue.txt

. lang.conf
. local.conf
. ./utils/parse_options.sh

des_dir=data/OOV_feats/$(basename $wlist)

if [ ! -f $des_dir/$test_set/.done.ref ]; then
  if [ ! -f data/extra_lexicon/$test_set ]; then
    echo "extra lexicon $test_set not exist"
    exit 1;
  fi
  echo "Get reference..."
  mkdir -p $des_dir/$test_set
  cut -f 1 $wlist | perl ./czpScripts/ext_lex/mark_truth.pl data/extra_lexicon/$test_set > $des_dir/$test_set/ref.txt
  touch $des_dir/$test_set/.done.ref
fi     

if [ ! -f $des_dir/.done.global ]; then
  mkdir -p $des_dir
  # Global
  echo "Get global feature: web 1gram score..."
  ./czpScripts/ext_lex/get_prop_web1gram.sh $wlist data/srilm_$(basename $corpus)/lm.gz $des_dir/web1gram.txt
  echo "Get global feature: average PPL and OOV rate of web sentences containing the specific word"
  ./czpScripts/ext_lex/get_prop_sent_avg_ppl.sh $wlist $corpus $des_dir/sent_avg_ppl.txt
  echo "Get global feature: PPL of phoneme sequences on phoneme-based LM"
  ./czpScripts/ext_lex/get_prop_phone_LM_ppl.sh $wlist $lexicon_file $des_dir/phone_LM_ppl.txt
  touch $des_dir/.done.global
fi

# Local
if [ ! -f $des_dir/$test_set/.done.local ]; then
  echo "Get local features..."
  cut -f 2-4 $ntrue_file | perl -e '
    my %ntrue;
    my %maxScore;
    my $min_ntrue = 99;
    my $min_maxScore = 99;
    while (<STDIN>) {
      chomp;
      my @col = split(/\t/, $_);
      my $w = $col[0];
      $ntrue{$w} = log($col[1]) / log(10);
      $maxScore{$w} = log($col[2]) / log(10);
      if ($ntrue{$w} < $min_ntrue) {
        $min_ntrue = $ntrue{$w};
      }
      if ($maxScore{$w} < $min_maxScore) {
        $min_maxScore = $maxScore{$w};
      }
    }
    $min_ntrue -= 1;
    $min_maxScore -= 1;
    open(LIST, "$ARGV[0]") or die;
    while (<LIST>) {
      chomp;
      my @col = split(/\t/, $_);
      my $w = $col[0];
      print "$w";
      if (defined($ntrue{$w})) {
        print "\t$ntrue{$w}\t$maxScore{$w}\n";
      } else {
        print "\t$min_ntrue\t$min_maxScore\n";
      }
    }
    close(LIST);
    ' $wlist > $des_dir/$test_set/ntrue.txt
  touch $des_dir/$test_set/.done.local
fi


# Generate matrix
echo "Generaing feature matrix CSV..."
paste <(cut -f 2- $des_dir/$test_set/ref.txt) \
  <(cut -f 2- $des_dir/web1gram.txt) <(cut -f 2- $des_dir/sent_avg_ppl.txt) \
  <(cut -f 2- $des_dir/phone_LM_ppl.txt) \
  <(cut -f 2- $des_dir/$test_set/ntrue.txt) | sed 's/\t/,/g' > $des_dir/$test_set/feats.csv

