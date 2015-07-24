
all:
EXTRA_CXXFLAGS = -Wno-sign-compare
include ../kaldi.mk

BINFILES = transform-info.chenzp convert-mrasta-feats-from-rasr

OBJFILES = 

TESTFILES =

ADDLIBS = ../feat/kaldi-feat.a ../transform/kaldi-transform.a ../gmm/kaldi-gmm.a \
         ../thread/kaldi-thread.a ../tree/kaldi-tree.a ../matrix/kaldi-matrix.a \
         ../util/kaldi-util.a ../base/kaldi-base.a

include ../makefiles/default_rules.mk

