#!/bin/perl -w

use strict;

if ($#ARGV != 2) {
  die "Usage:$0 phone_count.txt alignment.csv tot-trial"
}
my $phone_count = $ARGV[0];
my $align = $ARGV[1];
my $tottrial = $ARGV[2];
my $beta = 999.9; 
print STDERR "Total Trials: $tottrial\n";
open(CNT,"$phone_count") || die "cannot open phone count file\n";
my %cnt;
while (<CNT>) {
  chomp;
  my @col = split();
  $cnt{$col[0]} = $col[1];
}
my @s_r;
my @s2_r;
my @s_t;
my @s2_t;
my @num;
my $totnum = 0;
my %recall;
my %twv;
while (<STDIN>) {
  chomp;
  my @col = split();
  my $key = $col[0];
  if (!defined($cnt{$key})) {
    die "$col[0] not defined in phone count file\n"
  }
  my $c = $cnt{$key};
  if (!defined($s_r[$c])) {
    $s_r[$c] = 0;
    $s2_r[$c] = 0;
    $s_t[$c] = 0;
    $s2_t[$c] = 0;
    $num[$c] = 0;
  }
  $recall{$key} = 1 - $col[2];
  $s_r[$c] += $recall{$key};
  $s2_r[$c] += $recall{$key} ** 2;
  $twv{$key} = $col[1];
  $s_t[$c] += $twv{$key};
  $s2_t[$c] += $twv{$key} ** 2;
  $num[$c] ++;
  $totnum ++;
}
print STDERR "Keyword (with occurances) number: $totnum\n";

my %stwv;
my %posting;
my %true;
open(ALI, "$align") || die "cannot open alignment file\n";
<ALI>;
while (<ALI>) {
  chomp;
  my @col = split(/,/, $_);
  my $key = $col[3];
  if (!defined($cnt{$key})) {next;}  # skip OOV
  if ($col[5] ne '') { # a ref
    if (!defined($true{$key})) {
      $true{$key} = 0;
      $stwv{$key} = 0;
    }
    $true{$key} ++;
    if ($col[7] ne '') { # a hyp
      $stwv{$key} ++;
    }
  }
  if (!defined($posting{$key})) { # for keywords without any hyps, we also give them empty postings
    @{$posting{$key}} = ();
  }
  if ($col[10] ne '') { # a hyp
    my $truth = 'false';
    if ($col[10] eq 'YES' && $col[11] eq 'CORR'
      || $col[10] eq 'NO' && $col[11] eq 'MISS') {
      $truth = 'true';
    }
    my @item = ($col[9], $truth);
    push(@{$posting{$key}}, \@item);
  }
}

# Process N_true and STWV
my @true_n;
my $tottrue=0;
my @stwv_n;
for my $key (keys %stwv) {
  $stwv{$key} /= $true{$key};
  my $c = $cnt{$key};
  if (!defined($stwv_n[$c])) {
    $stwv_n[$c] = 0;
    $true_n[$c] = 0;
  }
  $stwv_n[$c] += $stwv{$key};
  $true_n[$c] += $true{$key};
  $tottrue += $true{$key};
}

# Process OTWV
my %otwv;
my %otwv_recall;
my @otwv_n;
my @otwv_recall_n;
#my %twv_acc_thres; TODO use unnormalized kwslist file to see the metrics under accurate KST threshold
#my @twv_acc_thres_n;
for my $key (keys %posting) {
  if (!defined($cnt{$key})) {next;}  # skip OOV
  if (!defined($true{$key}) || $true{$key} == 0) { # not consider keywords with 0 ref
    next;
  }
  my $rBenifit = 1 / $true{$key};
  my $fCost = $beta / ($tottrial - $true{$key});
  my $max_twv = 0;
  my $max_twv_recall = 0;
  my $curr_twv = 0;
  my $curr_recall = 0;
  my $rnum = 0;
  my $fnum = 0;
  # my $acc_thres = $true{$key} / ($tottrial/$beta + ($beta-1)*$true{$key}/$beta);
  for my $item (sort {$b->[0] <=> $a->[0]} @{$posting{$key}}) {
    #print STDERR "$item->[0] $item->[1]\n";
    if ($item->[1] eq 'true') {
      $curr_twv += $rBenifit;
      $curr_recall += $rBenifit;
      if ($curr_twv > $max_twv) {
        $max_twv = $curr_twv;
        $max_twv_recall = $curr_recall;
      }
    } else {
      $curr_twv -= $fCost;
    }
  }
  $otwv{$key} = $max_twv;
  $otwv_recall{$key} = $max_twv_recall;
  my $c = $cnt{$key};
  if (!defined($otwv_n[$c])) {
    $otwv_n[$c] = 0;
    $otwv_recall_n[$c] = 0;
  }
  $otwv_n[$c] += $otwv{$key};
  $otwv_recall_n[$c] += $otwv_recall{$key};
}

# Check results compared with metrics.txt
my $tototwv = 0;
my $totstwv = 0;
my $kwnum = 0;
for (my $i=1; $i < @num; $i++) {
  if (!defined($num[$i]) || $num[$i] <= 0) {
    next;
  }
  $tototwv += $otwv_n[$i];
  $totstwv += $stwv_n[$i];
  $kwnum += $num[$i];
}
printf STDERR "Mean OTWV: %f\n", $tototwv / $kwnum;
printf STDERR "Mean STWV: %f\n", $totstwv / $kwnum;

print STDERR "Examples:\n";
#print STDERR "Keywords\tTWV\tRecall\tOTWV\tOTWV_Recall\n";
my $lower_len = 0;
my $higher_len = 0;
my $equal_len = 0;
my $lower_num = 0;
my $higher_num = 0;
my $equal_num = 0;
for my $key (keys %recall) {
  my $o_recall = sprintf("%.4f", $otwv_recall{$key});
  my $o = sprintf("%.4f", $otwv{$key});
  if ($recall{$key} > $o_recall) {
    $lower_num ++;
    $lower_len += $cnt{$key};
  } elsif ($recall{$key} < $o_recall) {
    $higher_num ++;
    $higher_len += $cnt{$key};
  } else {
    $equal_num ++;
    $equal_len += $cnt{$key};
  }
#  print STDERR "$key\t$twv{$key}\t$recall{$key}\t$otwv{$key}\t$otwv_recall{$key}\n";
}
#printf STDERR "Lower num:\t%d\t%.1f phones\n", $lower_num, $lower_len / $lower_num;
#printf STDERR "Higher num:\t%d\t%.1f phones\n", $higher_num, $higher_len / $higher_num;
#printf STDERR "Equal num:\t%d\t%.1f phones\n", $equal_num, $equal_len / $equal_num;

printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", 
  "PC", "%_of_kw", "mean_N_true", "mean_Recall", "mean_TWV", "mean_STWV", "mean_OTWV_recall", "mean_OTWV";
for (my $i=1; $i<@num; $i++) {
  if (defined($num[$i]) && $num[$i] > 0) {
    printf "%d\t%f", $i, $num[$i] / $totnum;
    printf "\t%f", $true_n[$i] / $num[$i] / 25;
    my $mean_r = $s_r[$i] / $num[$i];
    my $stderr_r = ($s2_r[$i] / $num[$i] - ($mean_r) ** 2) ** 0.5;
    printf "\t%f", $mean_r; 
    my $mean_t = $s_t[$i] / $num[$i];
    my $stderr_t = ($s2_t[$i] / $num[$i] - ($mean_t) ** 2) ** 0.5;
    printf "\t%f", $mean_t;
    my $mean_stwv = $stwv_n[$i] / $num[$i];
    printf "\t%f", $mean_stwv;
    printf "\t%f", $otwv_recall_n[$i] / $num[$i];
    printf "\t%f", $otwv_n[$i] / $num[$i];
    printf "\n";
  }
}

