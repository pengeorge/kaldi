#This script is not really supposed to be run directly 
#Instead, it should be sourced from the decoding script
#It makes many assumption on existence of certain environmental
#variables as well as certain directory structure.

# TODO A better way to split kwlist is to use a unique splitting version
# , since different splits in different systems will cause multi-entries
# of some keywords.
  splitdir=$kwsdatadir/split${kwlist_nj}
  if [ ! -f $splitdir/.done ]; then
    mkdir -p $splitdir
    if [ -f $kwsdatadir/keywords.txt ]; then
      cut -f 1 $kwsdatadir/keywords.txt > $splitdir/kwlist
    elif [[ `basename $kwsdatadir` =~ ^oov ]] && [ -f $kwsdatadir/keywords_proxy.txt ]; then # in case of phone system, where keywords.txt is not generated and kwlist.xml contains all queries
      cut -f 1 $kwsdatadir/keywords_proxy.txt > $splitdir/kwlist
    elif [ -f $kwsdatadir/kwlist.xml ]; then
      grep -Po '(?<=kwid=")[^"]+(?=")' $kwsdatadir/kwlist.xml > $splitdir/kwlist
    else
      echo "Both keywords.txt and kwlist.xml are missing... How can I split kwlist?? Please fix this bug."
      exit 1;
    fi
    for k in `seq 1 $kwlist_nj`; do
      split -n l/$k/$kwlist_nj $splitdir/kwlist > $splitdir/kwlist.$k
    done
    touch $splitdir/.done
  fi
