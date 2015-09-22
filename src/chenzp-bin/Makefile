
all:
EXTRA_CXXFLAGS = -Wno-sign-compare
include ../kaldi.mk

BINFILES = map-multi-model-pdf map-multi-model-phone sum-multi-model-lda-accs pdf-map-view acc-phone-lda

OBJFILES =

ADDLIBS = ../lm/kaldi-lm.a ../decoder/kaldi-decoder.a ../lat/kaldi-lat.a \
          ../hmm/kaldi-hmm.a ../transform/kaldi-transform.a ../gmm/kaldi-gmm.a \
	      ../tree/kaldi-tree.a ../matrix/kaldi-matrix.a  ../util/kaldi-util.a \
          ../base/kaldi-base.a  ../thread/kaldi-thread.a \
					../chenzp-transform/chenzp-transform.a


TESTFILES =

include ../makefiles/default_rules.mk

