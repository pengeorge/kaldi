#!/usr/bin/perl
use strict;

if ($#ARGV != 1) {
    die "Usage: $0 <base-lexicon> <ext-lexicon>\n";
}

my $base = $ARGV[0];
my $ext = $ARGV[1];

open(BASE, "$base") or die "Cannot open base lexicon file: $base\n";
my %existed;
while (<BASE>) {
    chomp;
    my @col = split(/\t/, $_);
    $existed{$col[0]} = 1;
    print "$_\n";
}
close(BASE);

open(EXT, "$ext") or die "Cannot open ext lexicon file: $ext\n";
while (<EXT>) {
    chomp;
    my @col = split(/\t/, $_);
    if (defined($existed{$col[0]})) {
        print STDERR "[WARNING] word $col[0] exists in the base lexicon\n";
    } else {
        print "$_\n";
    }
}
close(EXT);
