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
This script reads the unnormalized kwslist.xml and outputs estimated Ntrue for each word.

Usage: $0 [options] <fullvocab_keywords_list> <fullvocab_kwslist_in|-> <est_Ntrue_out>
 e.g.: dev10h.pem/fullvocab_kws/keywords.txt fullvocab_kws_11/kwslist.unnormalized.xml fullvocab_kws_11/Ntrue.txt

Allowed options:
  --verbose                   : Verbose level (higher --> more kws section) (integer, default 0)

EOU

my $verbose = 0;
GetOptions(
  'verbose=i'         => \$verbose,
);

if (@ARGV != 3) {
  die $Usage;
}

# Get parameters
my $filekwlist = shift @ARGV;
my $filekwslist = shift @ARGV;
my $fileoutNtrue = shift @ARGV;


open(KW, "$filekwlist") or die "Cannot open KW list file $filekwlist\n";
print STDERR "Reading kwlist\n";
my %kwid2kw;
while (<KW>) {
  chomp;
  my @col = split(/\t/, $_);
  $kwid2kw{$col[0]} = $col[1];
}
close(KW);

print STDERR "Reading kwslist\n";
my $parser = XML::DOM::Parser->new();
my $doc = $parser->parsefile("$filekwslist");
my $root = $doc->getDocumentElement();

my %Ntrue;
my %max_score;
my %candNum;
# Processing
my $kwlist_filename = $root->getAttribute('kwlist_filename');
my $language = $root->getAttribute('language');
my $system_id = $root->getAttribute('system_id');

foreach my $detected_kwlist ($root->getElementsByTagName("detected_kwlist")) {
  my $search_time = $detected_kwlist->getAttribute('search_time');
  my $kwid = $detected_kwlist->getAttribute('kwid');
  my $oov_count = $detected_kwlist->getAttribute('oov_count');

  if (!defined($Ntrue{$kwid})) {
    $Ntrue{$kwid} = 0;
    $max_score{$kwid} = -1;
    $candNum{$kwid} = 0;
  }
  #my $wid = $kwid;
  #$wid =~ s/^KWID\d+-FULLVOCAB-0*(\d+)$/$1/;

  foreach my $kw ($detected_kwlist->getElementsByTagName("kw")) {
    my $utter = $kw->getAttribute('file');
    #my $chnl = $kw->getAttribute('channel');
    #my $start = $kw->getAttribute('tbeg');
    #my $dur = $kw->getAttribute('dur');
    my $score = $kw->getAttribute('score');
    #my $decision = $kw->getAttribute('decision');
    #my $d = $utter; # document
    #if (!defined($tfidf{$d})) {
    #  @{$tfidf{$d}} = (0)x$wordnum;
    #}
    #$tfidf{$d}[$widx] += $score;
    $Ntrue{$kwid} += $score;
    if ($score > $max_score{$kwid}) {
      $max_score{$kwid} = $score;
    }
    $candNum{$kwid}++;
  }
}

print STDERR "Outputing estimated N_true\n";

# Output Ntrue
open(NTRUE, ">$fileoutNtrue") || die "$0: Fail to open output file $fileoutNtrue\n";
foreach my $kwid (sort {$Ntrue{$b}<=>$Ntrue{$a}}  keys %Ntrue) {
  print NTRUE "$kwid\t$kwid2kw{$kwid}\t$Ntrue{$kwid}\t$max_score{$kwid}\t$candNum{$kwid}\n";
}
close(NTRUE);

