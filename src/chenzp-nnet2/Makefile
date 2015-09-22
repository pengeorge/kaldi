

all:

include ../kaldi.mk

LDFLAGS += $(CUDA_LDFLAGS)
LDLIBS += $(CUDA_LDLIBS)


TESTFILES = 

OBJFILES = nnet-functions-ext.o

LIBNAME = chenzp-nnet2

ADDLIBS = ../thread/kaldi-thread.a ../lat/kaldi-lat.a ../gmm/kaldi-gmm.a \
      ../hmm/kaldi-hmm.a ../tree/kaldi-tree.a ../transform/kaldi-transform.a \
      ../cudamatrix/kaldi-cudamatrix.a ../matrix/kaldi-matrix.a \
      ../base/kaldi-base.a  ../util/kaldi-util.a 

include ../makefiles/default_rules.mk
