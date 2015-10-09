#!/usr/bin/perl
use strict;
use Encode;

if ($#ARGV != 0) {
  die "Usage: $0 char_sampa_file\n"
}

my $char_sampa_file = $ARGV[0];

open(CHAR, "$char_sampa_file") or die;

my %chars;
while (<CHAR>) {
  chomp;
  if (-z $_) {
    next;
  }
  my @col = split(/\t/, $_);
  $col[0] =~ s/^\s*|\s*$//g;
  my @cs = split(//, decode('utf8',$col[0]));
  foreach (@cs) {
    $chars{$_} = 1;
  }
}

print STDERR "Only words containing only these characters would be kept:\n".encode('utf8', join(' ', keys %chars))."\n";

my %excChars;
my $saveNum = 0;
my $excNum = 0;
while (<STDIN>) {
  my $line = $_;
  chomp;
  if (-z $_) {
    next;
  }
  my @col = split(/\t/, $_);
  if (@col < 2) {
    die "in lexicon has something wrong\n";
  }
  my @charOfWord = split(//, decode('utf8', $col[0]));
  #print STDERR "$col[0] ".scalar @charOfWord."\n";
  my $native = 1;
  
  if (0) {
  foreach my $c (@charOfWord) {
    if (!defined($chars{$c})) {
      $native = 0;
      if (defined($excChars{$c})) {
        $excChars{$c}++;
      } else {
        $excChars{$c} = 1;
      }
      last;
    }
  }
  }

  my $tmp = decode('utf8', $col[0]);
  if ($tmp !~ /^[\x{0B80}-\x{0BFF}]+$/) {
    $native = 0;
  }
  if ($native) {
    print "$line";
    $saveNum++;
  } else {
    #print STDERR "Word $col[0] is exluded\n";
    $excNum++;
  }
}

foreach (keys %excChars) {
  print STDERR encode('utf8',$_)."\t$excChars{$_}\n";
}
print STDERR "$excNum excluded, $saveNum saved.\n";
