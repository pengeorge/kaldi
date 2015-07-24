#!/bin/perl -w
use strict;
use XML::Simple;
use Data::Dumper;

if ($#ARGV != 2) {
    die "USAGE: $0 <kws-data-dir> <all_kwlist> <lexicon>\n";
}

my $kwsdatadir = shift @ARGV;
my $kwlist = shift @ARGV;
my $lex = shift @ARGV;

my %lex;
open(LEX, "$lex") or die "Cannot open lexicon file $lex\n";
while (<LEX>) {
    chomp;
    my @col = split();
    $lex{$col[0]} = 1;
}
close(LEX);

my $kwxs = XML::Simple->new(ForceArray=>1, KeyAttr=>{kw=>"kwid"});
my $kwxml = $kwxs->XMLin($kwlist);

my %kws = %{$kwxml->{kw}};

my %ivxml;
my %oovxml;

$ivxml{$_} = $kwxml->{$_} foreach keys %$kwxml;
$oovxml{$_} = $kwxml->{$_} foreach keys %$kwxml;
undef $ivxml{kw};
undef $oovxml{kw};
%{$ivxml{kw}} = ();
%{$oovxml{kw}} = ();

#print Dumper($kwxml)."\n";
#print Dumper(\%ivxml)."\n";
#print Dumper(\%kws)."\n";
my $ivnum = 0;
my $oovnum = 0;
for my $key (sort keys %kws) {
    #print $kws{$key}->{kwtext}[0]."\n";
    my $isiv = 0;
    my $kwtext = $kws{$key}->{kwtext}[0];
    if (defined($lex{$kwtext})) {
        $isiv = 1;
    } else {
        $isiv = 1;
        my @col = split(/\s+/, $kwtext);
        #print scalar @col." $kwtext\n";
        for (@col){
            if (!defined($lex{$_})) {
                $isiv = 0;
                last;
            }
        }
    }
    if ($isiv == 1) {
        $ivxml{kw}->{$key} = $kws{$key};
        $ivnum++;
    } else {
        $oovxml{kw}->{$key} = $kws{$key};
        $oovnum++;
    }
}
print "ivnum=$ivnum\n";
print "oovnum=$oovnum\n";

my $ivout = XML::Simple->new(ForceArray=>1, RootName=>"kwlist");
my $outname = $kwlist;
if ($outname !~ s/\.kwlist\.xml$/_invocab.kwlist.xml/) {
    $outname =~ s/\.xml$/_invocab.xml/;
}
$outname = `dirname $kwlist`;
chomp($outname);
$outname .= "/kwlist_invocab.xml";
$ivout->XMLout(\%ivxml, KeyAttr=>{kw=>'kwid'}, outputfile=>$outname);
my $oovout = XML::Simple->new(ForceArray=>1, RootName=>"kwlist");
$outname = $kwlist;
if ($outname !~ s/\.kwlist\.xml$/_outvocab.kwlist.xml/) {
    $outname =~ s/\.xml$/_outvocab.xml/;
}
$outname = `dirname $kwlist`;
chomp($outname);
$outname .= "/kwlist_outvocab.xml";
$oovout->XMLout(\%oovxml, KeyAttr=>{kw=>'kwid'}, outputfile=>$outname);
