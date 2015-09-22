// nnet2bin/nnet-extend-const-component.cc

// Copyright 2015  Tsinghua University (author:  Zhipeng Chen)

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
#include "nnet2/nnet-component.h"
#include "nnet2/nnet-component-ext.h"
#include "nnet2/nnet-functions.h"
#include "chenzp-nnet2/nnet-functions-ext.h"

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::nnet2;
    typedef kaldi::int32 int32;

    const char *usage =
        "Remove the softmax component and the last AffineComponent, extend remaining components to "
        "'Ext' version, then adding a new AffineComponent and softmax on top.\n"
        "Usage:  nnet-extend-const-component [options] <nnet-in> <nnet-out>\n"
        "e.g.:\n"
        " nnet-extend-const-component 1.nnet 1e.nnet\n";

    bool with_trans_model = true;
    bool binary_write = true;
    bool randomize_next_component = true;
    int32 const_dim = 0;
    int32 num_ext_component = 0; // 0 means all before the last affine
    BaseFloat stddev_factor = 0.1;
    int32 srand_seed = 0;
    
    ParseOptions po(usage);
    
    po.Register("binary", &binary_write, "Write output in binary mode");
    po.Register("with-trans-model", &with_trans_model, "Input type is am.mdl or nnet.raw");
    po.Register("randomize-next-component", &randomize_next_component,
                "If true, randomize the parameters of the next component after "
                "what we insert (which must be updatable).");
    po.Register("const-dim", &const_dim, "const component dimension to extend.");
    po.Register("num-ext-component", &num_ext_component, "Number of components to extend (from 0).");
    po.Register("stddev-factor", &stddev_factor, "Factor on the standard "
                "deviation when randomizing next component (only relevant if "
                "--randomize-next-component=true");
    po.Register("srand", &srand_seed, "Seed for random number generator");
    
    po.Read(argc, argv);
    srand(srand_seed);
    
    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string nnet_rxfilename = po.GetArg(1),
        nnet_wxfilename = po.GetArg(2);

    if (const_dim < 0) {
      KALDI_ERR << "const_dim is meaningless: " << const_dim;
    }
    
    if (num_ext_component < 0) {
      KALDI_ERR << "num_ext_component is meaningless: " << num_ext_component;
    }

    TransitionModel trans_model;
    AmNnet am_nnet;
    Nnet *pnnet;
    if (with_trans_model) {
      {
        bool binary;
        Input ki(nnet_rxfilename, &binary);
        trans_model.Read(ki.Stream(), binary);
        am_nnet.Read(ki.Stream(), binary);
        pnnet = &(am_nnet.GetNnet());
      }
    } else {
      pnnet = new Nnet();
      ReadKaldiObject(nnet_rxfilename, pnnet);
    }

    if (num_ext_component == 0) {
      if ((num_ext_component = IndexOfSoftmaxLayer(*pnnet)) == -1)
        KALDI_ERR << "We don't know where the softmax layer is: "
            "the neural net doesn't have exactly one softmax component, "
            "and you didn't use the --num-ext-component option.";
      num_ext_component--;
    }
    
    // This function is declared in nnet-functions-ext.h
    ExtendComponents(num_ext_component, pnnet, const_dim);
    KALDI_LOG << "Extend " << num_ext_component << " components by " << const_dim << " dimensions.";

    if (randomize_next_component || const_dim > 0) {
      int32 c = num_ext_component;
      kaldi::nnet2::Component *component = &(pnnet->GetComponent(c));
      AffineComponent *ac = dynamic_cast<AffineComponent*>(component);
      bool treat_as_gradient = false;
      ac->SetZero(treat_as_gradient);
      BaseFloat stddev = stddev_factor /
          std::sqrt(static_cast<BaseFloat>(ac->InputDim()));
      ac->PerturbParams(stddev);
      KALDI_LOG << "Randomized component index " << c << " with stddev "
                << stddev;
    }
   
    if (with_trans_model) {
      {
        Output ko(nnet_wxfilename, binary_write);
        trans_model.Write(ko.Stream(), binary_write);
        am_nnet.Write(ko.Stream(), binary_write);
      }
    } else {
      WriteKaldiObject(*pnnet, nnet_wxfilename, binary_write);
      delete pnnet;
    }
    KALDI_LOG << "Write neural-net acoustic model to " <<  nnet_wxfilename;
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}
