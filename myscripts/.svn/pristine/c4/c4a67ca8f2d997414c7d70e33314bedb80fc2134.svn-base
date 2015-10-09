#!/bin/perl -w
use strict;
while (<>) {
    chomp;
    my $line = $_;
    my @col = split(/[ \t]/);
    my $word = shift @col;
    my $modified = 0;
    if (@col > 1) {
        if ($col[0] !~ /_B$/) {
            $col[0] =~ s/_.$/_B/;
            $modified = 1;
        }
        for (my $i=1; $i < @col-1; $i++) {
            if ($col[$i] !~ /_I$/) {
                $col[$i] =~ s/_.$/_I/;
                $modified = 1;
            }
        }
        if ($col[@col-1] !~ /_E$/) {
            $col[@col-1] =~ s/_.$/_E/;
            $modified = 1;
        }
    } elsif (@col == 1 && $col[0] !~ /_S$/) {
        $col[0] =~ s/_.$/_S/;
        $modified = 1;
    }
    if ($modified == 1) {
        my $newpron = join(' ', @col);
        print STDERR "$line --> $newpron\n";
        print "$word\t$newpron\n";
    } else {
        print "$line\n";
    }
}
