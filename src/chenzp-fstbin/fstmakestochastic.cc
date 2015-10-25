// fstbin/fstmakestochastic.cc

// Copyright 2009-2011  Microsoft Corporation
// Copyright 2014  Tsinghua University (Author: Zhipeng Chen)

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

#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "util/kaldi-io.h"
#include "util/parse-options.h"
#include "fst/fstlib.h"
#include "fstext/fstext-utils.h"
#include "chenzp-fstext/rescale.h"
#include "fstext/fstext-utils.h"
#include "fstext/fst-test-utils.h"
#include "fstext/kaldi-fst-io.h"
// Just check that it compiles, for now.
int main(int argc, char **argv) {
  try {
    using namespace kaldi;
    using namespace fst;
    using kaldi::int32;

    const char *usage =
        "Rescale an FST on log semiring to make it stochastic.\n"
        "Prints out maximum error (in log units).\n"
        "\n"
        "Usage:  fstisstochastic [ in.fst [ out.fst ] ]\n";

    float delta = 0.01;
    float tot_weight = 0; // default value, which is 1.0 in real/prob semiring


    ParseOptions po(usage);
    po.Register("delta", &delta, "Maximum error to accept.");
    po.Register("total-weight", &tot_weight, "The objective total-weight (in log semiring) of FST.");
    po.Read(argc, argv);

    if (po.NumArgs() > 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string fst_in_filename = po.GetOptArg(1);
    std::string fst_out_filename = po.GetOptArg(2);

    typedef LogArc Arc;
    typedef Arc::Weight Weight;
    Weight rescale = Weight(tot_weight);
    if (ClassifyRspecifier(fst_in_filename, NULL, NULL) == kNoRspecifier) {
      VectorFst<StdArc> *fst_std = ReadFstKaldi(fst_in_filename);
      VectorFst<LogArc> *fst = new VectorFst<LogArc>;
      Cast(*fst_std, fst);

      //TODO this seems to be a wrong rescale, should rescale final states only.
      RescaleToStochastic(fst, delta);
      //Weight tot = ShortestDistance(*fst),
      Weight tot2 = ComputeTotalWeight(*fst, Weight(-log(2.0)));
      //std::cerr <<  " tot is " << tot<<", tot2 = "<<tot2<<'\n';
      if (ApproxEqual(tot2, Weight::One(), delta)) {
        std::cerr << "[WARNING] stochastication may fail: " << std::endl;
      }
      
      // Scaling to the specified total weight
      for (StateIterator<VectorFst<LogArc> > siter(*fst); !siter.Done(); siter.Next()) {
        Arc::StateId s = siter.Value();
        fst->SetFinal(s, Times(rescale, fst->Final(s)));
      }
      tot2 = ComputeTotalWeight(*fst, Weight(-log(2.0)));
      if (ApproxEqual(tot2, Times(Weight::One(), rescale), delta)) {
        std::cerr << "[WARNING] scale after stochastication may fail " << std::endl;
      }
      
      Cast(*fst, fst_std);
      WriteFstKaldi(*fst_std, fst_out_filename);
      delete fst;
      delete fst_std;
    } else { // Dealing with archives.
      SequentialTableReader<VectorFstHolder> fst_reader(fst_in_filename);
      TableWriter<VectorFstHolder> fst_writer(fst_out_filename);
      for (; !fst_reader.Done(); fst_reader.Next()) {
        std::string key = fst_reader.Key();
        VectorFst<StdArc> fst_std(fst_reader.Value());
        fst_reader.FreeCurrent();
        VectorFst<LogArc> *fst = new VectorFst<LogArc>;
        Cast(fst_std, fst);
        ArcSort(fst, ILabelCompare<LogArc>()); // improves speed.
        try {
          RescaleToStochastic(fst, delta);
          //Weight tot = ShortestDistance(*fst);
          Weight tot2 = ComputeTotalWeight(*fst, Weight(-log(2.0)));
          //std::cerr << key << "  tot is " << tot<<", tot2 = "<<tot2<<'\n';
          if (!ApproxEqual(tot2, Weight::One(), delta)) {
            std::cerr << "[WARNING] stochastication may fail: " << key << std::endl;
          }
          
          // Scaling to the specified total weight
          for (StateIterator<VectorFst<LogArc> > siter(*fst); !siter.Done(); siter.Next()) {
            Arc::StateId s = siter.Value();
            fst->SetFinal(s, Times(rescale, fst->Final(s)));
          }
          tot2 = ComputeTotalWeight(*fst, Weight(-log(2.0)));
          if (!ApproxEqual(tot2, Times(Weight::One(), rescale), delta)) {
            std::cerr << "[WARNING] scale after stochastication may fail: " << key << std::endl;
          }
          
          Cast(*fst, &fst_std);
          fst_writer.Write(key, fst_std);
          delete fst;
        } catch (const std::runtime_error e) {
          KALDI_WARN << "Error during making stochastic for key " << key;
        }
      }
    }
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
