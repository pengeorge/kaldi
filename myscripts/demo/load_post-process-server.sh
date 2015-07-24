#!/bin/bash
. path.sh
. demo.conf

post-process-kwslist-service.json --tree-output=$tree_output \
 --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=`cat $kwsdatadir/duration` \
 --segments=$kwsdatadir/../segments --normalize=$norm_method --duptime=$duptime --remove-dup=true --remove-NO=true \
 --map-utter=$kwsdatadir/utter_map --utter-id=$kwsdatadir/utter_id \
 --utter-one-best=$indexdir/utter_one_best --digits=3 $nj - &

sleep 10
chmod 777 /tmp/unix_domains/kws_demo.json

wait
