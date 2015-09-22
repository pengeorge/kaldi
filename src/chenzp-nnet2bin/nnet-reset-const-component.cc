// nnet2bin/nnet-reset-const-component.cc

// Copyright 2013  Johns Hopkins University (author:  Daniel Povey)

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
#include "hmm/transition-model.h"
#include "nnet2/am-nnet.h"
#include "hmm/transition-model.h"
#include "tree/context-dep.h"
#include "nnet2/nnet-component-ext.h"

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::nnet2;
    
    typedef kaldi::int32 int32;

    const char *usage =
        "Reset const_dim for all components\n"
        "\n"
        "Usage:  nnet-reset-const-component [options] <raw-nnet-in> <raw-nnet-out>\n"
        "e.g.:\n"
        " nnet-reset-const-component --binary=false --const-dim 0 0.raw 1.raw\n";

    int32 const_dim = 0;
    int32 const_dim_to_reduce = 0;
    bool binary_write = true;

    ParseOptions po(usage);
    po.Register("binary", &binary_write, "Write output in binary mode");
    po.Register("const-dim", &const_dim, "The target const_dim after resetting.");
    po.Register("const-dim-to-reduce", &const_dim_to_reduce, "The dim to reduce, only used for SpliceComponent.");
    
    po.Read(argc, argv);
    
    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string raw_nnet_rxfilename = po.GetArg(1),
        raw_nnet_wxfilename = po.GetArg(2);
    
    Nnet nnet;
    ReadKaldiObject(raw_nnet_rxfilename, &nnet);

    if (const_dim >= 0) {
      for (int32 c = 0; c < nnet.NumComponents(); c++) {
        Component *comp = &(nnet.GetComponent(c));
        if (comp->Type() == "AffineComponentExt") {
          dynamic_cast<AffineComponentExt*>(comp)->ResetConst(const_dim);
        } else if (comp->Type() == "FixedAffineComponentExt") {
          dynamic_cast<FixedAffineComponentExt*>(comp)->ResetConst(const_dim);
        } else if (comp->Type() == "SpliceComponent") {
          SpliceComponent *sc = dynamic_cast<SpliceComponent*>(comp);
          sc->Init(sc->InputDim() - const_dim_to_reduce, sc->Context(), const_dim);
        } else if (comp->Type() == "TanhComponentExt") {
          dynamic_cast<TanhComponentExt*>(comp)->ResetConst(const_dim);
        } else if (comp->Type() == "PnormComponentExt") {
          dynamic_cast<PnormComponentExt*>(comp)->ResetConst(const_dim);
        } else if (comp->Type() == "NormalizeComponentExt") {
          dynamic_cast<NormalizeComponentExt*>(comp)->ResetConst(const_dim);
        } else {
          KALDI_ERR << comp->Type() << " is not supported for resetting const dimension";
        }
      }
      KALDI_LOG << "Reset const part to " << const_dim << " dimensions.";
    } else {
      KALDI_ERR << "Wrong parameter: const_dim = " << const_dim;
    }

    WriteKaldiObject(nnet, raw_nnet_wxfilename, binary_write);
    
    KALDI_LOG << "Read neural net from " << raw_nnet_rxfilename
              << " and wrote raw neural net to " << raw_nnet_wxfilename;
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}
