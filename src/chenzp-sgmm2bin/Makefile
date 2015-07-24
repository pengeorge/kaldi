
all:
EXTRA_CXXFLAGS = -Wno-sign-compare
include ../kaldi.mk

BINFILES = sgmm2-acc-shared-stats.chenzp sgmm2-sum-shared-accs.chenzp sgmm2-est-shared.chenzp sgmm2-aggregate-shared-accs.chenzp sgmm2-init.chenzp

OBJFILES =



TESTFILES =


ADDLIBS =  ../decoder/kaldi-decoder.a ../lat/kaldi-lat.a ../feat/kaldi-feat.a \
	../sgmm2/kaldi-sgmm2.a ../transform/kaldi-transform.a ../gmm/kaldi-gmm.a \
	../hmm/kaldi-hmm.a ../tree/kaldi-tree.a ../matrix/kaldi-matrix.a  \
	../thread/kaldi-thread.a ../util/kaldi-util.a ../base/kaldi-base.a 

include ../makefiles/default_rules.mk
