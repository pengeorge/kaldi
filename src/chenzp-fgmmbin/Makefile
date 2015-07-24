
all:
EXTRA_CXXFLAGS = -Wno-sign-compare
include ../kaldi.mk

BINFILES = # fgmm-global-acc-stats-multilang.chenzp (has bugs)


OBJFILES =



TESTFILES =

ADDLIBS = ../decoder/kaldi-decoder.a ../lat/kaldi-lat.a ../feat/kaldi-feat.a \
          ../transform/kaldi-transform.a ../gmm/kaldi-gmm.a ../thread/kaldi-thread.a \
		  ../hmm/kaldi-hmm.a ../tree/kaldi-tree.a ../matrix/kaldi-matrix.a  \
		  ../util/kaldi-util.a ../base/kaldi-base.a 

include ../makefiles/default_rules.mk
