#!/bin/perl -w

use strict;

my %map;
$map{'<no-speech>'} = '!sil';

$map{'<int>'} = '[noise]';
$map{'<click>'} = '[noise]';
$map{'<ring>'} = '[noise]';

$map{'<laugh>'} = '[laughter]';

$map{'<breath>'} = '[vocalized-noise]';
$map{'<cough>'} = '[vocalized-noise]';
$map{'<lipsmack>'} = '[vocalized-noise]';

$map{'()'} = '<unk>';
$map{'<foreign>'} = '<unk>';
$map{'<overlap>'} = '<unk>';

my $sent;
my $time;
while (<STDIN>) {
    chomp;
    my @col = split();
    print shift @col;
    for (@col) {
        my $w;
        my $bra = 0;
        if ($_ =~ s/^\((.*)\)$/$1/) {
            $bra = 1;
        }
        if (defined($map{$_})) {
            $w = $map{$_};
        } elsif ($_ =~ m/^\*(.*)\*$/) {
            $w = $1;
        } elsif ($_ !~ m/^<.*>$/) {
            $w = $_;
        }
        if (defined($w)) {
            if ($bra) {
                print " ($w)";
            } else {
                print " $w";
            }
        }
    }
    print "\n";
}

