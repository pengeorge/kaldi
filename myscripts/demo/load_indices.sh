#/bin/bash -v

# Copyright 2014  MSIIP, Tsinghua University (Author: Zhipeng Chen)
# Apache 2.0.

set -e
set -o pipefail

runat=/home/kaldi/code/kaldi-trunk/egs/babel/bnbc
echo $0 "$@" > /dev/null
pushd $runat > /dev/null
. ./demo.conf || exit 1;
. ./lang.conf || exit 1;

help_message="Usage: $0"

[ -f ./path.sh ] && . ./path.sh; # source the path.
. ./utils/parse_options.sh

if [ $# -ne 0 ]; then
  printf "FATAL: invalid number of arguments.\n\n"
  printf "$help_message\n"
  exit 1;
fi

for f in $indexdir/index.1.gz; do
  [ ! -f $f ] && echo "No index $f" && exit 1;
done

rm -f $indexdir/load_log/q/*
load_id=`date | md5sum | cut -d' ' -f 1`
if [ -z "$nj" ]; then
    nj=`cat $indexdir/num_jobs` || exit 1;
fi
($load_indices_cmd JOB=1:$nj $indexdir/load_log/kws-server.$load_id.JOB.log \
  kws-search-service --negative-tolerance=-1 \
  $indexdir JOB || exit 1) &

sleep 10 

declare -a arr_hosts
declare -a arr_ids
list=`qstat | grep 'kws-server' | sed 's:  \+: :g' | cut -f 11,9 -d' ' | sed 's:service.q@::' | sed 's:.msiip.thu.::'`
ids=`echo "$list" | cut -f 2 -d' '`
hosts=`echo "$list" | cut -f 1 -d' '`
idxnum=`echo "$list" | wc -l`
i=0
for id in $ids; do
    arr_ids[$i]=$id
    i=$[$i+1]
done
i=0
for host in $hosts; do
    arr_hosts[$i]=$host
    i=$[$i+1]
done
(echo 'declare -a id2host'; \
 echo 'id2host=('; \
 for i in `seq 0 $[$idxnum-1]`; do \
   echo "  [${arr_ids[$i]}]=${arr_hosts[$i]}"; \
 done; \
 echo ')') > ./id2host.conf 
echo "$idxnum indices loaded."

popd >/dev/null
