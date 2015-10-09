#!/bin/bash

src_lex=
src_text=
ext=
lexicon_extension=false
exclude_non_native=true # If true, remove 
hes_pron="A	E	A m	u m"
nj=192

[ ! -f ./lang.conf ] && echo 'Language configuration does not exist! Use the configurations in conf/lang/* as a startup' && exit 1
[ ! -f ./conf/common_vars.sh ] && echo 'the file conf/common_vars.sh does not exist!' && exit 1

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;

[ -f local.conf ] && . ./local.conf

. ./utils/parse_options.sh

set -e
set -o pipefail  #Exit if any of the commands in the pipeline will 
                 #return non-zero return code
if [ -z "$src_lex" ] || [ -z "$char_phone_map" ] \
   || [ -z "$ext" ]; then
  echo "Options error"
  exit 1;
fi
if [[ "$lexiconFlags" =~ romanized ]]; then # we don't do romanization when generating pronunciation automatically, this should always be false
  scol=3
  roman_flag=true
else
  scol=2
  roman_flag=
fi

dir=exp/prep_lex/$ext
mkdir -p ${dir}

### Clean raw lexicon
if [ ! -f ${dir}/raw_lexicon.txt ]; then
  awk '{if(NF>1){print $0;}}' $src_lex > ${dir}/raw_lexicon.txt
  if ! $stress_in_phone; then
    mv ${dir}/raw_lexicon.txt ${dir}/raw_lexicon.with_stress.txt
    tr -d '"%' < ${dir}/raw_lexicon.with_stress.txt |\
      sed 's:  \+: :g' > ${dir}/raw_lexicon.txt
  else
    echo "NOT Supported!! stress_in_phone=true"
    echo "This requires syllable separator."
    exit 1;
  fi
  sed -i.bak '/*/d' ${dir}/raw_lexicon.txt
fi
### Replace '=' with '-', to avoid problem in phoneme mapping
sed -i.no_replace_equal 's/=/-/g' ${dir}/raw_lexicon.txt

### Fix compounded letters pronunciation
if [ ! -z "$letter_pron_file" ]; then
  if [ ! -f $letter_pron_file ]; then
    echo "letter_pron_file: $letter_pron_file not exist"
    exit 1;
  fi
  mv ${dir}/raw_lexicon.txt ${dir}/raw_lexicon.not_fixed.txt
  cat ${dir}/raw_lexicon.not_fixed.txt | perl -e '
    my %letter_pron;
    open(LE, "<'$letter_pron_file'") or die;
    while (<LE>) {
      chomp;
      my @col = split(/\t/, $_);
      if (@col != 2) { die "Bad line of file: '$letter_pron_file'\n$_\n"; }
      $letter_pron{$col[0]} = $col[1];
    }
    close(LE);
    my %first_pron;
    my %line;
    while (<STDIN>) {
      chomp;
      my @col = split(/\t/, $_);
      $first_pron{$col[0]} = $col[1];
      $line{$col[0]} = $_
    }
    foreach my $w (keys %line) {
      if ($w =~ m/[_-]/) {
        my @col = split(/[_-]/, $w);
        my $fail = 0;
        for (my $i=0; $i < @col; $i++) {
          if ($col[$i] =~ m/^[A-Za-z]$/) {
            $col[$i] =~ tr/a-z/A-Z/;
            $col[$i] = $letter_pron{$col[$i]};
          } elsif (defined($first_pron{$col[$i]})) {
            $col[$i] = $first_pron{$col[$i]};
          } else {
            print STDERR "[WARN] Word $w is removed because the compound $col[$i] has no pronunciation\n";
            $fail = 1;
            break;
          }
        }
        if ($fail == 0) {
          print "$w\t".join(" ", @col)."\n";
        }
      } else {
        print "$line{$w}\n";
      }
    }' > ${dir}/raw_lexicon.txt
fi

### Add <hes>
if [ ! -z "$hes_pron" ] && [ `grep -P "^<hes>\t" ${dir}/raw_lexicon.txt | wc -l` -eq 0 ]; then
  echo "<hes>	$hes_pron" >> ${dir}/raw_lexicon.txt
fi

### Filter lexicon
if [ ! -f ${dir}/filtered_raw_lexicon.txt ]; then
  if ! $lexicon_extension; then
    echo =========================================
    echo "Filtering by transcription..."
    czpScripts/local/make_lexicon_subset.chenzp.sh --case_insensitive $case_insensitive $train_data_trans_dir ${dir}/raw_lexicon.txt ${dir}/filtered_raw_lexicon.txt
    echo "`cat ${dir}/filtered_raw_lexicon.txt | wc -l` remained"
  else
    ln -s raw_lexicon.txt ${dir}/filtered_raw_lexicon.txt
  fi
fi

### Get phone list in LSP doc.
awk '{print $NF}' $char_phone_map | sed 's:\~:\n:g' | sort -u | sed 's/=/-/g' > ${dir}/LSP_phone_list.txt

echo $phoneme_mapping | sed "s: \+: :g" | sed "s: *; *:;:g" | tr ';' '\n' | sed "s: *= *:\t:g"| sed 's: \+$::' > ${dir}/phoneme_mapping

if [ ! -f ${dir}/phone_list.txt ]; then
  echo =========================================
  echo "Generating phone list..."
  cut -f ${scol}- ${dir}/filtered_raw_lexicon.txt |\
    tr ' \t' '\n' | sort -u | grep -v '^[\.#]$' > ${dir}/lex_phone_list.txt
  num_lex=`wc -l ${dir}/lex_phone_list.txt | cut -d' ' -f1`
  num_lsp=`wc -l ${dir}/LSP_phone_list.txt | cut -d' ' -f1`
  echo "$num_lex phones in lexicon. $num_lsp phones in LSP doc."
  set +e;
  grep -Fxv -f ${dir}/lex_phone_list.txt ${dir}/LSP_phone_list.txt > ${dir}/missing_phones
  grep -Fxv -f ${dir}/LSP_phone_list.txt ${dir}/lex_phone_list.txt > ${dir}/extra_phones
  set -e;
  num_miss=`wc -l ${dir}/missing_phones | cut -d' ' -f1`
  num_extra=`wc -l ${dir}/extra_phones | cut -d' ' -f1`
  #if [ $(($num_miss+$num_lex)) -ne $num_lsp ]; then
  echo "Warning: Phone number does not match. $num_miss phones in LSP are missing in lexicon, found $num_extra extra phones in lexicon"
  rm -f ${dir}/extra_but_in_map_from
  touch ${dir}/extra_but_in_map_from
  if [ $num_extra -gt 0 ]; then
    for p in `cat ${dir}/extra_phones`; do
      if [ `cut -f 1 ${dir}/phoneme_mapping | grep -Fx "$p" | wc -l` -gt 0 ]; then # if this extra phone has been mapped
        #echo "Extra phone $p will be mapped to other phones"
        echo "$p" >> ${dir}/extra_but_in_map_from
      else
        echo "[WARNING] Extra phone $p was not mapped. You may want to specify a mapping rule in lang.conf to reduce #phones."
      fi
    done
  fi
  rm -f ${dir}/missing_but_in_map_from
  touch ${dir}/missing_but_in_map_from
  if [ $num_miss -gt 0 ]; then
    for p in `cat ${dir}/missing_phones`; do
      if [ `cut -f 1 ${dir}/phoneme_mapping | grep -F "$p" | wc -l` -gt 0 ]; then # if this missing phone has been mapped
        echo "Missing phone $p has been mapped to other phones"
        echo "$p" >> ${dir}/missing_but_in_map_from
      else
        echo "[WARNING] Missing phone $p was not mapped. You may want to specify a mapping rule in lang.conf, otherwise when doing lexicon extension, words containing this phone will be removed."
        #exit 1;
      fi
    done
  fi
  set +e
  cut -f 2- ${dir}/phoneme_mapping | tr ' ' "\n" | sort -u > ${dir}/map_to
  grep -Fxv -f ${dir}/lex_phone_list.txt ${dir}/map_to > ${dir}/unknown_phones_in_map_to
  set -e
  #for p in $map_to; do
  #  if [ `grep $(echo "$p" | sed 's/\\/\\\\/g') ${dir}/phone_list.txt | wc -l` -eq 0 ]; then
  if [ `cat ${dir}/unknown_phones_in_map_to | wc -l` -gt 0 ]; then
    echo "These phones in map_to is missing in lex phone list. You should modify the mapping rules."
    cat ${dir}/unknown_phones_in_map_to
    exit 1;
  fi
  cat ${dir}/lex_phone_list.txt ${dir}/missing_but_in_map_from > ${dir}/phone_list.txt
  echo "`cat ${dir}/phone_list.txt | wc -l` phones remained."
fi

if [ ! -f ${dir}/split$nj/.done.split ]; then
  echo =========================================
  echo "Splitting raw_lexicon into $nj pieces"
  mkdir -p ${dir}/split$nj
  split -n l/$nj -d -a 3 ${dir}/raw_lexicon.txt ${dir}/split$nj/raw_lexicon.
  for k in `seq 1 9`; do
    mv ${dir}/split$nj/raw_lexicon.00$k ${dir}/split$nj/raw_lexicon.$k
  done
  for k in `seq 10 99`; do
    mv ${dir}/split$nj/raw_lexicon.0$k ${dir}/split$nj/raw_lexicon.$k
  done
  mv ${dir}/split$nj/raw_lexicon.000 ${dir}/split$nj/raw_lexicon.$nj
  touch ${dir}/split$nj/.done.split
fi
if [ ! -f ${dir}/split$nj/.done.filter ]; then
  echo =========================================
  echo "Filtering splitted raw_lexicon by phone list"
  $train_cmd JOB=1:$nj ${dir}/log/filter_by_phone_list.JOB.log \
    cat ${dir}/split$nj/raw_lexicon.JOB \| \
    perl czpScripts/prep_lex/filter_by_phone_list.pl ${dir}/phone_list.txt ${dir}/phoneme_mapping $roman_flag '>' ${dir}/split$nj/filter-by-phone.raw_lexicon.JOB '2>' ${dir}/split$nj/not_covered.JOB \
    || exit 1;
  touch ${dir}/split$nj/.done.filter
fi
if [ ! -f ${dir}/.merged ]; then
  echo =========================================
  echo "Merging filtered.raw_lexicon..."
  cat ${dir}/split$nj/filter-by-phone.raw_lexicon.* > ${dir}/filter-by-phone.raw_lexicon.txt
  echo "`cat ${dir}/filter-by-phone.raw_lexicon.txt | wc -l` words remained"
  cat ${dir}/split$nj/not_covered.* | sort > ${dir}/not_covered.list
  cut -f 2 ${dir}/not_covered.list |\
    sort | uniq -c | sort -nr > ${dir}/not_covered_phone.txt
  touch ${dir}/.merged
fi
if [ ! -f ${dir}/$ext ] || [ ${dir}/$ext -ot ${dir}/filter-by-phone.raw_lexicon.txt ]; then
  echo =========================================
  echo "Sorting and output final lexicon (case_insensitive: $case_insensitive)"
  if $case_insensitive; then
    cat ${dir}/filter-by-phone.raw_lexicon.txt |\
      awk -F"\t" 'BEGIN{ORS=""}{print tolower($1); for(i=2;i<=NF;i++){ print "\t"$i;} print "\n";}' |\
      sort -u > ${dir}/$ext
  else
    sort -u ${dir}/filter-by-phone.raw_lexicon.txt > ${dir}/$ext
  fi
  echo "`cat ${dir}/$ext | wc -l` words remained"
fi
mkdir -p data/extra_lexicon
pushd data/extra_lexicon
ln -sf ../../${dir}/$ext
popd

if [ ! -z "$src_text" ]; then
  echo =========================================
  echo "Copying extra text (case_insensitive: $case_insensitive)"
  mkdir -p data/extra_text
  if $case_insensitive; then
    cat $src_text | tr A-Z a-z > data/extra_text/$ext
  else
    cp $src_text data/extra_text/$ext
  fi
fi

echo Done.

