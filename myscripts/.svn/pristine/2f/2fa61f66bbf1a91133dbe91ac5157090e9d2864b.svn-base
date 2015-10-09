#!/usr/bin/perl

# Copyright 2012  Johns Hopkins University (Author: Guoguo Chen)
# Support several easy normalization method (chenzp, Mar 6, 2014)
# Apache 2.0.
#
use strict;
use warnings;
use Getopt::Long;
use XML::DOM;

my $Usage = <<EOU;
This script reads the kwslist.xml (typically unnormalized) and writes them as the kwslist.xml file.
It can also do things like score normalization, decision making, etc.

Usage: $0 [options] <kwslist_in|-> <kwslist_out|->
 e.g.: $0 --flen=0.01 --duration=1000 --segments=data/eval/segments
                              --normalize=true kwslist.unnormalized.xml kwslist.xml

Allowed options:
  --beta                      : Beta value when computing ATWV              (float,   default = 999.9)
  --digits                    : How many digits should the score use        (int,     default = "infinite")
  --flen                      : Frame length                                (float,   default = 0.01)
  --normalize                 : Normalization method (kaldi/KST/skip)       (string,  default = kaldi2)
  --Ntrue-scale               : Keyword independent scale factor for Ntrue  (float,   default = 1.0)
  --remove-NO                 : Remove the "NO" decision instances          (boolean, default = false)
  --segments                  : Segments file from Kaldi                    (string,  default = "")
  --verbose                   : Verbose level (higher --> more kws section) (integer, default 0)
  --YES-cutoff                : Only keep "\$YES-cutoff" yeses for each kw  (int,     default = -1)
  --all-YES                   : set hard decisions to YES                   (boolean, default = false)
  --cutoff-thres              : remove items whose score <= this value      (float, default = 0)

EOU

my $segment = "";
my $flen = 0.01;
my $beta = 999.9;
my $duration = 999.9;
my $normalize = "kaldi2";
my $Ntrue_scale = 1.0;
my $Ntrue_file = "";
my $digits = 0;
my $verbose = 0;
my $remove_NO = "false";
my $YES_cutoff = -1;
my $all_YES = "false";
my $cutoff_thres = 0;
GetOptions('segments=s'     => \$segment,
  'flen=f'         => \$flen,
  'beta=f'         => \$beta,
  'duration=f'     => \$duration,
  'normalize=s'    => \$normalize,
  'Ntrue-scale=f'  => \$Ntrue_scale,
  'Ntrue-file=s'   => \$Ntrue_file,
  'digits=i'       => \$digits,
  'verbose=i'         => \$verbose,
  'YES-cutoff=i'      => \$YES_cutoff,
  'remove-NO=s'       => \$remove_NO,
  'all-YES=s'         => \$all_YES,
  'cutoff-thres=f'    => \$cutoff_thres);

my @norm_methods = ('skip', 'kaldi', 'kaldi2', 'kaldi2True', 'KST', 'STO', 'STO2', 'QL');
($normalize ~~ @norm_methods) || die "$0: Bad value for option --normalize\n";
($remove_NO eq "true" || $remove_NO eq "false") || die "$0: Bad value for option --remove-NO\n";
($all_YES eq "true" || $all_YES eq "false") || die "$0: Bad value for option --all-YES\n";

if ($segment) {
  open(SEG, "<$segment") || die "$0: Fail to open segment file $segment\n";
}
if ($Ntrue_file) {
  open(NTRUE, "<$Ntrue_file") || die "$0: Fail to open Ntrue file $Ntrue_file\n";
}

if (@ARGV != 2) {
  die $Usage;
}

# Get parameters
my $filein = shift @ARGV;
my $fileout = shift @ARGV;

# Get input source
my $source = "";
if ($filein eq "-") {
  $source = "STDIN";
  die "Standard input not supported.\n";
} else {
  open(I, "<$filein") || die "$0: Fail to open input file $filein\n";
  $source = "I";
}

my $parser = XML::DOM::Parser->new();
my $doc = $parser->parsefile("$filein");
my $root = $doc->getDocumentElement();


# Get symbol table and start time
my %tbeg;
if ($segment) {
  while (<SEG>) {
    chomp;
    my @col = split(" ", $_);
    @col == 4 || die "$0: Bad number of columns in $segment \"$_\"\n";
    $tbeg{$col[0]} = $col[2];
  }
}

# Function for printing Kwslist.xml
sub PrintKwslist {
  my ($info, $KWS) = @_;

  my $kwslist = "";

  # Start printing
  $kwslist .= "<kwslist kwlist_filename=\"$info->[0]\" language=\"$info->[1]\" system_id=\"$info->[2]\">\n";
  my $prev_kw = "";
  foreach my $kwentry (@{$KWS}) {
    if ($prev_kw ne $kwentry->[0]) {
      if ($prev_kw ne "") {$kwslist .= "  </detected_kwlist>\n";}
      $kwslist .= "  <detected_kwlist search_time=\"1\" kwid=\"$kwentry->[0]\" oov_count=\"0\">\n";
      $prev_kw = $kwentry->[0];
    }
    $kwslist .= "    <kw file=\"$kwentry->[1]\" channel=\"$kwentry->[2]\" tbeg=\"$kwentry->[3]\" dur=\"$kwentry->[4]\" score=\"$kwentry->[5]\" decision=\"$kwentry->[6]\"";
    #if (defined($kwentry->[7])) {$kwslist .= " threshold=\"$kwentry->[7]\"";}  chenzp: I've defined [7] as the max single score before merge
    #if (defined($kwentry->[8])) {$kwslist .= " raw_score=\"$kwentry->[8]\"";}
    $kwslist .= "/>\n";
  }
  if ($prev_kw ne "") {$kwslist .= "  </detected_kwlist>\n";}
  $kwslist .= "</kwslist>\n";

  return $kwslist;
}

# Function for sorting
sub KwslistOutputSort {
  if ($a->[0] ne $b->[0]) {
    if ($a->[0] =~ m/[0-9]+$/ && $b->[0] =~ m/[0-9]+$/) {
      ($a->[0] =~ /([0-9]*)$/)[0] <=> ($b->[0] =~ /([0-9]*)$/)[0]
    } else {
      $a->[0] cmp $b->[0];
    }
  } elsif ($a->[5] ne $b->[5]) {
    $b->[5] <=> $a->[5];
  } else {
    $a->[1] cmp $b->[1];
  }
}
sub KwslistDupSort {
  my ($a, $b, $duptime) = @_;
  if ($a->[0] ne $b->[0]) {
    $a->[0] cmp $b->[0];
  } elsif ($a->[1] ne $b->[1]) {
    $a->[1] cmp $b->[1];
  } elsif ($a->[2] ne $b->[2]) {
    $a->[2] cmp $b->[2];
  } elsif (abs($a->[3]-$b->[3]) >= $duptime){
    $a->[3] <=> $b->[3];
  } elsif ($a->[5] ne $b->[5]) {
    $b->[5] <=> $a->[5];
  } else {
    $b->[4] <=> $a->[4];
  }
}

# Processing
my $kwlist_filename = $root->getAttribute('kwlist_filename');
my $language = $root->getAttribute('language');
my $system_id = $root->getAttribute('system_id');

my @KWS;
foreach my $detected_kwlist ($root->getElementsByTagName("detected_kwlist")) {
  my $search_time = $detected_kwlist->getAttribute('search_time');
  my $kwid = $detected_kwlist->getAttribute('kwid');
  my $oov_count = $detected_kwlist->getAttribute('oov_count');
  foreach my $kw ($detected_kwlist->getElementsByTagName("kw")) {
    my $utter = $kw->getAttribute('file');
    my $chnl = $kw->getAttribute('channel');
    my $start = $kw->getAttribute('tbeg');
    my $dur = $kw->getAttribute('dur');
    my $score = $kw->getAttribute('score');
    my $decision = $kw->getAttribute('decision');
    push(@KWS, [$kwid, $utter, $chnl, $start, $dur, $score, "", $score]);
  }
}

my %Ntrue = ();
if ($normalize !~ /True$/) { # estimate N_True
  foreach my $kwentry (@KWS) {
    if (!defined($Ntrue{$kwentry->[0]})) {
      $Ntrue{$kwentry->[0]} = 0.0;
    }
    $Ntrue{$kwentry->[0]} += $kwentry->[5];
  }
} else { # read true N_True, just for analysis
  while (<NTRUE>) {
    chomp;
    my @col = split(/\t/, $_);
    if (@col < 2 || $col[1] eq '') {
      $Ntrue{$col[0]} = 0;  # actually this will not affect TWV
    } else {
      $Ntrue{$col[0]} = $col[1];
    }
  }
}

# Scale the Ntrue
my %threshold;
foreach my $key (keys %Ntrue) {
  $Ntrue{$key} *= $Ntrue_scale;
  $threshold{$key} = $Ntrue{$key}/($duration/$beta+($beta-1)/$beta*$Ntrue{$key});
}

my $format_string = "%g";
if ($digits gt 0 ) {
  $format_string = "%." . $digits ."f";
}

my $outdir = `dirname $fileout`;
chomp($outdir);
my %STOsum;
if ($normalize =~ /^STO/) {
  $all_YES = "true";  # TODO We haven't made ATWV threshold decision in this method
                    #      , force $all_YES equal to true.
}
  foreach my $kwentry (@KWS) {
    if (!defined($STOsum{$kwentry->[0]})) {
      $STOsum{$kwentry->[0]} = $kwentry->[5];
    } else {
      $STOsum{$kwentry->[0]} += $kwentry->[5]; # not equal to Ntrue (before scale),
                                               # 'cause we just do remove_dup before.
    }
  }
#  open(STO_OUT, ">$outdir/STOsum.csv") || die "cannot write to $outdir/STOsum.csv";
#  print STO_OUT "key,STO sum,thres,N_true,scaled N_true\n";
#  for my $key (sort keys %STOsum) {
#    print STO_OUT "$key,$STOsum{$key},$threshold{$key},".$Ntrue{$key}/$Ntrue_scale.",$Ntrue{$key}\n";
#  }
#  close(STO_OUT);
#}
my %QLdur;
my %numHit;
if ($normalize eq 'QL') {
  $all_YES = "true";  # TODO We haven't made ATWV threshold decision in this method
                    #      , force $all_YES equal to true.
  foreach my $kwentry (@KWS) {
    if (!defined($QLdur{$kwentry->[0]})) {
      $QLdur{$kwentry->[0]} = $kwentry->[4];
      $numHit{$kwentry->[0]} = 1;
    } else {
      $QLdur{$kwentry->[0]} += $kwentry->[4];
      $numHit{$kwentry->[0]}++;
    }
  }
  open(QL_OUT, ">$outdir/QLdur.csv") || die "cannot write to $outdir/QLdur.txt";
  print QL_OUT "key,QL duration,N_true\n";
  foreach my $key (keys %QLdur) {
    $QLdur{$key} /= $numHit{$key};
    print QL_OUT "$key,$QLdur{$key},$Ntrue{$key}\n";
  }
  close(QL_OUT);
}

my @info = ($kwlist_filename, $language, $system_id);
my %YES_count;
my $logThr = log(0.5);
foreach my $kwentry (@KWS) {
  my $threshold = $threshold{$kwentry->[0]};
  if ($kwentry->[5] > $threshold) {
    $kwentry->[6] = "YES";
    if (defined($YES_count{$kwentry->[0]})) {
      $YES_count{$kwentry->[0]} ++;
    } else {
      $YES_count{$kwentry->[0]} = 1;
    }
  } else {
    $kwentry->[6] = "NO";
    if (!defined($YES_count{$kwentry->[0]})) {
      $YES_count{$kwentry->[0]} = 0;
    }
  }
  #if ($verbose > 0) {
  #  push(@{$kwentry}, sprintf("%g", $threshold));
  #}
  if ($normalize =~ /^kaldi/) {
    #if ($verbose > 0) {
    #  push(@{$kwentry}, $kwentry->[5]);
    #}
    my $numerator = (1-$threshold)*$kwentry->[5];
    my $denominator = (1-$threshold)*$kwentry->[5]+(1-$kwentry->[5])*$threshold;
    if ($denominator != 0) {
      $kwentry->[5] = sprintf($format_string, $numerator/$denominator);
    } else {
      $kwentry->[5] = sprintf($format_string, $kwentry->[5]);
    }
  } elsif ($normalize eq "KST") {
    if ($verbose > 0) {
      push(@{$kwentry}, $kwentry->[5]);
    }
    $kwentry->[5] = sprintf($format_string, $kwentry->[5]**($logThr/log($threshold)));
  } elsif ($normalize =~ /^STO/) {
    if ($verbose > 0) {
      push(@{$kwentry}, $kwentry->[5]);
    }
    $kwentry->[5] = sprintf($format_string, $kwentry->[5] / $STOsum{$kwentry->[0]});
  } elsif ($normalize eq "QL") {
    if ($verbose > 0) {
      push(@{$kwentry}, $kwentry->[5]);
    }
    $kwentry->[5] = sprintf($format_string, $kwentry->[5]**(1/$QLdur{$kwentry->[0]}));
  } else {
    $kwentry->[5] = sprintf($format_string, $kwentry->[5]);
  }
}

# Output sorting
my @tmp = sort KwslistOutputSort @KWS;

if ($all_YES eq "true") {
  for (my $i = 0; $i < scalar(@tmp); $i ++) {
    $tmp[$i]->[6] = "YES";
  }
} else {
# Process the YES-cutoff. Note that you don't need this for the normal cases where
# hits and false alarms are balanced
  if ($YES_cutoff != -1) {
    my $count = 1;
    for (my $i = 1; $i < scalar(@tmp); $i ++) { 
      if ($tmp[$i]->[0] ne $tmp[$i-1]->[0]) {
        $count = 1;
        next;
      }
      if ($YES_count{$tmp[$i]->[0]} > $YES_cutoff*2) {
        $tmp[$i]->[6] = "NO";
        $tmp[$i]->[5] = 0;
        next;
      }
      if (($count == $YES_cutoff) && ($tmp[$i]->[6] eq "YES")) {
        $tmp[$i]->[6] = "NO";
        $tmp[$i]->[5] = 0;
        next;
      }
      if ($tmp[$i]->[6] eq "YES") {
        $count ++;
      }
    }
  }
}

# Process the remove-NO decision
if ($remove_NO eq "true") {
  my @KWS = @tmp;
  @tmp = ();
  for (my $i = 0; $i < scalar(@KWS); $i ++) {
    if ($KWS[$i]->[6] eq "YES") {
      push(@tmp, $KWS[$i]);
    }
  }
}
# Process the cutoff for low score items
if ($cutoff_thres >= 0) {
  my @KWS = @tmp;
  @tmp = ();
  for (my $i = 0; $i < scalar(@KWS); $i ++) {
    if ($KWS[$i]->[5] > $cutoff_thres) {
      push(@tmp, $KWS[$i]);
    }
  }
}

# Printing
my $kwslist = PrintKwslist(\@info, \@tmp);

if ($segment) {close(SEG);}
if ($filein  ne "-") {close(I);}
if ($fileout eq "-") {
    print $kwslist;
} else {
  open(O, ">$fileout") || die "$0: Fail to open output file $fileout\n";
  print O $kwslist;
  close(O);
}
