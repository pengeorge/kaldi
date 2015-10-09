#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;

my $Usage = <<EOU;
  Usage: $0 <input-lexicon> <output-lm>
    --cutoff : subword with atoms fewer than this would be ignored (int, default = 3)
EOU

my $cutoff = 3;
GetOptions(
  'cutoff=i' => \$cutoff
);

if (@ARGV != 2) {
  die $Usage;
}

my $inlex = shift @ARGV;
my $outlm = shift @ARGV;

open(IN, "<$inlex") or die "Cannot open input lexicon $inlex\n";

print STDERR "Reading lexicon\n";
my %lex;
my %existed_atoms;
while (<IN>) {
  chomp;
  my @col = split(/\t/, $_);
  my $word = shift @col;
  my $pron_weight = 1 / (scalar @col);
  while (my $pron = shift @col) {
    my @atoms = split(/ \. | # /, $pron);  # split by seperator
    my @filtered_atoms;
    foreach my $atom (@atoms) {
      $atom =~ s/" //g;
      $atom =~ s/^\s*//;
      $atom =~ s/\s*$//;
      $atom =~ s/ /-/g;
      $existed_atoms{$atom} = 1;
      push(@filtered_atoms, $atom);
    }
    push(@{$lex{$word}}, [\@filtered_atoms, $pron_weight]);
    #print $lex{$word}->[0][1]."\n"; # get weight
    #print $lex{$word}->[0][0][1]."\n"; # get second atom of first pron
  }
}
close(IN);
print STDERR "# Atom = ".(scalar keys %existed_atoms)."\n";

print STDERR "Counting subwords\n";
my %subcnt;
my %sublen;
foreach my $word (keys %lex) {
  foreach my $pron (@{$lex{$word}}) {
    my $weight = $pron->[1];
    my @atoms = @{$pron->[0]};
    for (my $i = 0; $i < @atoms; $i++) {
      my $sub = $atoms[$i];
      for (my $j = $i; $j < @atoms; $j++) {
        #my $sub = join(".", @atoms[$i..$j]);
        if ($j > $i) {
          $sub .= ".".$atoms[$j];
        }
        if (!defined($subcnt{$sub})) {
          $subcnt{$sub} = 0;
          $sublen{$sub} = $j - $i + 1;
        }
        $subcnt{$sub}++;
      }
    }
  }
}

my %PrSub;
my %logPrSub;
my $totalPr = 0;
foreach my $sub (keys %subcnt) {
  # Ignore the subwords with more than one atom
  #   appearing fewer than $cutoff
  if ($sublen{$sub} > 1 && $subcnt{$sub} < $cutoff) {
    next;
  }
  # TODO different initialization methods will be tested here
  $PrSub{$sub} = $subcnt{$sub} * (2 ** ($sublen{$sub} - 1) );
  $totalPr += $PrSub{$sub};
  $logPrSub{$sub} = log($PrSub{$sub});
}
my $logTotalPr = log($totalPr);
my $log10 = log(10);
foreach my $sub (keys %PrSub) {
  $logPrSub{$sub} = ($logPrSub{$sub} - $logTotalPr) / $log10;
}



#foreach my $sub (sort {$PrSub{$b}<=>$PrSub{$a}} keys %PrSub) {
#  print "$sub\t$subcnt{$sub}\t$PrSub{$sub}\t$logPrSub{$sub}\n"
#}

open(OUT, ">$outlm") or die "Cannot open output LM $outlm\n";

print OUT "\\data\\\n";
print OUT "ngram 1=".(scalar keys %logPrSub)."\n";
print OUT "\n";
print OUT "\\1-grams:\n";
foreach my $sub (sort keys %logPrSub) {
  printf OUT "%.6f\t$sub\n", $logPrSub{$sub};
}
print OUT "\n";
print OUT "\\end\\\n";
close(OUT);


