#!/usr/bin/perl
use strict;
my $line = 0;
while (<>) {
  chomp;
  $line++;
  if ($line % 3 != 1) {
    next;
  }
  my @col = split(/ +/, $_);
  my $key = shift @col;
  print "$key\t";
  my $boundary = 0;
  my $labelSeq = '';
  my $seqLen = 0;
  foreach (@col) {
    if ( $_ eq '[') {
      $boundary = 1;
    } elsif (/\d+/) {
      $seqLen++;
      if ($boundary) {
        $labelSeq .= "1 ";
        $boundary = 0;
      } else {
        $labelSeq .= "0 ";
      }
    }
  }
  $labelSeq =~ s/ $//;
  $labelSeq =~ s/^1 /0 /;
  print "$seqLen\t$labelSeq\n";
}
