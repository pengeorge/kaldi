#!/usr/bin/perl

# Copyright 2012  Johns Hopkins University (Author: Guoguo Chen)
# Support several easy normalization method (chenzp, Mar 6, 2014)
# Apache 2.0.
#
use strict;
use warnings;
use Getopt::Long;
use XML::DOM;

my $Usage = <<EOU;
This script reads the kwslist.xml (typically unnormalized) and outputs estimated term frequency for each word in each document.

Usage: $0 [options] <fullvocab_kwslist_in|-> <df_in> <est_tf_out> <est_tfidf_out|->
 e.g.: $0 --flen=0.01 --duration=1000 --segments=data/eval/segments
                              --normalize=true fullvocab_kws_11/kwslist.unnormalized.xml data/train/df.txt fullvocab_kws_11/tf.txt fullvocab_kws_11/tfidf.txt

Allowed options:
  --Ntrue-scale               : Keyword independent scale factor for Ntrue  (float,   default = 1.0)
  --verbose                   : Verbose level (higher --> more kws section) (integer, default 0)

EOU

my $verbose = 0;
my $threshold = 0.001;
my $lexicon = "";
my $alpha = 1.0;
GetOptions(
  'verbose=i'         => \$verbose,
  'lexicon=s' => \$lexicon,
  'alpha=f' => \$alpha
);

if (@ARGV != 4) {
  die $Usage;
}

# Get parameters
my $filein = shift @ARGV;
my $filedf = shift @ARGV;
my $filetf = shift @ARGV;
my $fileout = shift @ARGV;

# Get input source
my $source = "";
if ($filein eq "-") {
  $source = "STDIN";
  die "Standard input not supported.\n";
} else {
  open(I, "<$filein") || die "$0: Fail to open input file $filein\n";
  $source = "I";
}

my %wordlen;
my $avgLen = 0;
if ($lexicon ne "") {
  open(LEX, "<$lexicon") || die "$0: Fail to open lexicon file $lexicon\n";
  while (<LEX>) {
    chomp;
    my @col = split(/ /, $_);
    if ($col[0] !~ m/^#/ && $col[0] !~ m/^</) {
      $wordlen{$col[0]} = @col - 2;
      $avgLen += $wordlen{$col[0]};
    }
  }
  $avgLen /= scalar keys %wordlen;
  close(LEX);
}

open(DF, "<$filedf") || die "$0: Fail to open df file $filedf\n";

my @widx2df;
my %wid2idx;
my @widx2text;
my $docnum = <DF>;
chomp($docnum);
while (<DF>) {
  chomp;
  my @col = split(/\t/, $_);
  $widx2df[$col[1]] = $col[3];
  $wid2idx{$col[2]} = $col[1];
  $widx2text[$col[1]] = $col[0];
}

my $wordnum = scalar keys %wid2idx;
my %tfidf;

print STDERR "Reading kwslist\n";
my $parser = XML::DOM::Parser->new();
my $doc = $parser->parsefile("$filein");
my $root = $doc->getDocumentElement();


# Processing
my $kwlist_filename = $root->getAttribute('kwlist_filename');
my $language = $root->getAttribute('language');
my $system_id = $root->getAttribute('system_id');

foreach my $detected_kwlist ($root->getElementsByTagName("detected_kwlist")) {
  my $search_time = $detected_kwlist->getAttribute('search_time');
  my $kwid = $detected_kwlist->getAttribute('kwid');
  my $oov_count = $detected_kwlist->getAttribute('oov_count');

  my $wid = $kwid;
  $wid =~ s/^KWID\d+-FULLVOCAB-0*(\d+)$/$1/;
  my $widx = $wid2idx{$wid};

  print STDERR "process $kwid, wid:$wid, widx:$widx\n";
  foreach my $kw ($detected_kwlist->getElementsByTagName("kw")) {
    my $utter = $kw->getAttribute('file');
    #my $chnl = $kw->getAttribute('channel');
    #my $start = $kw->getAttribute('tbeg');
    #my $dur = $kw->getAttribute('dur');
    my $score = $kw->getAttribute('score');
    #my $decision = $kw->getAttribute('decision');
    my $d = $utter; # document
    if (!defined($tfidf{$d})) {
      @{$tfidf{$d}} = (0)x$wordnum;
    }
    $tfidf{$d}[$widx] += $score;
  }
}

print STDERR "Outputing term frequency\n";

# Output tf
open(TFO, ">$filetf") || die "$0: Fail to open output file $filetf\n";
foreach my $d (sort keys %tfidf) {
  print TFO "$d";
  for (my $i = 0; $i < $wordnum; $i++) {
    if ($lexicon ne "") {
      $tfidf{$d}[$i] = $tfidf{$d}[$i] ** ($alpha * $avgLen / $wordlen{$widx2text[$i]});
    }
    if ($tfidf{$d}[$i] > $threshold) {
      print TFO " $i:$tfidf{$d}[$i]";
    } else {
      $tfidf{$d}[$i] = 0;
    }
  }
  print TFO "\n";
}
close(TFO);

print STDERR "Outputing tf-idf\n";
my $output = '';
my $log2 = log(2);
my $logN = log($docnum) / $log2;
foreach my $d (sort keys %tfidf) {
  $output .= "$d";
  for (my $i = 0; $i < $wordnum; $i++) {
    if ($tfidf{$d}[$i] != 0) {
      my $idf;
      if ($widx2df[$i] == 0) {
        $idf = $logN;
      } else {
        $idf = log($docnum / $widx2df[$i]) / $log2;
      }
      $tfidf{$d}[$i] *= $idf;
      if ($tfidf{$d}[$i] > $threshold) {
        $output .= " $i:$tfidf{$d}[$i]";
      }
    }
  }
  $output .= "\n";
}

if ($filein  ne "-") {close(I);}
if ($fileout eq "-") {
    print $output;
} else {
  open(O, ">$fileout") || die "$0: Fail to open output file $fileout\n";
  print O $output;
  close(O);
}
