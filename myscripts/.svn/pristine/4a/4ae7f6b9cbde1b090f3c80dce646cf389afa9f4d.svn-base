#!/usr/bin/perl

# Copyright 2014  Tsinghua University (Author: Zhipeng Chen)
# Apache 2.0.
#

use strict;
use warnings;
use Getopt::Long;
use XML::Simple;
use Data::Dumper;
use File::Basename;

sub mysort {
  if ($a->{kwid} =~ m/[0-9]+$/ and $b->{kwid} =~ m/[0-9]+$/) {
    ($a->{kwid} =~ /([0-9]*)$/)[0] <=> ($b->{kwid} =~ /([0-9]*)$/)[0]
  } else {
    $a->{kwid} cmp $b->{kwid};
  }
}

my $Usage = <<EOU;
Usage: fix_kwslist.pl [options] <kwslist_in1|-> <kwslist_in2|-> <merged_kwslist_out|->
 e.g.: fix_kwslist.pl kwslist_iv.xml kwslist_oov.xml merged_kwslist.xml

Allowed options:
  --kwlist-filename       : Kwlist filename with version info     (string, default = "")

EOU

my $kwlist_filename="";
GetOptions('kwlist-filename=s'    => \$kwlist_filename);

if (@ARGV != 3) {
  die $Usage;
}

# Workout the input/output source
my $kwslist_in1 = shift @ARGV;
my $kwslist_in2 = shift @ARGV;
my $merged_kwslist_out = shift @ARGV;

my $KWS1 = XMLin($kwslist_in1);
my $KWS2 = XMLin($kwslist_in2);

my %kwlist1;
my %kwlist2;
# Now work on the kwslist
foreach my $kwentry (@{$KWS1->{detected_kwlist}}) {
  $kwlist1{$kwentry->{kwid}} = 1;
}
foreach my $kwentry (@{$KWS2->{detected_kwlist}}) {
  if (defined($kwlist1{$kwentry->{kwid}})) {
    die "Error: results of $kwentry->{kwid} is in IV too!";
  }
  $kwentry->{oov_count} = 1;
  push(@{$KWS1->{detected_kwlist}}, $kwentry);
}

my @sorted = sort mysort @{$KWS1->{detected_kwlist}};
$KWS1->{detected_kwlist} = \@sorted;

my $xml = XMLout($KWS1, RootName => "kwslist", NoSort=>0);
if ($merged_kwslist_out eq "-") {
  print $xml;
} else {
  if (!open(O, ">$merged_kwslist_out")) {
    print "Fail to open output file: $merged_kwslist_out\n"; 
    exit 1;
  }
  print O $xml;
  close(O);
}
