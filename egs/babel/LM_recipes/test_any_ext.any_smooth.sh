#!/bin/bash
set -e

# chenzp 2015
# Generating required resource for some 'ext' types specifying the lexicon, text corpus, gram order and smoothing type. Optionally estimate N_true for new words.

datatype=dev10h.pem
vocab_sort_via_kws=false
lm_only=false
newvocab_or_fullvocab=true
ext_set=' +FLP.3gram-kn '
subword=false
ext_for_word_lm=  # if $subword, defined word ext here, default: `cat $ext | sed 's/HYB//'`

echo "$0 $@"

. ./utils/parse_options.sh

for ext_raw in $ext_set; do
  if [[ $ext_raw =~ \. ]]; then
    smooth=${ext_raw##*.}
    ext=${ext_raw%%.*}
  else
    smooth=
    ext=${ext_raw}
  fi
  if [[ $ext =~ '+' ]]; then
    lex=${ext%%+*}
    #echo "ext: $ext lex=$lex"
    text=${ext##*+}
    #echo "ext: $ext text=$text"
    if [ -z "$lex" ]; then
      lex=VLLP
    fi
  else
    lex=$ext
    text=$ext
  fi
  if [ ! -f exp/tri5/decode_${datatype}_${ext_raw}/.done.score ]; then
    echo "Processing ext: $ext_raw ---------------------------"
    if [ ! -f data/extra_lexicon/$ext ] || [ ! -f data/extra_text/$ext ]; then
      if [[ $ext =~ '+' ]]; then
        if [ ! -f data/extra_lexicon/$lex ]; then
          if [[ $lex =~ '-' ]]; then
            for t in `echo $lex | sed 's/-/ /g'`; do
              if [ ! -f data/extra_lexicon/$t ]; then
                echo "Component $t in $lex does not exist in extra_lexicon"
                exit 1;
              fi
            done
            (
              set -e;
              for t in `echo $lex | sed 's/-/ /g'`; do
                cat data/extra_lexicon/$t
              done
            ) | sort -u > data/extra_lexicon/$lex
          else
            echo "$lex does not exist in extra_lexicon"
            exit 1;
          fi
        fi
        if [ -z "$text" ]; then
          text=VLLP
        fi
        if [ ! -f data/extra_text/$text ]; then
          if [[ $text =~ '-' ]]; then
            for t in `echo $text | sed 's/-/ /g'`; do
              if [ ! -f data/extra_text/$t ]; then
                echo "Component $t in $text does not exist in extra_text"
                exit 1;
              fi
            done
            (
              set -e;
              for t in `echo $text | sed 's/-/ /g'`; do
                cat data/extra_text/$t
              done
            )  > data/extra_text/$text
          else
            echo "$text does not exist in extra_text"
            exit 1;
          fi
        fi
        ln -sf $lex data/extra_lexicon/$ext
        if [ -f data/extra_w2s/$lex ]; then
          ln -sf $lex data/extra_w2s/$ext
        fi
        ln -sf $text data/extra_text/$ext
      else
        echo "$ext not exist in extra_lexicon or extra_text"
        exit 1;
      fi
    fi
    
    # Test other smooth
    if [ ! -z $smooth ]; then
      ext_to_test=${ext}.${smooth}
      if [ ! -f data/srilm_${ext}/perplexities.txt ]; then
        ./run-4-ext-LEX-mix-LM-decode.sh --dir ${datatype} --ext ${ext} --do-ext-lexicon true --merge-lexicon true --lm-only true
      fi
      lm=`grep $(echo $smooth | sed 's/-/./g') data/srilm_${ext}/perplexities.txt | head -n 1 | cut -d' ' -f 1`
      if [ -z $lm ]; then
        lm=`ls data/srilm_${ext}/*$(echo $smooth | sed 's/-/./g')* | head -n 1`
      fi
      if [ ! -f "$lm" ]; then
        echo "No $smooth smoothing LM called $lm found in data/srilm_${ext}"
        echo ", available smoothing: "
        ls data/srilm_${ext}/*gram*
        continue
      fi
      if [ "`readlink -f data/srilm_${ext}/lm.gz`" == "`readlink -f $lm`" ]; then
        if [ ! -L data/srilm_${ext_to_test} ] && [ ! -d data/srilm_${ext_to_test} ]; then
          ln -sf srilm_${ext} data/srilm_${ext_to_test}
        fi
        echo "The requested LM is the same as the primary LM"
        if [ -f exp/tri5/decode_${datatype}_${ext}/.done.score ]; then
          echo ", and the primary LM is already tested. Skip."
          continue
        else
          echo ", test the primary LM instead."
          ext_to_test=${ext}
        fi
      else
        action=create
        for f in data/srilm_${ext}.*/lm.gz; do
          this_ext=`basename $(dirname $f) | sed 's/srilm_//'`
          if [ "`readlink -f $f`" == "`readlink -f $lm`" ]; then
            if [ ! -L data/srilm_${ext_to_test} ] && [ ! -d data/srilm_${ext_to_test} ]; then
              ln -sf srilm_${this_ext} data/srilm_${ext_to_test}
            fi
            echo "The requested LM is the same as another LM: ${this_ext}"
            if [ -f exp/tri5/decode_${datatype}_${this_ext}/.done.score ]; then
              echo ", and it is already tested. Skip."
              action=skip
            else
              echo ", test ${this_ext} instead."
              ext_to_test=${this_ext}
              action=runAnother
            fi
            break
          fi
        done
        if [ $action == skip ]; then
          continue
        fi
        if [ $action == create ]; then
          mkdir -p data/srilm_${ext_to_test}
          lm_src="`echo $lm | sed 's/data/../'`"

          ln -sf "$lm_src" data/srilm_${ext_to_test}/lm.gz
          ln -sf `dirname $lm_src`/vocab data/srilm_${ext_to_test}/vocab
          ln -sf ${ext} data/extra_lexicon/${ext_to_test}
        fi
      fi
    else
      ext_to_test=${ext}
    fi
    echo "ext_to_test: $ext_to_test"
    echo "ext_raw: $ext_raw"
    ./run-4-ext-LEX-mix-LM-decode.sh --dir ${datatype} --ext ${ext_to_test} --do-ext-lexicon true --merge-lexicon true --sys-to-decode "" --sys-to-kws-stt "" --skip-kws true --lm-only $lm_only
    if [ $ext_to_test != $ext_raw ]; then # create soft link for further mixing
      if [ ! -L data/srilm_${ext_raw} ] && [ ! -d data/srilm_${ext_raw} ]; then
        ln -s srilm_${ext_to_test} data/srilm_${ext_raw}
      fi
      if [ ! -L data/lang_${ext_raw} ] && [ ! -d data/lang_${ext_raw} ]; then
        ln -s lang_${ext_to_test} data/lang_${ext_raw}
      fi
    fi
  fi
  if $vocab_sort_via_kws; then
    if $subword; then
      if [ -z $ext_for_word_lm ]; then
        ext_for_word_lm=`echo ${ext_raw} | sed 's/HYB3//'`
      fi
      lang_dir=data/lang_${ext_for_word_lm}
      subword_options=" --subword $subword --ext-for-word-lm $ext_for_word_lm "
    else
      lang_dir=data/lang_${ext_raw}
      subword_options=" --subword $subword "
    fi
    if $newvocab_or_fullvocab; then
      kwlist_id=${lex}-exc-VLLP
    fi    
    if [ ! -f exp/tri5/decode_${datatype}_${ext_raw}/.done.kws.${kwlist_id} ]; then
      ./czpScripts/prep_lex/lexicon_subtraction.pl \
        $lang_dir/words.txt data/extra_lexicon/VLLP |\
        grep -v -F "<" | grep -v -F "#"  | \
        awk "{printf \"KW-NEWVOCAB-%05d %s\\n\", \$2, \$1 }" \
        > data/extra_kwlist/${kwlist_id}.txt

      (
       echo '<kwlist ecf_filename="kwlist.xml" language="" encoding="UTF-8" compareNormalize="lowercase" version="" >'
       awk '{ printf("  <kw kwid=\"%s\">\n", $1);
              printf("    <kwtext>"); for (n=2;n<=NF;n++){ printf("%s", $n); if(n<NF){printf(" ");} }
              printf("</kwtext>\n");
              printf("  </kw>\n"); }' < data/extra_kwlist/${kwlist_id}.txt
       echo '</kwlist>'
      ) > data/extra_kwlist/${kwlist_id}.xml || exit 1

      kws_options=" --oov-kws false "
      if $newvocab_or_fullvocab; then
        kws_options="$kws_options --vocab-kws false --extra-kws false --tmp-kws-key ${kwlist_id} --tmp-kwlist data/extra_kwlist/${kwlist_id}.xml "
      else
        kws_options="$kws_options --vocab-kws true --extra-kws true"
      fi
      ./run-4-ext-LEX-mix-LM-decode.sh --dir ${datatype} --ext ${ext_raw} --do-ext-lexicon true --merge-lexicon true --sys-to-decode " sat " --sys-to-kws-stt " sat "\
        --skip-kws false $kws_options \
        $subword_options
    fi
    if $newvocab_or_fullvocab; then
      kwsoutdir=exp/tri5/decode_${datatype}_${ext_raw}/${kwlist_id}_kws_15
      #kwsoutdir=$(grep ATWV exp/tri5/decode_${datatype}_${ext}/${kwlist_id}_kws_*/metrics.txt |\  
      #  sort -k 3 -nr | head -n 1 | cut -d':' -f 3 | xargs dirname) # we don't know KWS score actually...
    else
      kwsoutdir=exp/tri5/decode_${datatype}_${ext_raw}/fullvocab_kws_15
      #kwsoutdir=$(grep ATWV exp/tri5/decode_${datatype}_${ext}/fullvocab_kws_*/metrics.txt |\
      #  sort -k 3 -nr | head -n 1 | cut -d':' -f 3 | xargs dirname)
    fi
    if [ ! -f $kwsoutdir/Ntrue.txt ]; then
      ./czpScripts/kws/est_Ntrue.pl data/${datatype}_${ext_raw}/${kwlist_id}_kws/keywords.txt \
        $kwsoutdir/kwslist.unnormalized.xml \
        $kwsoutdir/Ntrue.txt
    fi
  fi
done



exit 0;


