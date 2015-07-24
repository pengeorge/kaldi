
all:
EXTRA_CXXFLAGS = -Wno-sign-compare
include ../kaldi.mk

BINFILES = init-ubm-multilang.chenzp

OBJFILES =



TESTFILES =


ADDLIBS = ../decoder/kaldi-decoder.a ../lat/kaldi-lat.a  ../feat/kaldi-feat.a \
	../sgmm/kaldi-sgmm.a ../transform/kaldi-transform.a ../gmm/kaldi-gmm.a \
	../hmm/kaldi-hmm.a ../tree/kaldi-tree.a ../matrix/kaldi-matrix.a  \
	../thread/kaldi-thread.a ../util/kaldi-util.a ../base/kaldi-base.a 

include ../makefiles/default_rules.mk
