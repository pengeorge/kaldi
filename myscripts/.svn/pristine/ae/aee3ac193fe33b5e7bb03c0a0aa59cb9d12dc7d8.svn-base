#!/bin/bash

ref=exp/tri6_nnet_ali/bound_det_valid_5/data.svm
hyp=exp/linear_bound_det/valid_5.ext.predict

cut -f 1 -d' ' $ref | paste - $hyp | perl -e '
  $n00 = 0;
  $n01 = 0;
  $n10 = 0;
  $n11 = 0;
  while (<>) {
      chomp;
      my @col = split(/\t/, $_);
      if ($col[0] == -1) {
          if ($col[1] == -1) {
              $n00++;
          } else {
              $n01++;
          }
      } else {
          if ($col[1] == -1) {
              $n10++;
          } else {
              $n11++;
          }
      }
  }
  print "\t\t0\t1\n";
  print "0\t$n00\t$n01\n";
  print "1\t$n10\t$n11\n";
  '
