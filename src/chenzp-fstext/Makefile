
# make "all" the target.
all:

# Disable linking math libs because  not needed here.  Just for compilation speed.
# no, it's now needed for context-fst-test.
# MATHLIB = NONE

EXTRA_CXXFLAGS = -Wno-sign-compare

include ../kaldi.mk

TESTFILES = rescale-test rescale-dag-test

OBJFILES = 


LIBNAME = chenzp-fstext

# tree and matrix archives needed for test-context-fst
# matrix archive needed for push-special.
ADDLIBS =  ../tree/kaldi-tree.a ../matrix/kaldi-matrix.a \
           ../util/kaldi-util.a ../base/kaldi-base.a 

include ../makefiles/default_rules.mk
