#!/usr/bin/perl
use strict;

my $labelFile = $ARGV[0];
open(LAB, "$labelFile") or die "Cannot open label file: $labelFile\n";

my $n = 0;
my @labs;
my $lab;
while (<STDIN>) {
  chomp;
  if (/\[/) {
    $n = 0;
    if (@labs == 0) {
      my $labelLine = <LAB>;
      chomp($labelLine);
      my @col = split(/\t/, $labelLine);
      my $num = $col[1];
      $labelLine = $col[2];
      @labs = split(/ /, $labelLine);
      if ($num != @labs) {
        die;
      }
    }
    $lab = shift @labs;
    if ($lab == 0) {
      print "-1";
    } elsif ($lab == 1) {
      print "+1";
    } else {
      die;
    }
  } else {
    my $feats = $_;
    $feats =~ s/^ +//;
    $feats =~ s/ +$//;
    my @col = split(/ +/, $feats);
    foreach (@col) {
      $n++;
      if (/^\d+/) {
        print " $n:+$_";
      } elsif (/^\-\d+/) {
        print " $n:$_";
      } elsif (/\]/) {
        print "\n";
      }
    }
  }
}
close(LAB);
