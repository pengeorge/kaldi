#!/usr/bin/perl
use strict;
if ($#ARGV != 1 && $#ARGV != 2) {
    die "Usage: $0 phone-list phone-map-file [romanized-or-not,default:false]\n"
}
open(PHO, "$ARGV[0]") or die "Cannot open $ARGV[0]\n";
my %phone;
my $romanized = 'false';
if ($#ARGV == 2) {
    $romanized = $ARGV[2];
}
while (<PHO>) {
    chomp;
    $phone{$_} = 1;
}
for (('.','"','#','%')) {
    $phone{$_} = 1;
}

open(PM, "$ARGV[1]") or die "Cannot open $ARGV[1]\n";
while (<PM>) {
  chomp;
  my @col = split(/[\t ]/, $_);
  my $p = shift @col;
  if (!defined($phone{$p})) {
    my $to_be_included = 1;
    foreach (@col) {
      if (!defined($phone{$_})) {
        $to_be_included = 0;
        last;
      }
    }
    if ($to_be_included == 1) {
      $phone{$p} = 1;
    }
  }
}
while (<STDIN>) {
    chomp;
    my @col = split(/\t/, $_);
    my $word = shift @col;
    if ($romanized eq 'true') {
        shift @col;
    }
    my @usefulProns;
    foreach my $pron (@col) {
        my @p = split(/ /, $pron);
        my $use = 1;
        foreach (@p) {
            if (!defined($phone{$_})) {
                $use = 0;
                print STDERR "$word\t$_\t$pron\n";
                last;
            }
        }
        if ($use) {
            push(@usefulProns, $pron);
        }
    }
    if (@usefulProns > 0) {
        print "$word\t".join("\t", @usefulProns)."\n";
    }
}
