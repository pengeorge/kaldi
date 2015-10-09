#!/bin/bash

cat data/dev10h.seg/NIST_kws/keywords.txt | perl -e '
    open(W, "<data/lang/phones/align_lexicon.txt") || die "Fail to open lexicon\n";
    my %lexicon;
    while (<W>) {
      chomp;
      my @col = split();
      @col >= 2 || die "'$0': Bad line in lexicon: $_\n";
      $lexicon{$col[0]} = scalar(@col)-2;
    }
    print "kwid,len\n";
    while (<STDIN>) {
      chomp;
      my $line = $_;
      my @col = split();
      @col >= 2 || die "Bad line in keywords file: $_\n";
      my $len = 0;
      for (my $i = 1; $i < scalar(@col); $i ++) {
        $col[$i] =~ tr/[A-Z]/[a-z]/;
        if (defined($lexicon{$col[$i]})) {
          $len += $lexicon{$col[$i]};
        } else {
          print STDERR "'$0': No pronunciation found for word: $col[$i]\n";
        }
      }
      print "$col[0],$len\n"
    }' > data/dev10h.seg/NIST_kws/kw_phone_count.csv 
