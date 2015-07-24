#!/usr/bin/perl

# Copyright 2012  Johns Hopkins University (Author: Guoguo Chen)
# Apache 2.0.
#

use strict;
use warnings;
use Getopt::Long;

sub KeywordSort {
  if ($a->[0] ne $b->[0]) {
    $b->[0] <=> $a->[0];
  } else {
    $b->[1] <=> $a->[1];
  }
}

my $Usage = <<EOU;
This script reads a alignment.csv file and computes the ATWV, OTWV, MTWV by
sweeping the threshold. It also computes the lattice recall. The duration of
the search collection is supposed to be provided. In the Babel case, the
duration should be half of the total audio duration.

The alignment.csv file is supposed to have the following fields for each line:
language,file,channel,termid,term,ref_bt,ref_et,sys_bt,sys_et,sys_score,
sys_decision,alignment

Usage: kws_oracle_threshold.pl [options] <alignment.csv>
 e.g.: kws_oracle_threshold.pl alignment.csv

Allowed options:
  --beta                      : Beta value when computing ATWV              (float,   default = 999.9)
  --duration                  : Duration of all audio, you must set this    (float,   default = 999.9)

EOU

my $beta = 999.9;
my $duration = 999.9;
GetOptions(
  'beta=f'         => \$beta,
  'duration=f'     => \$duration);

@ARGV == 1 || die $Usage;

# Works out the input/output source.
my $alignment_in = shift @ARGV;

# Hash alignment file. For each instance we store a 3-dimension vector:
# [score, ref, res]
# where "score" is the confidence of that instance, "ref" equals 0 means there's
# no reference at that place and 1 means there's corresponding reference, "res"
# 0 means the instance is not considered when scoring, 1 means it's a false
# alarm and 2 means it's a true hit.
open(A, "<$alignment_in") || die "$0: Fail to open alignment file: $alignment_in\n";
my %Ntrue;
my %NtrueEst;
my %keywords;
my %alignment;
my $true_miss = 0;
my $soft_miss = 0;
my $true_hit = 0;
while (<A>) {
  chomp;
  my @col = split(',');
  @col == 12 || die "$0: Bad number of columns in $alignment_in: $_\n";

  # First line of the csv file.
  if ($col[11] eq "alignment") {next;}

  # Instances that do not have corresponding references.
  if ($col[11] eq "CORR!DET" || $col[11] eq "FA") {
    if (!defined($alignment{$col[3]})) {
      $alignment{$col[3]} = [];
      $NtrueEst{$col[3]} = 0;
    }
    my $ref = 0;
    my $res = 0;
    if ($col[11] eq "FA") {
      $res = 1;
    }
    push(@{$alignment{$col[3]}}, [$col[9], $ref, $res, $col[1]]);
    $NtrueEst{$col[3]} += $col[9];
    next;
  }

  # Instances that have corresponding references.
  if ($col[11] eq "CORR" || $col[11] eq "MISS") {
    if (!defined($alignment{$col[3]})) {
      $alignment{$col[3]} = [];
      $Ntrue{$col[3]} = 0;
      $NtrueEst{$col[3]} = 0;
    }
    my $ref = 1;
    my $res = 0;
    if ($col[10] ne "") {
      if ($col[11] eq "CORR") {
        $res = 2;
      }
      push(@{$alignment{$col[3]}}, [$col[9], $ref, $res, $col[1]]);
      $NtrueEst{$col[3]} += $col[9];
    }
    $Ntrue{$col[3]} += 1;
    $keywords{$col[3]} = 1;

    # The following is for lattice recall.
    if ($col[11] eq "CORR" && $col[10] eq "YES") {
      $true_hit ++;
    } elsif ($col[11] eq "MISS" && $col[10] eq "NO") {
      $soft_miss ++;
    } elsif ($col[11] eq "MISS" && $col[10] eq "") {
      $true_miss ++;
    }
    next;
  }
}
close(A);

# Works out the oracle ATWV by sweeping the threshold.
my $atwv = 0.0;
my $atwv_trueNtrue = 0.0;
my $otwv = 0.0;
my %dotwv;
my %mtwv_sweep;
my %kst_thres;
my %kst_thres_trueNtrue;
my %kw_otwvs;
my %kw_best_thres;
my %kw_atwvs;
my %kw_atwvs_trueNtrue;
foreach my $kwid (keys %keywords) {
  # Sort the instances by confidence score.
  my @instances = sort KeywordSort @{$alignment{$kwid}};
  my $local_otwv = 0.0;
  my $max_local_otwv = 0.0;
  my $local_atwv = 0.0;
  my $local_atwv_trueNtrue = 0.0;
  my $local_best_thres = 0;
  my $this_thres = $NtrueEst{$kwid}/($duration/$beta+($beta-1)/$beta*$NtrueEst{$kwid});
  $kst_thres_trueNtrue{$kwid} = $Ntrue{$kwid}/($duration/$beta+($beta-1)/$beta*$Ntrue{$kwid});
  $kst_thres{$kwid} = $this_thres;
  my %local_dotwv;
  my %max_local_dotwv;
  foreach my $instance (@instances) {
    my @ins = @{$instance};
    my $gain = 1.0 / $Ntrue{$kwid};
    my $cost = $beta / ($duration - $Ntrue{$kwid});
    # OTWV.
    if (!defined($local_dotwv{$ins[3]})) {
      $local_dotwv{$ins[3]} = 0.0;
      $max_local_dotwv{$ins[3]} = 0.0;
    }
    if ($ins[1] == 1) {
      $local_otwv += $gain;
      $local_dotwv{$ins[3]} += $gain;
    } else {
      $local_otwv -= $cost;
      $local_dotwv{$ins[3]} -= $cost;
    }
    if ($local_otwv > $max_local_otwv) {
      $max_local_otwv = $local_otwv;
      $local_best_thres = $ins[0];
    }
    if ($local_dotwv{$ins[3]} > $max_local_dotwv{$ins[3]}) {
      $max_local_dotwv{$ins[3]} = $local_dotwv{$ins[3]};
    }
    # ATWV.
    if ($ins[0] > $this_thres) {
      if ($ins[2] == 1) { # FA
        $local_atwv -= $cost;
      } elsif ($ins[2] == 2) { # CORR
        $local_atwv += $gain;
      }
    }
    if ($ins[0] > $kst_thres_trueNtrue{$kwid}) {
      if ($ins[2] == 1) { # FA
        $local_atwv_trueNtrue -= $cost;
      } elsif ($ins[2] == 2) { # CORR
        $local_atwv_trueNtrue += $gain;
      }
    }
    #if ($ins[2] == 1) {
    #  $local_atwv -= $cost;
    #} elsif ($ins[2] == 2) {
    #  $local_atwv += $gain;
    #}
  }
  $atwv += $local_atwv;
  $otwv += $max_local_otwv;
  $kw_otwvs{$kwid} = $max_local_otwv;
  $kw_best_thres{$kwid} = $local_best_thres;
  $kw_atwvs{$kwid} = $local_atwv;
  $kw_atwvs_trueNtrue{$kwid} = $local_atwv_trueNtrue;

  $dotwv{$kwid} = 0.0;
  foreach (sort keys %max_local_dotwv) {
    $dotwv{$kwid} += $max_local_dotwv{$_};
  }
}

my $avg_dotwv = 0.0;
foreach (sort keys %dotwv) {
  $avg_dotwv += $dotwv{$_};
}
$avg_dotwv /= scalar(keys %keywords);
$avg_dotwv = sprintf("%.4f", $avg_dotwv);
$atwv /= scalar(keys %keywords);
$atwv = sprintf("%.4f", $atwv);
$otwv /= scalar(keys %keywords);
$otwv = sprintf("%.4f", $otwv);
print STDERR "ATWV = $atwv\n";
print STDERR "OTWV = $otwv\n";
print STDERR "DOTWV = $avg_dotwv\n";

print "kwid,otwv,dotwv,best_thres,atwv,kst_thres,atwv_trueNtrue,kst_thres_trueNtrue,Ntrue,NtrueEst\n";
foreach my $kwid (sort keys %kw_otwvs) {
  print "$kwid,$kw_otwvs{$kwid},$dotwv{$kwid},$kw_best_thres{$kwid},$kw_atwvs{$kwid},$kst_thres{$kwid},$kw_atwvs_trueNtrue{$kwid},$kst_thres_trueNtrue{$kwid},$Ntrue{$kwid},$NtrueEst{$kwid}\n";
}
