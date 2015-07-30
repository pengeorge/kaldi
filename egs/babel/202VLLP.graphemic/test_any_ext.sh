#!/bin/bash
set -e

ext_set=' +FLP FLP+ FLP-colv8+FLP FLP '
for ext in $ext_set; do
  echo "Processing ext: $ext"
  if [ ! -f exp/tri5/decode_dev10h.pem_${ext}/.done.score ]; then
    if [ ! -f data/extra_lexicon/$ext ] || [ ! -f data/extra_text/$ext ]; then
      if [[ $ext =~ '+' ]]; then
        lex=${ext%%+*}
        #echo "ext: $ext lex=$lex"
        text=${ext##*+}
        #echo "ext: $ext text=$text"
        if [ -z "$lex" ]; then
          lex=VLLP
        fi
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
        ln -sf $text data/extra_text/$ext
      else
        echo "$ext not exist in extra_lexicon or extra_text"
        exit 1;
      fi
    fi

    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext} --do-ext-lexicon true --merge-lexicon true --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true
  fi
done



exit 0;





# ext_lexicon (merge lexicon with VLLP)
normal_set=
ol_set=
mix_lex_set=" FLP-colv8 FLP-bbnC FLP-bbnC-colv8 "
#"bbnut02 bbnut02c50 bbnut05c100s02e05 colut05c100s02e05 colut02 colut02c50 "
for ext in $normal_set; do
  if [ ! -f exp/tri5/decode_dev10h.pem_${ext}/.done.score ]; then
    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext} --do-ext-lexicon true --merge-lexicon true --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true
  fi
done

# original_lexicon
for ext in $ol_set; do
  if [ ! -f exp/tri5/decode_dev10h.pem_${ext}OL/.done.score ]; then
    ln -sf ${ext} data/extra_lexicon/${ext}OL
    ln -sf ${ext} data/extra_text/${ext}OL
    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext}OL --do-ext-lexicon false --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true
  fi
done

# mix_lexicon_only (merge other extra_lexicon, text is the same with ext1)

for ext in $ext_lex_set; do
  if [ ! -f exp/tri5/decode_dev10h.pem_${ext}/.done.score ]; then
    ext1=`echo $ext | sed 's/^\(.*\)\-\([^\-]*\)$/\1/'`
    ext2=`echo $ext | sed 's/^\(.*\)\-\([^\-]*\)$/\2/'`
    cat data/extra_lexicon/$ext1 data/extra_lexicon/$ext2 | sort -u > data/extra_lexicon/
    ./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --ext ${ext} --do-ext-lexicon true --merge-lexicon true --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true
  fi
done

