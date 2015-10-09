#!/bin/perl -w

use strict;
use warnings;
use Getopt::Long;


my $romanized = "true";
my $stm_in;
my $stm_out;

GetOptions('romanized=s'     => \$romanized,
           'stm-in=s'     => \$stm_in,
           'stm-out=s'     => \$stm_out
);

if ($#ARGV != 3) {
    die "USAGE: $0 <original-lexicon> <word-to-subword-lexicon> <in-trans-dir> <out-trans-dir>\n  e.g. $0 in out .\n  mlf.phone-word file is read from STDIN";
}

print "$0 @ARGV\n";
my $lexfile = shift @ARGV;
my $w2sfile = shift @ARGV;
my $indir = shift @ARGV;
my $outdir = shift @ARGV;

my $do_stm = 'false';
if (defined($stm_in) && $stm_in ne '') {
  if (-e $stm_in) {
    if ($stm_out ne '') {
      $do_stm = 'true';
    }
  } else {
    die "[ERROR] input stm not exist.\n";
  }
}

print "Reading lexicon: $lexfile...\n";
my %lex;
my %rlex;
open(LEX, "$lexfile") or die "cannot open lexicon file $lexfile\n";
while (my $line = <LEX>) {
    chomp($line);
    my @pronseq = split(/\t/, $line);
    my $word = shift @pronseq;
    if ($romanized eq 'true') {
      shift @pronseq;
    }
    #$rlex{$pron} = $word;
    push(@{$lex{$word}}, @pronseq);
}
close(LEX);

print "Reading W2S lexicon: $w2sfile...\n";
my %w2s;
open(W2S, "$w2sfile") or die "cannot open word-to-subword lexicon file $w2sfile\n";
while (my $line = <W2S>) {
    chomp($line);
    my @pronseq = split(/\t/, $line);
    my $word = shift @pronseq;
    push(@{$w2s{$word}}, @pronseq);
}
close(W2S);
#open(PWMLF, "$odir/$out.mlf.phone-word") or die "cannot open phone-word mlf file $odir/$out.mlf.phone-word\n";
#open(WMLF, "$odir/$out.mlf.word") or die "cannot open word mlf file $odir/$out.mlf.word\n";

print "Reading MLF from STDIN...\n";
my %mlf;
my $putt;
while (<STDIN>) {
  chomp;
  if (/^#/) {
    next;
  } elsif (/^"(.*)_(\d+)"$/) {
    $putt = \@{$mlf{$1}{$2}};
    @$putt = ();
  } elsif (/^\.$/) {
  } else {
    my @col = split();
    shift @col; shift @col;
    if (@col == 1 && $col[0] eq 'SIL') {
      next;
    }
    push(@$putt, \@col);
  }
}

opendir(INDIR, "$indir") || die "cannot open dir $indir\n";
my @files = readdir INDIR;
closedir(INDIR);

if (! -d "$outdir") {
    mkdir("$outdir") or die "[ERROR] mkdir $outdir failed.";
}

my $oov_multi_pron_num = 0;
my $oov_num = 0;
my %trans;
my $ptrans;
print "Generating subword transcriptions in $outdir...\n";
for my $f (sort @files) {
  if ($f !~ /^BABEL_/) {
    next;
  }
  print "$f\n";
  open(F, "$indir/$f") || die "cannot open input file: $indir/$f\n";
  open(OF, ">$outdir/$f") || die "cannot open output file: $outdir/$f\n";
  $f =~ s/\.txt$//;
  %{$trans{$f}} = ();
  $ptrans = \%{$trans{$f}};
  my $ptransutt;
  $f =~ s/inLine$/A/;
  $f =~ s/outLine$/B/;
  $f =~ s/^BABEL_[^_]+_[^_]+_(\d+)_(\d+_\d+)_([A|B])$/$1_$3_$2/;
  my $f_in_mlf = 'true';
  if (!defined($mlf{$f})) {
    print STDERR "[WARNING] $f not defined in MLF, will use 1st pronunciation in the lexicon.\n";
    $f_in_mlf = 'false';
  }
  my $ln = 0;
  my $beg;
  my $putt;
  my $u_in_mlf = $f_in_mlf;
  while (<F>) {
    chomp;
    $ln ++;
    my $line = $_;
    if ($line =~ m/^\[/) {
      print OF "$_\n";
      if ($f_in_mlf eq 'true') {
        $beg = $line;
        $beg =~ s/^\[([\d\.]+)\]$/$1/;
        $ptrans->{$beg} = '';
        $ptransutt = \($ptrans->{$beg});
        $beg = sprintf("%06d", $beg*100);
        if (defined($mlf{$f}{$beg})) {
          $putt = \@{$mlf{$f}{$beg}};
          $u_in_mlf = 'true';
        } else {
          $u_in_mlf = 'false'
        }
      }
    } else {
      my $str = "";
      my @col = split(/ /, $line);
      my $wn = 0;
      for my $w (@col) {
        if ($w =~ m/<sta>/
          || $w =~ m/<female-to-male>/
          || $w =~ m/<male-to-female>/
          || $w =~ m/~/) {  # don't count these words, since they are removed in 'data/xxx/text'
          $str .= " $w";
        } else {
          $wn++;
          if ($w =~ m/<.*>/ || $w =~ m/\(\(\)\)/) {
            $str .= " $w";
          } elsif (!defined(@{$w2s{$w}})) {
            if ($w =~ /^\-/
              || $w =~ /\-$/) {
              $str .= " $w";
#            } elsif ($w =~ /^\*(.*)\*$/ && defined(@{$w2s{$1}})) {
#              $str .= " *$w2s{$1}[0]*";
            } elsif ($w =~ /^\*(.*)\*$/) {
              $str .= " $w";
            } else {
              print STDERR "Bad word: $w   '$f': line:$ln word:$wn \n";
              die;
            }
          } else {
            if ($f_in_mlf eq 'false' || $u_in_mlf eq 'false') {
              $str .= " $w2s{$w}[0]"; # pick the first one
            } else {
              my $subwordseq2replace = '';
              my $phoneseq = join(' ', @{$putt->[$wn-1]});
              $phoneseq =~ s/_[BIES] / /g;
              $phoneseq =~ s/_[BIES]$//;
              #print "  [MLF] $w --> $phoneseq\n";
              my $i = 0;
              for ($i=0; $i < @{$w2s{$w}}; $i++) {
                my $subwordseq = $w2s{$w}[$i];
                my $subword_phoneseq = $subwordseq;
                $subword_phoneseq =~ s/\-/ /g;
                #print "  [W2S] $w --> $subword_phoneseq\n";
                if ($subword_phoneseq eq $phoneseq) {
                  $subwordseq2replace = $subwordseq;
                  last;
                }
              }
              if ($subwordseq2replace eq '') {
                if ($phoneseq eq '<oov>') { # it's a OOV, should only happen in dev
                  $oov_num++;
                  if (@{$w2s{$w}} > 1) {
                    print "  [WARNING] OOV $w has ".@{$w2s{$w}}." prons, arbitrarily use the 0th one\n";
                    $oov_multi_pron_num++;
                  } else {
                    print "  OOV $w has only ".@{$w2s{$w}}." prons, no problem.\n";
                  }
                  $str .= " $w2s{$w}[0]";
                } else {
                  die "[ERROR] no subword seq exist in W2S for word: $w  at line: $ln, word: $wn\n";
                }
              } else {
                if (@{$w2s{$w}} > 1) {
                  # print "  Pron $i selected for ".@{$w2s{$w}}."-pron word $w at time $beg\n";
                }
                $str .= " $subwordseq2replace";
              }
            }
          }
        }
      }
      $str =~ s/^ //;
      print OF "$str\n";
      $$ptransutt = $str;
    }
  }
  close(F);
  close(OF);
}
print "Find OOV $oov_num times.\n";
print "Find OOV with multi-pronunciations $oov_multi_pron_num times.\n";

if ($do_stm eq 'true') {
  print "Generating new stm file to: $stm_out\n";
  open(ISTM, "$stm_in") || die "cannot open input file: $stm_in\n";
  open(OSTM, ">$stm_out") || die "cannot open input file: $stm_out\n";
  while (my $line = <ISTM>) {
    chomp($line);
    my @col = split(/ +/, $line);
    if (@col > 5 && $col[5] =~ m/^IGNORE_TIME/) {
      print OSTM "$line\n";
    } else {
      my $f = $col[0];
      $f =~ s/^;;//;
      my @words = split(/ /, $trans{$f}{$col[3]});
      for (@words) {
        if ($_ eq '<hes>' || $_ eq '<foreign>' || $_ =~ m/^\-/ || $_ =~ m/\-$/) {
          $_ = "($_)";
        } elsif ($_ =~ m/^\*(.*)\*$/) {
          $_ =~ s/^\*(.*)\*$/$1/;
          if (!defined($w2s{$_})) {
            print STDERR "[WARNING] word $_ in *...* not exist.\n";
          } else {
            if (@{$w2s{$_}} > 1) {
              print "[WARNING] word $_ in *...* has ".@{$w2s{$_}}." pronunciations, arbitrarily pick the 0th one\n";
            } else {
              print "word $_ in *...* has only one pronunciation, Good!\n";
            }
            $_ = $w2s{$_}[0];
          }
        } elsif ($_ eq '~' || $_ =~ m/^<.*>$/) {
          $_ = '';
        }
      }
      my $str = join(' ', @words);
      $str =~ s/ +/ /g;
      $str =~ s/^ +//;
      print OSTM "@col[0..4]  $str\n";
    }
  }
  close(ISTM);
  close(OSTM);
}

print "Done.\n";


