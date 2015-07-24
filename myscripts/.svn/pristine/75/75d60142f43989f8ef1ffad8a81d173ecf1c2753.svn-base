#!/bin/bash

dir=exp/train_g2p
train=data/local/lang/align_lexicon.txt
pos_depend_phone=true
g2p_order=6
[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;
if [ $# != 1 ]; then
    echo "Usage: $0 <kws-data-dir>"
    echo "[Options]"
    echo "  --pos-depend-phone true/false (default: true)"
    exit 1;
fi
kwsdatadir=$1

if [ ! -d $dir/log ]; then
    mkdir -p $dir/log
fi

if [ ! -e $dir/model-$g2p_order ]; then
    echo "Unigram model training..."
    log=$dir/log/model1.log
    # false &&
    {
    g2p.py --train $train --devel 5% --write-model $dir/model-1 >> $log || exit 1
    
    for k in $(seq 2 $g2p_order); do
        log=$dir/log/model$k.log
        echo "Higher order model training ($k/$g2p_order) ..."
        echo "# Started at `date`" > $log
        g2p.py --model $dir/model-$(($k-1)) --ramp-up --train $train --devel 5% --write-model $dir/model-$k >> $log || exit 1
        echo "# Ended at `date`" >> $log
    done
    }
    
    #false &&
    {
    for k in $(seq 1 $g2p_order); do
        eval=$dir/model$k.eval
        echo "Evaluating model-$k..."
        g2p.py --model $dir/model-$k --test $train > $eval || exit 1
    done
    }
fi

#false &&
{
echo "Generating OOV lexicon by model-$g2p_order"
cat $kwsdatadir/keywords.txt | perl -e '
    require "czpScripts/utils/libCase.pl";
    open(LEX,"'$train'") or die "Cannot open lexicon file '$train'\n";
    my %lex;
    my %oov;
    while (<LEX>) {
        chomp;
        my @col = split();
        $lex{$col[0]} = 1;
    }
    close(LEX);
    while (<>) {
        chomp;
        my @col = split(/\t/);
        my $kw = &tolower($col[1]);
        @col = split(/ /, $kw);
        for (@col) {
            if (!defined($lex{$_})) {
                $oov{$_} = 1;
            }
        }
    }
    for (sort keys %oov) {
        print "$_\n";
    }' | g2p.py --model $dir/model-$g2p_order --apply - > $kwsdatadir/oov.g2p

## only for self-created kwlist
#cat $kwsdatadir/kwlist.txt | sed -n '/^\\oov/,$p' |\  
#  perl -e '
#    open(LEX,"'$train'") or die "Cannot open lexicon file '$train'\n";
#    my %lex;
#    my %oov;
#    while (<LEX>) {
#        chomp;
#        my @col = split();
#        $lex{$col[0]} = 1;
#    }
#    close(LEX);
#    while (<>) {
#        chomp;
#        if (/^\\/) {
#            next;
#        }
#        my @col = split(/[ \t]/);
#        pop @col;
#        for (@col) {
#            if (!defined($lex{$_})) {
#                $oov{$_} = 1;
#            }
#        }
#    }
#    for (sort keys %oov) {
#        print "$_\n";
#    }' | g2p.py --model $dir/model-$g2p_order --apply - > $kwsdatadir/oov.g2p
}

if [ $pos_depend_phone == 'true' ]; then
    cat $kwsdatadir/oov.g2p | perl czpScripts/kws/fix-lex-as-pos-depend.pl > $kwsdatadir/oov.lex
else
    cp $kwsdatadir/oov.g2p $kwsdatadir/oov.lex
fi

