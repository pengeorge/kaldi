
all:

EXTRA_CXXFLAGS = -Wno-sign-compare
include ../kaldi.mk

BINFILES = kws-search-service kws-search-client \
			 post-process-kwslist post-process-kwslist-service post-process-kwslist-client \
			 post-process-kwslist-service.json \
			 generate-proxy-keywords.chenzp generate-proxy-keywords.no-self-prior.chenzp \
			 generate-proxy-keywords.old generate-proxy-keywords.new.chenzp generate-proxy-keywords-log \
			 generate-proxy-keywords.LM-support.chenzp

OBJFILES =



TESTFILES =


ADDLIBS = ../kws/kaldi-kws.a ../lat/kaldi-lat.a ../fstext/kaldi-fstext.a \
        ../hmm/kaldi-hmm.a ../tree/kaldi-tree.a ../matrix/kaldi-matrix.a \
        ../util/kaldi-util.a ../base/kaldi-base.a \
				../chenzp-util/chenzp-util.a

include ../makefiles/default_rules.mk
