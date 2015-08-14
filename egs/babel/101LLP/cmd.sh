# "queue.pl" uses qsub.  The options to it are
# options to qsub.  If you have GridEngine installed,
# change this to a queue you have access to.
# Otherwise, use "run.pl", which will run jobs locally
# (make sure your --num-jobs options are no more than
# the number of cpus on your machine.

#0) THU MSIIP cluster options
export trainsmall_cmd="run.pl" # local machine is the fastest one.
export train_cmd="queue.pl -q all.q@@allhosts -l ram_free=1200M,mem_free=1200M"
export acc_cmd="queue.pl -q word.q@@wordhosts -l ram_free=1200M,mem_free=1200M"
export decode_cmd="queue.pl -q all.q@@allhosts -l ram_free=1700M,mem_free=1700M"
export cuda_cmd="queue.pl -q gpu.q@@gpuhosts -l gpu=1"
export mkgraph_cmd="queue.pl -q all.q@@allhosts -l mem_free=4G,ram_free=4G"
#export proxy_cmd="queue.pl -q all.q@@allhosts -l ram_free=17G,mem_free=17G" # only for generate_proxy_keywords (Feb 28,2014)

#a) JHU cluster options
#export train_cmd="queue.pl -l arch=*64*"
#export decode_cmd="queue.pl -l arch=*64* -l ram_free=4G,mem_free=4G"
#export cuda_cmd="..."
#export mkgraph_cmd="queue.pl -l arch=*64* ram_free=4G,mem_free=4G"

#b) BUT cluster options
#export train_cmd="queue.pl -q all.q@@blade -l ram_free=1200M,mem_free=1200M"
#export decode_cmd="queue.pl -q all.q@@blade -l ram_free=1700M,mem_free=1700M"
#export decodebig_cmd="queue.pl -q all.q@@blade -l ram_free=4G,mem_free=4G"
#export cuda_cmd="queue.pl -q long.q@@pco203 -l gpu=1"
#export cuda_cmd="queue.pl -q long.q@pcspeech-gpu"
#export mkgraph_cmd="queue.pl -q all.q@@servers -l ram_free=4G,mem_free=4G"

#c) run it locally...
#export train_cmd=run.pl
#export decode_cmd=run.pl
#export cuda_cmd=run.pl
#export mkgraph_cmd=run.pl


