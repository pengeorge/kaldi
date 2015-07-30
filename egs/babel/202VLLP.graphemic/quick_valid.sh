#!/bin/bash
set -e

./run-1-main-VLLP.chenzp.sh --tri5-only true

./run-4-ext-LEX-mix-LM-decode.sh --dir dev10h.pem --sys-to-decode " sat " --sys-to-kws-stt " sat " --skip-kws true

echo "==== SAT STT perfornance ============="
grep Sum exp/tri5/decode_dev10h.pem/score_*/*.sys
