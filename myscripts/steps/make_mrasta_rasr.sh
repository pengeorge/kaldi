#!/bin/bash

nj=24
cmd=run.pl
mrasta_config=./rasr_conf/feature-extraction.mrasta.config
shared_var_config=./rasr_conf/shared.config
cleanup=true

echo "$0 $@"  # Print the command line for logging
if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 2 ]; then
  echo "usage: make_mrasta_rasr.sh [options] <kaldi-data-dir> <exp-dir>"
  echo "options: "
fi

indir=$1
expdir=$2

data_type=`basename $indir`

if [ ! -d $indir/split${nj} ]; then
  echo "Directory $indir/split${nj} does not exist. You should give a matched nj."
  exit 1;
fi

adir=$expdir/audio
mkdir -p $adir

cp $mrasta_config ${expdir}/
cp $shared_var_config ${expdir}/var.config
echo "DATA_DIR = $expdir" >> ${expdir}/var.config
echo "CORPUS = ${expdir}/corpus.gz" >> ${expdir}/var.config
echo "AUDIO_DIR = ${adir}" >> ${expdir}/var.config
echo "LOG_DIR = $expdir/log" >> ${expdir}/var.config
echo "DESCRIPTION = feature-extraction.mrasta.${data_type}" >> ${expdir}/var.config


if [ ! -f $expdir/.done.audio ]; then
  echo ======================================
  echo "Save audio as wav file in $adir"
  echo ======================================
  mkdir -p $expdir/log

  $cmd JOB=1:${nj} $expdir/log/convert2wav.JOB.log \
   '.' '<(' awk '{printf $2; for(i=3;i<NF;i++){ printf " "$i;} printf(" > '$adir'/%s.wav\n",$1);}' $indir/split${nj}/JOB/wav.scp ')' \
   || exit 1;
  touch $expdir/.done.audio
fi

if [ ! -f $expdir/.done.corpus ]; then
  echo ======================================
  echo "Generate corpus.gz in $expdir for RWTH ASR System"
  echo ======================================
  cat $indir/segments | perl -e '
    print "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    print "<corpus name=\"'${data_type}'\">\n";
    my $audio="";
    while (<STDIN>) {
      chomp;
      @col = split(/ /, $_);
      if ($col[1] ne $audio) {
        if ($audio ne "") {
          print "  </recording>\n";
        }
        $audio = $col[1];
        print "  <recording audio=\"$audio.wav\" name=\"$audio\">\n";
      }
      print "    <segment start=\"$col[2]\" end=\"$col[3]\" name=\"$col[0]\">\n";
      print "    </segment>\n";
    }
    if ($audio ne "") {
      print "  </recording>\n";
    }
    print "</corpus>\n";
    ' | gzip > ${expdir}/corpus.gz
  touch $expdir/.done.corpus
fi

echo ======================================
echo "Extracting MRASTA features for $expdir"
echo ======================================
#$cmd JOB=1:$nj $expdir/log/make_mrasta_rasr.JOB.log \
  feature-extraction --config=${expdir}/`basename $mrasta_config`

if $cleanup; then
  echo "Clean up audio files"
  rm $adir/*
  rm $expdir/.done.audio
fi
