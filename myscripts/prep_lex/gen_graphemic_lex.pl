#!/usr/bin/perl

use strict;
use Encode;
use Getopt::Long;
my $phonemap="";
my $phoneset=""; # e.g. data/local/nonsilence_phones.txt
GetOptions(
  "phonemap=s" => \$phonemap,
  "phoneset=s" => \$phoneset
);

#The phonemap is in the form of "ph1=a b c;ph2=a f g;...."
my %phonemap_hash;
if ($phonemap) {
  $phonemap=join(" ", split(/\s+/, $phonemap));
  my @phone_map_instances=split(/;/, $phonemap);
  foreach my $instance (@phone_map_instances) {
    my ($phoneme, $tgt) = split(/=/, $instance);
    $phoneme =~ s/^\s+|\s+$//g;
    $tgt =~ s/^\s+|\s+$//g;
    #print "$phoneme=>$tgt\n";
    my @tgtseq=split(/\s+/,$tgt);
    $phonemap_hash{$phoneme} = [];
    push @{$phonemap_hash{$phoneme}}, @tgtseq;
  }
}

my %phoneset_hash;
if ($phoneset) {
  open(SET, "$phoneset") or die "Cannot open phone set file $phoneset\n";
  while (<SET>) {
    chomp;
    $phoneset_hash{$_} = 1;
  }
  close(SET);
}

while (<STDIN>) {
  chomp;
  my @col = split(/\t/, $_);
  my $line = $col[0]."\t";
  my @graphemes = split(//, decode('utf8', $col[0]));
  for (my $k = 0; $k < @graphemes; $k++) {
    $graphemes[$k] = encode('utf8', $graphemes[$k]);
  }
  if ($phonemap) {
    for (my $k = 0; $k < @graphemes; $k++) {
      if (defined($phonemap_hash{$graphemes[$k]})) {
        $graphemes[$k] = join(" ", @{$phonemap_hash{$graphemes[$k]}});
      }
    }
    @graphemes = split(/ /, join(" ", @graphemes));
  }
  foreach my $l (@graphemes) {
    if ($l ne '-' && $l ne '_' && $l ne "'") {
      if ($phoneset && !defined($phoneset_hash{$l})) {
        die "Failed generating graphemic lexicon, out-of-set phoneme found: $l\n";
      }      
      $line .= "$l ";
      if ($l !~ m/[A-Za-z]/) {
        print STDERR "Non-latin letter: $l\n";
      }
    }
  }
  $line =~ s/\s*$//;
  print "$line\n";
}

