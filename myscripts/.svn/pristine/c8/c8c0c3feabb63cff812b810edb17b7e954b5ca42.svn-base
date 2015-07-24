#!/bin/perl -w
use strict;
use List::Util qw/max min/;

my $usage = "USAGE: $0 <ali-hyp> <ali-ref> <phone-confusion> [<ref-split-num>]\n  use \* in ali-ref to represent split number\n";
if ($#ARGV != 3 && $#ARGV != 2) {
    die $usage;    
}

my $hyp = shift @ARGV;
my $ref = shift @ARGV;
my $out = shift @ARGV;
my $nref = shift @ARGV;

my @refs;
if ($ref =~ /\*/) {
    if ( -z $nref ) {
        die $usage;
    } elsif ( $nref < 0 ) {
        die "[ERROR] ref-split-num should be greater than 0.\n";
    }
    for ((1..$nref)) {
        my $reffile = $ref;
        $reffile =~ s/\*/$_/;
        push(@refs, $reffile);
    }
    #print "refs: @refs\n";
} else {
    push(@refs, $ref);
}

open(HYP, "$hyp") or die "Cannot open hyp file: $hyp\n";
my %hyputts;
my $utt;
while (<HYP>) {
    chomp;
    if (/^\"(.*)\"$/) {
        $utt = $1;
        $hyputts{$utt} = ();
    } elsif (/^(\d+) (\d+) (.*)$/) {
        my @tmp = ($3, $1, $2);
        push(@{$hyputts{$utt}}, \@tmp);
    }
}
close(HYP);

my %refutts;
for my $file (@refs) {    
    open(REF, "$file") or die "Cannot open ref file: $file\n";
    while (<REF>) {
	    chomp;
	    if (/^\"(.*)\"$/) {
	        $utt = $1;
	        $refutts{$utt} = ();
	    } elsif (/^(\d+) (\d+) (.*)$/) {
            my @tmp = ($3, $1, $2);
	        push(@{$refutts{$utt}}, \@tmp);
	    }
    }
}

#$utt='sw02028-A_036850-037001';
my %pcm;
for my $utt (sort keys %hyputts) {
    if (!defined($refutts{$utt})) {
        print "[WARNING] utterance '$utt' not found in REF (maybe FA failed).\n";
        next;
    }
    my @h = @{$hyputts{$utt}};
    my @r = @{$refutts{$utt}};
    my @d;
    my @p;
    $d[0][0] = 0;
    for my $j ((1..scalar(@r))) {
        $d[0][$j] = $d[0][$j-1] + 1;
        my @tmp = (0,$j-1);
        $p[0][$j] = \@tmp;
    }
    for my $i ((1..scalar(@h))) {
        $d[$i][0] = $d[$i-1][0] + 1;
        my @tmp = ($i-1,0);
        $p[$i][0] = \@tmp;
    }
    # print STDERR scalar @h." ".scalar @r."\n";
    for my $i ((1..scalar @h)) {
        for my $j ((1..scalar @r)) {
            #my $tmp = $h[$i-1][1];
            #print "$tmp\n";
            #die;
            # print STDERR "$i: $h[$i-1][0]  $j: $r[$j-1][0] \n";
            my $sub = $d[$i-1][$j-1];
            if ($h[$i-1][0] ne $r[$j-1][0]) {
                if (($h[$i-1][1] >= $r[$j-1][2]
                    || $h[$i-1][2] <= $r[$j-1][1])) {
                    $sub += 10;
                } else {
                    my $p1 = $h[$i-1][0];
                    my $p2 = $r[$j-1][0];
                    $p1 =~ s/_.$//;
                    $p2 =~ s/_.$//;
                    if ($p1 eq $p2) {
                        $sub += 0.5;
                    } else {
                        $sub++;
                    }
                }
            }
            my $del = $d[$i][$j-1] + 1;
            my $ins = $d[$i-1][$j] + 1;
            if ($ins <= $del && $ins <= $sub) { # ins
                $d[$i][$j] = $ins;
                my @tmp = ($i-1,$j);
                $p[$i][$j] = \@tmp;
                #print "($i-1,$j) -> ($i,$j)\n";
            } elsif ($del <= $sub) {    # del
                $d[$i][$j] = $del;
                my @tmp = ($i,$j-1);
                $p[$i][$j] = \@tmp;
                #print "($i,$j-1) -> ($i,$j)\n";
            } else {    #sub
                $d[$i][$j] = $sub;
                my @tmp = ($i-1,$j-1);
                $p[$i][$j] = \@tmp;
                #print "($i-1,$j-1) -> ($i,$j)\n";
            }
        }
    }
    if ($d[@h][@r] > 0) {
	    for my $i ((0..@h-1)) {
	        print "$h[$i][0] ";
	    }
	    print "\n";
	    for my $j ((0..@r-1)) {
	        print "$r[$j][0] ";
	    }
	    print "\n";
	    print "distantce is $d[@h][@r]\n";
    }
    my ($i,$j) = (scalar @h, scalar @r);
    while ($i != 0 || $j != 0) {
        #print "@{$p[$i][$j]}\n";
        my ($ii,$jj) = ($p[$i][$j][0],$p[$i][$j][1]);
        my $cmkey;
        if ($ii == $i) {
            print "[  Deletion  ] $r[$jj][0] -> <eps>\n";
            $cmkey = "$r[$jj][0] <eps>";
        } elsif ($jj == $j) {
            print "[ Insertion  ] <eps> -> $h[$ii][0]\n";
            $cmkey = "<eps> $h[$ii][0]";
        } elsif ($h[$ii][0] ne $r[$jj][0]) {
            print "[Substitution] $r[$jj][0] -> $h[$ii][0]\n";
            $cmkey = "$r[$jj][0] $h[$ii][0]";
        }
        if (defined($cmkey)) {
            if (defined($pcm{$cmkey})) {
                $pcm{$cmkey}++;
            } else {
                $pcm{$cmkey} = 1;
            }
        }
        ($i,$j) = ($ii,$jj);
    }
}

open(OUT, ">$out") or die "Cannot open output phone confusion matrix file: $out\n";
for my $cmkey (sort keys %pcm) {
    print OUT "$cmkey $pcm{$cmkey}\n";
}
close(OUT);
print "Done.";

