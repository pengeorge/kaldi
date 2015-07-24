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
Usage: merge_splitted_kwslist.pl [options] <kwslists> <merged_kwslist_out|-> <number-of-jobs>
 e.g.: merge_splitted_kwslist.pl kwslist.JOB.xml merged_kwslist.xml 96


EOU

my $kwlist_filename="";
#GetOptions('kwlist-filename=s'    => \$kwlist_filename);

if (@ARGV != 3) {
  die $Usage;
}

# Workout the input/output source
my $kwslists_pattern = shift @ARGV;
my $merged_kwslist_out = shift @ARGV;
my $nj = shift @ARGV;


if ($kwslists_pattern !~ m/JOB/) {
  die "The argument 'kwslist pattern' should contain 'JOB'.\n";
}

my %kwlist1;
my $f = $kwslists_pattern;
$f =~ s/JOB/1/g;
my $KWS1 = XMLin($f, 'ForceArray'=>1);
# Now work on the kwslist
foreach my $kwentry (@{$KWS1->{detected_kwlist}}) {
  $kwlist1{$kwentry->{kwid}} = 1;
}

#print "Merging ";
for my $k (2..$nj) {
  my $f = $kwslists_pattern;
  $f =~ s/JOB/$k/g;
  my $KWS2 = XMLin($f, 'ForceArray'=>1);
  #print " $k";
  if (!defined($KWS2->{detected_kwlist})) { # if kwslist is empty.
    next;
  }
  foreach my $kwentry (@{$KWS2->{detected_kwlist}}) {
    if (defined($kwlist1{$kwentry->{kwid}})) {
      die "Error: results of $kwentry->{kwid} exists!";
    }
    push(@{$KWS1->{detected_kwlist}}, $kwentry);
  }
}
#print "\n";
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
