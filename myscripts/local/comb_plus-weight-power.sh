#!/bin/bash

method=SUM  # cannot support p* method
weight_power=1
method_opt=
# End configuration section.

help_message="$0: Usage: see local/comb.pl" 

echo $0 $@
[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;


if [ $# -ne 2 ]; then
    printf "FATAL: incorrect number of variables given to the script\n\n"
    printf "$help_message\n"
    exit 1;
fi
if [[ $method =~ ^p ]]; then
  echo "$0: Currently we can't support methods with p"
  exit 1;
fi

systems=$1
okwslist=$2

systems_weight_powered=`echo "$systems" | perl -e '
  my $sys = <STDIN>;
  my @col = split(/ /, $sys);
  my $i = 0;
  my $max = -1;
  while ($i < @col) {
    if ($col[$i] > $max) {
      $max = $col[$i];
    }
    if ($col[$i] < 0) {
      die "weight should >= 0!\n";
    }
    $i += 2;
  }
  my $sum = 0;
  $i = 0;
  while ($i < @col) {
    $col[$i] = ($col[$i]/$max) ** ('$weight_power');
    $sum += $col[$i];
    $i += 2;
  }
  $i = 0;
  while ($i < @col) {
    $col[$i] /= $sum;
    $i += 2;
  }
  print join(" ", @col);
'`

czpScripts/local/comb.pl --method=$method $method_opt \
  $systems_weight_powered $okwslist || exit 1

