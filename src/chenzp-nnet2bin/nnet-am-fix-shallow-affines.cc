// nnet2bin/nnet-am-fix-shallow-affines.cc

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

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::nnet2;
    typedef kaldi::int32 int32;

    const char *usage =
        "Make the first K layers non-updatable (i.e. convert the first K affine components to FixedAffineComponent). Transition model will not be changed.\n"
        "\n"
        "Usage:  nnet-am-fix-shallow-affines [options] <nnet-in> <nnet-out>\n"
        "e.g.:\n"
        " nnet-am-fix-shallow-affines 1.mdl 2.mdl\n";

    bool binary_write = true;
    int32 num_layers_to_fix = -1;
    
    ParseOptions po(usage);
    po.Register("binary", &binary_write, "Write output in binary mode");
    po.Register("num-layers-to-fix", &num_layers_to_fix, "Number of affine layers  whose weights will be fixed. If negative, only keep the last abs(num-layers-to-fix) affine layers updatable.");

    po.Read(argc, argv);
    
    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string nnet_rxfilename = po.GetArg(1),
        nnet_wxfilename = po.GetArg(2);
    
    TransitionModel trans_model;
    AmNnet am_nnet;
    {
      bool binary;
      Input ki(nnet_rxfilename, &binary);
      trans_model.Read(ki.Stream(), binary);
      am_nnet.Read(ki.Stream(), binary);
    }


    Nnet &nn = am_nnet.GetNnet();
    
    // Count number of affine components
    int numAffCom = 0;
    for (int32 c = 0; c < nn.NumComponents(); c++) {
      string type = nn.GetComponent(c).Type();
      if (type == "AffineComponent"
          || type == "AffineComponentPreconditioned"
          || type == "AffineComponentPreconditionedOnline"
          || type == "BlockAffineComponent"
          || type == "BlockAffineComponentPreconditioned") {
          numAffCom++;
      }
    }

    if (num_layers_to_fix <= 0) {
      num_layers_to_fix += numAffCom;
    }

    int num_processed = 0;
    for (int32 c = 0; c < nn.NumComponents() && num_processed < num_layers_to_fix; c++) {
      string type = nn.GetComponent(c).Type();
      if (type == "BlockAffineComponent"
          || type == "BlockAffineComponentPreconditioned") {
          KALDI_ERR << type << " is currently not supported";
          exit(1);
      }
      if (type == "AffineComponent"
          || type == "AffineComponentPreconditioned"
          || type == "AffineComponentPreconditionedOnline") {
        AffineComponent *affCom = (AffineComponent*) &nn.GetComponent(c);
        const CuMatrix<BaseFloat> &linMat = affCom->LinearParams();
        CuMatrix<BaseFloat> mat(linMat.NumRows(), linMat.NumCols() + 1);
        for (int32 col = 0; col < linMat.NumCols(); col++) {
          CuVector<BaseFloat> colvec(linMat.NumRows());
          colvec.CopyColFromMat(linMat, col);
          mat.CopyColFromVec(colvec, col);
        }
        mat.CopyColFromVec(affCom->BiasParams(), mat.NumCols() - 1);
        FixedAffineComponent *fixAffCom = new FixedAffineComponent;
        fixAffCom->Init(mat);
        nn.SetComponent(c, fixAffCom);
        num_processed++;
      }
    }

    {
      Output ko(nnet_wxfilename, binary_write);
      trans_model.Write(ko.Stream(), binary_write);
      am_nnet.Write(ko.Stream(), binary_write);
    }
    KALDI_LOG << "Convert neural net from " << nnet_rxfilename
              << " to " << nnet_wxfilename
              << ", with " << num_processed << " affine layers fixed ("
              << num_layers_to_fix << " expected)";
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}
