#!/bin/perl -w

use strict;
use warnings;
use Encode;
use Getopt::Long;

sub ::tolower {
    my ($str) = @_;
    # $str =~ tr/A-ZĂÂĐÊÔƠƯÀẰẦÈỀÌÒỒỜÙỪỲẢẲẨẺỂỈỎỔỞỦỬỶÃẴẪẼỄĨÕỖỠŨỮỸÁẮẤÉẾÍÓỐỚÚỨÝẠẶẬẸỆỊỌỘỢỤỰỴ/\
    #            a-zăâđêôơưàằầèềìòồờùừỳảẳẩẻểỉỏổởủửỷãẵẫẽễĩõỗỡũữỹáắấéếíóốớúứýạặậẹệịọộợụựỵ/;
    # $str =~ tr/A-ZĂÂĐÊÔƠƯÀẰẦÈỀÌÒỒỜÙỪỲẢẲẨẺỂỈỎỔỞỦỬỶÃẴẪẼỄĨÕỖỠŨỮỸÁẮẤÉẾÍÓỐỚÚỨÝẠẶẬẸỆỊỌỘỢỤỰỴ/a-zăâđêôơưàằầèềìòồờùừỳảẳẩẻểỉỏổởủửỷãẵẫẽễĩõỗỡũữỹáắấéếíóốớúứýạặậẹệịọộợụựỵ/;
    $str = encode('utf8', lc(decode('utf8',$str)));
    return $str;
}

my $romanized = "false";  # useless

GetOptions('romanized=s'     => \$romanized);

if ($#ARGV != 5) {
    die "USAGE: $0 <phones> <model> <align-file> <lexicon> <text> <out-dir>\n  e.g. $0 phones.txt final.mdl ali.1.gz data/lang/phones/align_lexicon.txt data/train/split12/1/text tri4b_ali/view\n  if <text> is '-', word MLF file will not be generated.\n";
}

my $phone = $ARGV[0];
my $mdl = $ARGV[1];
my $ali = $ARGV[2];
my $lex = $ARGV[3];
my $text = $ARGV[4];
my $odir = $ARGV[5];

my $out = $ali;
$out =~ s/^.*\/([^\/]+)$/$1/;
#print "show file = $odir/$out.show\n";
if (! -d "$odir") {
    mkdir("$odir") or die "[ERROR] mkdir $odir failed.";
} elsif (#(-e "$odir/$out.show") ||
     0&&( (-e "$odir/$out.mlf.phone")
      || (-e "$odir/$out.mlf.phone-word")
      || (-e "$odir/$out.mlf.word") ) ) {
    die "[ERROR] $odir is not empty. ";
}

if (!(-e "$odir/$out.show")) {
    my $cmd = "show-alignments $phone $mdl ark:";
    if ($ali =~ /\.gz$/) {
         $cmd .= "\"gzip -cdf $ali|\"";
    } else {
         $cmd .= "$ali";
    }
    $cmd .= " > $odir/$out.show";
    system($cmd);
}

my %lex;
my %rlex;
open(LEX, "$lex") or die "cannot open lexicon file $lex\n";
while (my $line = <LEX>) {
    chomp($line);
    my @phoneseq = split(/ +/, $line);
    my $word = shift @phoneseq; shift @phoneseq;
    my $pron = join(' ', @phoneseq);
    $rlex{$pron} = $word;
    $lex{$word}{$pron} = 1;
}
close(LEX);

my %text;
open(TEXT, "$text") or die "cannot open text file $text\n";
while (my $line = <TEXT>) {
    chomp($line);
    my @wordseq = split(/ +/, $line);
    my $utt = shift @wordseq;
    $text{$utt} = ();
    foreach (@wordseq) {
        $_ = &tolower($_);
        if (&tolower($_) ne $_) {
          print "[WARNING] this language has lower case!!  $_ --> ".&tolower($_)."\n";
        }
    }
    push(@{$text{$utt}}, @wordseq);
}
close(TEXT);

open(SHOW, "$odir/$out.show") or die "cannot open show-alignments file $odir/$out.show\n";
open(PMLF, ">$odir/$out.mlf.phone") or die "cannot open phone mlf file $odir/$out.mlf.phone\n";
open(PWMLF, ">$odir/$out.mlf.phone-word") or die "cannot open phone-word mlf file $odir/$out.mlf.phone-word\n";
open(WMLF, ">$odir/$out.mlf.word") or die "cannot open word mlf file $odir/$out.mlf.word\n";

print PMLF "#!MLF!#\n";
print PWMLF "#!MLF!#\n";
print WMLF "#!MLF!#\n";
while (my $stateseq = <SHOW>) {
    chomp($stateseq);
    my $phoneseq = <SHOW>;
    chomp($phoneseq);
    <SHOW>;   # read in empty line
    my @states = split(/ +/, $stateseq);
    my @phones = split(/ +/, $phoneseq);
    my $utt = shift @states;
    die if ($utt ne (shift @phones));
    print "$utt\n";
    print PMLF "\"$utt\"\n";
    print PWMLF "\"$utt\"\n";
    print WMLF "\"$utt\"\n";
    #my @words = ('!sil', @{$text{$utt}}, '!sil');
    my @words = @{$text{$utt}};
    my $frm = 0;
    my $start = 0;
    my $wstart = 0;
    my $wphones = '';
    $phoneseq = join(' ', @phones);
    my $wordseq = join(' ', @words);

    while (my $tok = shift @states) {
        if ($tok eq '[') {
            $start = $frm;
        } elsif ($tok eq ']') {
            my $p = shift @phones;
            if ($wphones eq '') {
                $wphones = "$p";
            } else {
                $wphones .= " $p";
            }
            print PMLF "$start $frm $p\n";
            if ($wphones eq 'SIL'
                && (@words == 0 || !defined($lex{$words[0]}{$wphones}))) {
                unshift @words, '<eps>';
            }
            my $unk = 0;
            if ($wphones =~ /<oov>(_\w)?/
                && !defined($lex{$words[0]}{$wphones})) {
                $words[0] = '<unk>'.$words[0];
                $unk = 1;
            }
            #print join(' ', @words)."\n";
            #print "$words[0] =? $wphones ??\n";
            if ($unk ==0 && @words == 0) {
                print "[WARNING] phone seq and word seq don't mathch: $wphones\nphone : $phoneseq\nword  : $wordseq\n";
            }
            if ($unk == 1 || (@words > 0 && defined($lex{$words[0]}{$wphones}))) {
                print WMLF "$wstart $frm $words[0]\n";
                print PWMLF "$wstart $frm $wphones\n";
                shift @words;
                $wstart = $frm;
                $wphones = '';
            }
        } else {
            $frm++;
        }
    }
    die if (@words != 0 || @phones != 0 || @states != 0);
    print PMLF ".\n";
    print PWMLF ".\n";
    print WMLF ".\n";
}
close(SHOW);
close(PMLF);
close(PWMLF);
close(WMLF);

print "Done\n";



#open(PWMLF, "$odir/$out.mlf.phone-word") or die "cannot open phone-word mlf file $odir/$out.mlf.phone-word\n";
#my $utt = '';
#while (my $line=<PWMLF>) {
#    if ($line =~ /^\d+ \d+ .*/) {
#        chomp($line);
#        my @items = split(/ +/, $line);
#        print WMLF (shift @items)." ".(shift @items)." ";
#        my $phoneseq = join(' ', @items);
#        if (defined($rlex{$phoneseq})) {
#            if ($phoneseq eq 'sil') {
#                print WMLF "$rlex{$phoneseq}\n";
#            } else {
#                my $word = shift @{$text{$utt}};
#                if (!defined($lex{$word}{$phoneseq})) {
#                    if ($phoneseq ne 'spn_S') { # not <unk>
#                        die "[ERROR] \"$utt\" not match: \"$word\" with pronounciation \"$phoneseq\"\n";
#                    }
#                }
#                print WMLF "$word\n";
#            }
#        } else {
#            die "[ERROR] Word '$phoneseq' in alignment not exists in lexicon.\n";
#        }
#    } else {
#        print WMLF $line;
#        if ($line =~ /^"(.*)"/) {
#            chomp($line);
#            $line =~ s/^"(.*)"$/$1/;
#            $utt = $line;
#        }
#    }
#}
#close(PWMLF);
#close(WMLF);
