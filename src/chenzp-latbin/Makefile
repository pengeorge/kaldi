
all:

EXTRA_CXXFLAGS = -Wno-sign-compare
include ../kaldi.mk

BINFILES = lattice-oracle-cer.chenzp lattice-amrescore

OBJFILES =



TESTFILES =

ADDLIBS = ../lat/kaldi-lat.a ../lm/kaldi-lm.a ../hmm/kaldi-hmm.a \
          ../tree/kaldi-tree.a ../util/kaldi-util.a ../matrix/kaldi-matrix.a \
          ../thread/kaldi-thread.a ../base/kaldi-base.a ../fstext/kaldi-fstext.a

include ../makefiles/default_rules.mk

