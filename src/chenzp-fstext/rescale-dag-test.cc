// fstext/rescale-test.cc

// Copyright 2009-2011  Microsoft Corporation

// See ../../COPYING for clarification regarding multiple authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
// WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
// MERCHANTABLITY OR NON-INFRINGEMENT.
// See the Apache 2 License for the specific language governing permissions and
// limitations under the License.

#include "chenzp-fstext/rescale-dag.h"
#include "fstext/fstext-utils.h"
#include "fstext/fst-test-utils.h"
// Just check that it compiles, for now.

namespace fst
{


template<class Arc> void TestComputeTotalWeight() {
  typedef typename Arc::Weight Weight;
  VectorFst<Arc> *fst = RandFst<Arc>();

  std::cout <<" printing FST at start\n";
  {
#ifdef HAVE_OPENFST_GE_10400
    FstPrinter<Arc> fstprinter(*fst, NULL, NULL, NULL, false, true, "\t");
#else
    FstPrinter<Arc> fstprinter(*fst, NULL, NULL, NULL, false, true);
#endif
    fstprinter.Print(&std::cout, "standard output");
  }

  Weight tot = ComputeDagTotalWeight(*fst);
  std::cout << "Total weight is: " << tot.Value() << '\n';

  delete fst;
}



void TestRescaleToStochastic() {
  typedef LogArc Arc;
  typedef Arc::Weight Weight;
  RandFstOptions opts;
  opts.allow_empty = false;
  VectorFst<Arc> *fst = RandFst<Arc>(opts);

  std::cout <<" printing FST at start\n";
  {
#ifdef HAVE_OPENFST_GE_10400
    FstPrinter<Arc> fstprinter(*fst, NULL, NULL, NULL, false, true, "\t");
#else
    FstPrinter<Arc> fstprinter(*fst, NULL, NULL, NULL, false, true);
#endif
    fstprinter.Print(&std::cout, "standard output");

  }
  float diff = 0.001;
  RescaleDagToStochastic(fst);
  Weight tot = ShortestDistance(*fst),
      tot2 = ComputeDagTotalWeight(*fst);
  std::cerr <<  " tot is " << tot<<", tot2 = "<<tot2<<'\n';
  assert(ApproxEqual(tot2, Weight::One(), diff));

  delete fst;
}


} // end namespace fst


int main() {
  using namespace fst;
  for (int i = 0;i < 10;i++) {
    std::cout << "Testing with tropical\n";
    fst::TestComputeTotalWeight<StdArc>();
    std::cout << "Testing with log:\n";
    fst::TestComputeTotalWeight<LogArc>();
  }
  for (int i = 0;i < 10;i++) {
    std::cout << "i = "<<i<<'\n';
    fst::TestRescaleToStochastic();
  }
}
