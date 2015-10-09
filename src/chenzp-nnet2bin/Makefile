
all:
EXTRA_CXXFLAGS = -Wno-sign-compare -g
include ../kaldi.mk

LDFLAGS += $(CUDA_LDFLAGS)
LDLIBS += $(CUDA_LDLIBS)

BINFILES = nnet-latgen-faster-parallel.chenzp nnet-am-fix-shallow-affines nnet-info \
					 nnet-extend-const-component nnet-reset-const-component nnet-insert-and-resize \
					 nnet-am-full-info

OBJFILES =

# Add this dependency to force cuda-compiled.o to be rebuilt when we reconfigure.
cuda-compiled.o: ../kaldi.mk


TESTFILES =

ADDLIBS = ../nnet2/kaldi-nnet2.a ../chenzp-nnet2/chenzp-nnet2.a ../nnet/kaldi-nnet.a ../gmm/kaldi-gmm.a \
         ../decoder/kaldi-decoder.a ../lat/kaldi-lat.a ../hmm/kaldi-hmm.a  \
         ../transform/kaldi-transform.a ../tree/kaldi-tree.a ../thread/kaldi-thread.a \
         ../cudamatrix/kaldi-cudamatrix.a ../matrix/kaldi-matrix.a \
         ../fstext/kaldi-fstext.a ../util/kaldi-util.a ../base/kaldi-base.a 

include ../makefiles/default_rules.mk
