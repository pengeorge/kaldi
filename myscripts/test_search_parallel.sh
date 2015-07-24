#!/bin/bash

czpScripts/kws/kws_search.chenzp.parallel.sh --stage 2 --parallel-thres-mem 0 --cmd 'queue.pl -q leave1.q@@allhosts -l ram_free=1700M,mem_free=1700M' --extraid IBM2_oov --max-states 150000 --min-lmwt 10 --skip-scoring false --max-lmwt 15 --indices-dir exp/tri6_nnet_mpe/decode_dev10h.pem_epoch1/kws_indices data/lang data/dev10h.pem exp/tri6_nnet_mpe/decode_dev10h.pem_epoch1

