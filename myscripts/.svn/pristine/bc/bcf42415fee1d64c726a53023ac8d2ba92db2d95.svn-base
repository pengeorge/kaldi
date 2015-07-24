#!/bin/perl -w
# Author: chenzp (Dec 30, 2013)
package libCase;

@EXPORT=qw(tolower);
#use utf8;
#use feature 'unicode_strings';
use Encode;
sub ::tolower {
    my ($str) = @_;
    ## Vietnamese
    # $str =~ tr/A-ZĂÂĐÊÔƠƯÀẰẦÈỀÌÒỒỜÙỪỲẢẲẨẺỂỈỎỔỞỦỬỶÃẴẪẼỄĨÕỖỠŨỮỸÁẮẤÉẾÍÓỐỚÚỨÝẠẶẬẸỆỊỌỘỢỤỰỴ/\
    #            a-zăâđêôơưàằầèềìòồờùừỳảẳẩẻểỉỏổởủửỷãẵẫẽễĩõỗỡũữỹáắấéếíóốớúứýạặậẹệịọộợụựỵ/;
    # $str =~ tr/A-ZĂÂĐÊÔƠƯÀẰẦÈỀÌÒỒỜÙỪỲẢẲẨẺỂỈỎỔỞỦỬỶÃẴẪẼỄĨÕỖỠŨỮỸÁẮẤÉẾÍÓỐỚÚỨÝẠẶẬẸỆỊỌỘỢỤỰỴ/a-zăâđêôơưàằầèềìòồờùừỳảẳẩẻểỉỏổởủửỷãẵẫẽễĩõỗỡũữỹáắấéếíóốớúứýạặậẹệịọộợụựỵ/;
    $str = encode('utf8', lc(decode('utf8',$str)));
    return $str;
}

