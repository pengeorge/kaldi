#/usr/bin/perl
use strict;
use Encode;

if ($#ARGV != 0) {
    die "Usage: $0 <string>";
}
my $str = $ARGV[0];
my @arr = split(//, decode('utf8', $str));
my $num = 2**(@arr - 1);

for (0..$num-1) {
    my $r = $_;
    my $s;
    for (0..@arr-1) {
        $s .= $arr[$_];
        if ($r & 1) {
            $s .= " ";
        }
        $r >>= 1;
    }
    print encode('utf8', $s)."\n";
}
