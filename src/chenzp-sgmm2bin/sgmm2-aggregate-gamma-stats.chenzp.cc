// sgmm2bin/sgmm2-acc-stats.cc

// Copyright 2009-2012   Saarland University (Author:  Arnab Ghoshal),
//                       Johns Hopkins University (Author:  Daniel Povey)
//                2014   Guoguo Chen

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
#include "sgmm2/am-sgmm2.h"
#include "hmm/transition-model.h"
#include "chenzp-sgmm2/estimate-am-sgmm2-shared.chenzp.h"
#include "hmm/posterior.h"

int main(int argc, char *argv[]) {
  using namespace kaldi;
  try {
    const char *usage =
        "Aggregate gamma stats for multiple SGMMs.\n"
        "The resulting accs are used for updating w_i.\n"
        "Usage: sgmm2-aggregate-gamma-stats [options] <stats-out> <model1-accs> <model2-accs> [ <model3-accs> ...]\n"
        "e.g.: sgmm2-aggregate-gamma-stats stats-out m1.acc m2.acc [ m3.acc ...] \n";
        
    ParseOptions po(usage);
    bool binary = true;

    po.Register("binary", &binary, "Write output in binary mode");

    po.Read(argc, argv);

    if (po.NumArgs() < 2) {
      po.PrintUsage();
      exit(1);
    }
    
    using namespace kaldi;
    typedef kaldi::int32 int32;

    std::string stats_out_wxfilename = po.GetArg(1);
    kaldi::MleAmSgmm2AccsShared sgmm_out_accs;

    for (int i = 2, max = po.NumArgs(); i <= max; i++) {
      std::string stats_in_filename = po.GetArg(i);
      bool binary_read;
      kaldi::Vector<double> transition_accs;
      kaldi::MleAmSgmm2AccsShared sgmm_accs;
      kaldi::Input ki(stats_in_filename, &binary_read);
      transition_accs.Read(ki.Stream(), binary_read, false);
      sgmm_accs.Read(ki.Stream(), binary_read, false);
      sgmm_out_accs.AddGamma(sgmm_accs.GetGamma());
    }

    {
      Output ko(stats_out_wxfilename, binary);
      sgmm_out_accs.WriteGammas(ko.Stream(), binary);
    }
    KALDI_LOG << "Written gammas.";
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}


