#!/usr/bin/perl
use strict;

print "#!MLF!#\n";
my $file = '';
my $last = 0;
while (<STDIN>) {
  chomp;
  my @col = split(/ /, $_);
  if ($col[1] ne $file) {
    if ($file ne '') {
      print ".\n";
    }
    $last = 0;
    $file = $col[1];
    print "\"${file}.lab\"\n";
  }
  my $start = $col[2] * 100;
  my $end = $col[3] * 100;
  if ($start > $last) {
    printf("%d %d sil\n", $last, $start);
  } elsif ($start < $last) {
    die "Something wrong: $start < $last\n";
  }
  printf("%d %d speech\n", $start, $end);
  $last = $end;
}
if ($file ne '') {
  print ".\n";
}

