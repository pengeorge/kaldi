#!/bin/bash

org=exp/tri6_nnet_ali/bound_det_train_5/data.svm
dir=`dirname $org`
ext=$dir/data_ext.svm

num0=`grep -P '^\-1' $org | wc -l`
grep -P '^\+1' $org > $dir/data1.svm
num1=`cat $dir/data1.svm | wc -l`
num=`cat $org | wc -l`

echo "Total: $num (1: $num1, 0: $num0)"
echo "Num0/Num1 = "`perl -e "print $num0/$num1"`

repeat=`perl -e "printf(\"%d\", $num0/$num1+0.5);"`

cp $org $ext
for i in `seq 2 $repeat`; do
    cat $dir/data1.svm >> $ext
done
