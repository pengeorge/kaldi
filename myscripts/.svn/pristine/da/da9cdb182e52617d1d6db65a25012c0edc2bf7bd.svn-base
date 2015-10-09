#!/bin/bash

cmd=utils/run.pl

. lang.conf

if [ $# != 1 ]; then
    echo "Usage: $0 <kws-dir>"
    echo "e.g. $0 exp/tri4a/decode/kws_12"
    exit 1;
fi
kwsdir=$1
dir=`dirname $kwsdir | grep -Po '(?<=decode_).*\.[^_/]+(?=_|/|$)' | sed 's/.*_\(.*\)/\1/'`
data_type=${dir%%.*}
rawsrc=data/raw_${data_type}_data
eval rttm=\$${data_type}_rttm_file
data_dir=data/$dir

if [ ! -d $kwsdir ]; then
  echo "[ERROR] KWS dir doesn't exist."
  exit 1;
fi

if [ ! -d $rawsrc ]; then
  echo "[ERROR] Raw data dir doesn't exist."
  exit 1;
fi

# RTTM to textgrid, on raw data with rttm file specified
if [ ! -f $rawsrc/.done.rttm2textgrids ]; then
  mkdir -p $rawsrc/textgrids
  cat $rttm | awk 'BEGIN{audio=""}{
    if ($1 == "LEXEME" || $1 == "NON-LEX" || $1 == "NON-SPEECH"){
      if ($2 != audio) {
        if (audio != "") {
          print ".";
        } else {
          print "#!MLF!#";
        }
        audio = $2;
        print "\""audio"\"";
      }
      printf "%d %d %s\n",$4*100,($4+$5)*100, $6;
    } } END{print "."}' > $rawsrc/rttm.mlf
  
  PraatConverter $rawsrc/rttm.mlf $rawsrc/textgrids
  touch $rawsrc/.done.rttm2textgrids
fi

  function append_tier {
    file=$1
    tier_name=$2
    new_tier_labeled_seg=$3
    tier_num=`cat $file | sed -n '7p' | grep -Po '(?<=size = )\d+(?=\s*$)'`
    xmax=`cat $file | sed -n '13p' | grep -Po '(?<=xmax = )[\d\.]+(?=\s*$)'`
    tier_num=$[$tier_num+1]
    new_tier_seg="`echo "$new_tier_labeled_seg" |\
      awk -F "\t" -v max="$xmax" 'BEGIN{tbeg=0} {
        if ($1>tbeg) {
          print tbeg"\t"$1;
        }
        print $0;
        tbeg=$2;
      } END{if (tbeg < max) { print tbeg"\t"max} }'`"
    cat $file | sed "7s/[0-9]\+/$tier_num/"
    new_tier_size=`echo "$new_tier_seg" | wc -l`
    echo "    item [$tier_num]:"
    echo "        class = \"IntervalTier\" "
    echo "        name = \"$tier_name\" "
    echo "        xmin = 0 "
    echo "        xmax = $xmax "
    echo "        intervals: size = $new_tier_size "
    echo "$new_tier_seg" | awk -F "\t" '{
      print "        intervals ["NR"]:";
      print "            xmin = "$1" ";
      print "            xmax = "$2" ";
      print "            text = \""$3"\" "; }'
    echo ''
  }

# append KWS Ref to raw textgrids, with kwlist specified by $kwsdir
if [ ! -f $rawsrc/.done.kwsref2textgrids ]; then
  mkdir -p $rawsrc/kws_ref
  for file in $rawsrc/textgrids/*; do
    audio_key=`basename $file |  grep -Po '^.*(?=\.textgrid)'`
    new_tier_labeled_seg="`sed '1d' $kwsdir/alignment.csv | grep $audio_key | grep -P '(,MISS$)|(YES,CORR$)' |\
      cut -d ',' -f 4-7 | awk -F, '{print $3"\t"$4"\t"$1"("$2")"}' | sort -n -k 1`"
    append_tier $file "KWS Ref" "$new_tier_labeled_seg" > $rawsrc/kws_ref/`basename $file`
  done 
  touch $rawsrc/.done.kwsref2textgrids
fi
# append segmentation to KWS Ref textgrids, with dataset and segmentation type specified by $data_dir
if [ ! -f $data_dir/view/.done.seg2textgrids ]; then
  mkdir -p $data_dir/view/textgrids
  for file in $rawsrc/kws_ref/*; do
    audio_key=`basename $file |  grep -Po '^.*(?=\.textgrid)'`
    new_tier_labeled_seg="`grep $audio_key $data_dir/segments | cut -d ' ' -f 3,4 --output-delimiter=\"	\" | sed 's/$/\t<utt>/'`"
    append_tier $file "segments" "$new_tier_labeled_seg" > $data_dir/view/textgrids/`basename $file`
  done 
  touch $data_dir/view/.done.seg2textgrids
fi
# Generate kwslist.unnormalized.xml in plain format
cat $kwsdir/kwslist.unnormalized.xml | perl -e '
  while (<STDIN>) {
    chomp;
    if (/<detected_kwlist.*kwid="([^"]*)"/) {
      $kw = $1;
    } elsif (/<kw file="([^"]*)".* tbeg="([^"]*)".* score="([^"]*)"/) {
      $audio = $1;
      $tbeg = $2;
      $score = $3;
      print "$kw $audio $tbeg\t$score\n";
    } elsif (/<\/detected_kwlist>/) {
    }
  }' > $kwsdir/kwslist.unnormalized.txt
# Generate extended alignment.csv
perl < $kwsdir/alignment.csv -e '
  open(UNNORM,"'$kwsdir'/kwslist.unnormalized.txt") || die "cannot open kwslist.unnormalized.txt\n";
  my %unnorm;
  while (<UNNORM>) {
    chomp;
    my @col=split(/\t/,$_);
    $unnorm{$col[0]} = $col[1];
  }
  close(UNNORM);

  open(BSUM,"'$kwsdir'/bsum.txt") || die "cannot open bsum.txt\n";
  my $k=18;
  while ($k--) {<BSUM>}
  my %targ;
  while (<BSUM>) {
    chomp;
    my @col = split(/\s*\|\s*/, $_);
    my $kw;
    if ($col[0] =~ m/(KW\d{3}\-\d{4})/) {
      $kw = $1;
    } else {
      next;
    }
    if ($col[2] eq "") {
      next;
    }
    $targ{$kw} = $col[2];
  }
  close(BSUM);

  $line = <STDIN>;
  chomp($line);
  print "$line,unnorm_score,targ\n";
  while (<STDIN>) {
    chomp;
    my @col = split(/,/, $_);
    my $key = "$col[3] $col[1] $col[7]";
    print "$_,";
    if (defined($unnorm{$key})) {
      print $unnorm{$key};
    }
    if (defined($targ{$col[3]})) {
      print ",$targ{$col[3]}";
    } else {
      print ",0";
    }
    print "\n";
  }' > $kwsdir/alignment-ext.csv

# append posting list to textgrids, with kws result specified by $kwsdir
if [ ! -f $kwsdir/view/.done.wrong2textgrids ]; then
  mkdir -p $kwsdir/view/wrong
  for file in $data_dir/view/textgrids/*; do
    audio_key=`basename $file |  grep -Po '^.*(?=\.textgrid)'`
    new_tier_labeled_seg="`sed '1d' $kwsdir/alignment-ext.csv | grep $audio_key | grep -P '(YES,FA)|(NO,MISS)' |\
      cut -d ',' -f 4,5,8-14 | awk -F, '{print $3"\t"$4"\t"$1"("$2") "$5", "$6","$7","$8"("$9")"}' | sort -n -k 1 |\
      awk -F "\t" 'BEGIN{tend=0} {
        if ($1>=tend) {
          if (tend > 0) {
            print tbeg"\t"tend"\t"text;
          }
          tbeg=$1;
          tend=$2;
          text=$3;
        } else {
          text=text" | "$3;
          if ($2 > tend) {
            tend = $2;
          }
        }
      } END { if (tend > 0) { print tbeg"\t"tend"\t"text; } }'`"
    append_tier $file "KWS wrong" "$new_tier_labeled_seg" > $kwsdir/view/wrong/`basename $file`
  done 
  touch $kwsdir/view/.done.wrong2textgrids
fi
if [ ! -f $kwsdir/view/.done.right_wrong2textgrids ]; then
  mkdir -p $kwsdir/view/right_wrong
  for file in $kwsdir/view/wrong/*; do
    audio_key=`basename $file |  grep -Po '^.*(?=\.textgrid)'`
    new_tier_labeled_seg="`sed '1d' $kwsdir/alignment-ext.csv | grep $audio_key | grep -P 'YES,CORR' |\
      cut -d ',' -f 4,5,8-14 | awk -F, '{print $3"\t"$4"\t"$1"("$2") "$5", "$6","$7","$8"("$9")"}' | sort -n -k 1 |\
      awk -F "\t" 'BEGIN{tend=0} {
        if ($1>=tend) {
          if (tend > 0) {
            print tbeg"\t"tend"\t"text;
          }
          tbeg=$1;
          tend=$2;
          text=$3;
        } else {
          text=text" | "$3;
          if ($2 > tend) {
            tend = $2;
          }
        }
      } END { if (tend > 0) { print tbeg"\t"tend"\t"text; } }'`"
    append_tier $file "KWS right" "$new_tier_labeled_seg" > $kwsdir/view/right_wrong/`basename $file`
  done 
  touch $kwsdir/view/.done.right_wrong2textgrids
fi


#    item [1]:
#        class = "IntervalTier" 
#        name = "speech" 
#        xmin = 0 
#        xmax = 599.29 
#        intervals: size = 1041 
#        intervals [1]:
#            xmin = 7.14 
#            xmax = 7.56 
#            text = "ơi" 

     
#if [ ! -d $uttwavdir ]; then
#    echo "[WARN] Utterance wav dir not exists."
#else
#    #$cmd JOB=1:$nj $dir/view/log/ln_utt_wav.JOB.log \   not work, why cat output into log??
#    for JOB in `seq $nj`; do
#      cat $data/split$nj/$JOB/text | awk '{printf "%s\n",$1;}' | \
#        while read line; do
#          if [ ! -f "$uttwavdir/$line.wav" ]; then
#              echo "[WARN] Utterance file $line.wav not exists. Run split2uttwavs.pl to make the soft link valid."
#          fi
#          ln -sf $uttwavdir/$line.wav $dir/view/utts/$JOB/;
#        done
#    done
#fi
#

#$cmd JOB=1:$nj $kwsdir/view/log/praat_converter.JOB.log \
#  PraatConverter $dir/view/ali.JOB.gz.mlf.word $dir/view/utts/JOB



#    item [1]:
#        class = "IntervalTier" 
#        name = "speech" 
#        xmin = 0 
#        xmax = 599.29 
#        intervals: size = 1041 
#        intervals [1]:
#            xmin = 7.14 
#            xmax = 7.56 
#            text = "ơi" 

     
#if [ ! -f $data_dir/view/.done.seg2textgrids ]; then

#if [ ! -d $uttwavdir ]; then
#    echo "[WARN] Utterance wav dir not exists."
#else
#    #$cmd JOB=1:$nj $dir/view/log/ln_utt_wav.JOB.log \   not work, why cat output into log??
#    for JOB in `seq $nj`; do
#      cat $data/split$nj/$JOB/text | awk '{printf "%s\n",$1;}' | \
#        while read line; do
#          if [ ! -f "$uttwavdir/$line.wav" ]; then
#              echo "[WARN] Utterance file $line.wav not exists. Run split2uttwavs.pl to make the soft link valid."
#          fi
#          ln -sf $uttwavdir/$line.wav $dir/view/utts/$JOB/;
#        done
#    done
#fi
#

#$cmd JOB=1:$nj $kwsdir/view/log/praat_converter.JOB.log \
#  PraatConverter $dir/view/ali.JOB.gz.mlf.word $dir/view/utts/JOB

