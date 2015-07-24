#!/usr/bin/perl

# Copyright 2012  Johns Hopkins University (Author: Guoguo Chen)
# Support several easy normalization method (chenzp, Mar 6, 2014)
# Apache 2.0.
#
use strict;
use warnings;
use Getopt::Long;

my $Usage = <<EOU;
This script reads the raw keyword search results [result.*] and writes them as the kwslist.xml file.
It can also do things like score normalization, decision making, duplicates removal, etc.

Usage: utils/write_kwslist.pl [options] <raw_result_in|-> <kwslist_out|->
 e.g.: utils/write_kwslist.pl --flen=0.01 --duration=1000 --segments=data/eval/segments
                              --normalize=true --map-utter=data/kws/utter_map raw_results kwslist.xml

Allowed options:
  --beta                      : Beta value when computing ATWV              (float,   default = 999.9)
  --digits                    : How many digits should the score use        (int,     default = "infinite")
  --duptime                   : Tolerance for duplicates                    (float,   default = 0.5)
  --duration                  : Duration of all audio, you must set this    (float,   default = 999.9)
  --ecf-filename              : ECF file name                               (string,  default = "") 
  --flen                      : Frame length                                (float,   default = 0.01)
  --index-size                : Size of index                               (float,   default = 0)
  --kwlist-filename           : Kwlist.xml file name                        (string,  default = "") 
  --language                  : Language type                               (string,  default = "cantonese")
  --map-utter                 : Map utterance for evaluation                (string,  default = "")
  --normalize                 : Normalization method (kaldi/KST/skip)       (string,  default = kaldi2)
  --Ntrue-scale               : Keyword independent scale factor for Ntrue  (float,   default = 1.0)
  --remove-dup                : Remove duplicates                           (boolean, default = false)
  --remove-NO                 : Remove the "NO" decision instances          (boolean, default = false)
  --segments                  : Segments file from Kaldi                    (string,  default = "")
  --system-id                 : System ID                                   (string,  default = "")
  --verbose                   : Verbose level (higher --> more kws section) (integer, default 0)
  --YES-cutoff                : Only keep "\$YES-cutoff" yeses for each kw  (int,     default = -1)
  --all-YES                   : set hard decisions to YES                   (boolean, default = false)
  --cutoff-thres              : remove items whose score <= this value      (float, default = 0)

EOU

my $segment = "";
my $flen = 0.01;
my $beta = 999.9;
my $duration = 999.9;
my $language = "cantonese";
my $ecf_filename = "";
my $index_size = 0;
my $system_id = "";
my $normalize = "kaldi2";
my $map_utter = "";
my $Ntrue_scale = 1.0;
my $digits = 0;
my $kwlist_filename = "";
my $verbose = 0;
my $duptime = 0.5;
my $remove_dup = "false";
my $remove_NO = "false";
my $YES_cutoff = -1;
my $all_YES = "false";
my $cutoff_thres = 0;
GetOptions('segments=s'     => \$segment,
  'flen=f'         => \$flen,
  'beta=f'         => \$beta,
  'duration=f'     => \$duration,
  'language=s'     => \$language,
  'ecf-filename=s' => \$ecf_filename,
  'index-size=f'   => \$index_size,
  'system-id=s'    => \$system_id,
  'normalize=s'    => \$normalize,
  'map-utter=s'    => \$map_utter,
  'Ntrue-scale=f'  => \$Ntrue_scale,
  'digits=i'       => \$digits,
  'kwlist-filename=s' => \$kwlist_filename,
  'verbose=i'         => \$verbose,
  'duptime=f'         => \$duptime,
  'remove-dup=s'      => \$remove_dup,
  'YES-cutoff=i'      => \$YES_cutoff,
  'remove-NO=s'       => \$remove_NO,
  'all-YES=s'         => \$all_YES,
  'cutoff-thres=f'    => \$cutoff_thres);

my @norm_methods = ('skip', 'kaldi', 'kaldi2', 'KST', 'STO', 'STO2', 'QL');
($normalize ~~ @norm_methods) || die "$0: Bad value for option --normalize\n";
($remove_dup eq "true" || $remove_dup eq "false") || die "$0: Bad value for option --remove-dup\n";
($remove_NO eq "true" || $remove_NO eq "false") || die "$0: Bad value for option --remove-NO\n";
($all_YES eq "true" || $all_YES eq "false") || die "$0: Bad value for option --all-YES\n";

if ($segment) {
  open(SEG, "<$segment") || die "$0: Fail to open segment file $segment\n";
}

if ($map_utter) {
  open(UTT, "<$map_utter") || die "$0: Fail to open utterance table $map_utter\n";
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
} else {
  open(I, "<$filein") || die "$0: Fail to open input file $filein\n";
  $source = "I";
}

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

# Get utterance mapper
my %utter_mapper;
if ($map_utter) {
  while (<UTT>) {
    chomp;
    my @col = split(" ", $_);
    @col == 2 || die "$0: Bad number of columns in $map_utter \"$_\"\n";
    $utter_mapper{$col[0]} = $col[1];
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
my @KWS;
while (<$source>) {
  chomp;
  my @col = split(" ", $_);
  @col == 5 || die "$0: Bad number of columns in raw results \"$_\"\n";
  my $kwid = shift @col;
  my $utter = $col[0];
  my $start = sprintf("%.2f", $col[1]*$flen);
  my $dur = sprintf("%.2f", $col[2]*$flen-$start);
  my $score = exp(-$col[3]);

  if ($segment) {
    $start = sprintf("%.2f", $start+$tbeg{$utter});
  }
  if ($map_utter) {
    $utter = $utter_mapper{$utter};
  }
  # if $utter end with -A/B, extract channel and save in $kwentry[2], rather than arbitrary set to 1.
  # push(@KWS, [$kwid, $utter, 1, $start, $dur, $score, ""]);
  my $chnl = 1;
  #if ($utter =~ s/\-([AB])$//) {
  #  $chnl = ord($1) - ord('A') + 1;
  #}
  push(@KWS, [$kwid, $utter, $chnl, $start, $dur, $score, "", $score]);
}

# Removing duplicates
if ($remove_dup eq "true") {
  my @tmp = sort {KwslistDupSort($a, $b, $duptime)} @KWS;
  @KWS = ();
  push(@KWS, $tmp[0]);
  for (my $i = 1; $i < scalar(@tmp); $i ++) {
    my $prev = $KWS[-1];
    my $curr = $tmp[$i];
    if ((abs($prev->[3]-$curr->[3]) < $duptime ) &&
        ($prev->[2] eq $curr->[2]) &&
        ($prev->[1] eq $curr->[1]) &&
        ($prev->[0] eq $curr->[0])) {
      if ($normalize =~ /2$/) { # if we want to sum scores of the merging items
        if ($curr->[7] > $KWS[-1]->[7]) {
          $KWS[-1]->[7] = $curr->[7];
          $KWS[-1]->[3] = $curr->[3];
          $KWS[-1]->[4] = $curr->[4];
        }
        $KWS[-1]->[5] += $curr->[5];
        if ($KWS[-1]->[5] > 1.0) {
          print STDERR "[WARN] score exceeds 1.0 to $KWS[-1]->[5] for $KWS[-1]->[0] $KWS[-1]->[1] $KWS[-1]->[2] $KWS[-1]->[3]\n"; 
          $KWS[-1]->[5] = 1.0;
        }
      }
      next;
    } else {
      push(@KWS, $curr);
    }
  }
}

my %Ntrue = ();
foreach my $kwentry (@KWS) {
  if (!defined($Ntrue{$kwentry->[0]})) {
    $Ntrue{$kwentry->[0]} = 0.0;
  }
  $Ntrue{$kwentry->[0]} += $kwentry->[5];
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
if ($map_utter) {close(UTT);}
if ($filein  ne "-") {close(I);}
if ($fileout eq "-") {
    print $kwslist;
} else {
  open(O, ">$fileout") || die "$0: Fail to open output file $fileout\n";
  print O $kwslist;
  close(O);
}
