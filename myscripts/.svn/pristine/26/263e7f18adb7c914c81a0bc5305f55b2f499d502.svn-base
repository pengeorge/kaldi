#!/usr/bin/perl
use strict;
if ($#ARGV != 0) {
  die "Usage: $0 in_kwslist\n  The subset key list is provided from STDIN,\n  the output kwslist is printed to STDOUT\n";
}
my $infile = shift @ARGV;
my %insubset = ();
while (<STDIN>) {
  chomp;
  $insubset{$_} = 1;
}
my $kw = "";
$insubset{$kw} = 1;
open(KWS, "$infile") or die "cannot open kwslist file: $infile\n";
while (my $line = <KWS>) {
  chomp($line);
  if ($line =~ m/detected_kwlist.*kwid="([^"]+)"/) {
    $kw = $1;
  }
  if ($insubset{$kw} == 1) {
    print "$line\n";
  }
  if ($line =~ /<\/detected_kwlist>/) {
    $kw = "";
  }
}
close(KWS);
