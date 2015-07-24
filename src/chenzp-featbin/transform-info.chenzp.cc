// featbin/transform-feats.cc

// Copyright 2009-2012  Microsoft Corporation
//                      Johns Hopkins University (author: Daniel Povey)

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
#include "matrix/kaldi-matrix.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;

    const char *usage =
        "Read transform info (e.g. LDA; HLDA; fMLLR/CMLLR; MLLT/STC)\n"
        "Linear transform if transform-num-cols == feature-dim, affine if\n"
        "transform-num-cols == feature-dim+1 (->append 1.0 to features)\n"
        "Usage: transform-feats [options] <transform-rspecifier-or-rxfilename>\n";
        
    ParseOptions po(usage);
    std::string key;
    po.Register("key", &key, "one of keys in transform rspecifier");

    po.Read(argc, argv);

    if (po.NumArgs() != 1) {
      po.PrintUsage();
      exit(1);
    }

    std::string transform_rspecifier_or_rxfilename = po.GetArg(1);

    RandomAccessBaseFloatMatrixReaderMapped transform_reader;
    Matrix<BaseFloat> global_transform;
    int32 transform_rows, transform_cols;
    if (ClassifyRspecifier(transform_rspecifier_or_rxfilename, NULL, NULL)
       == kNoRspecifier) {
      // not an rspecifier -> interpret as rxfilename....
      ReadKaldiObject(transform_rspecifier_or_rxfilename, &global_transform);
      const Matrix<BaseFloat> &trans = global_transform;
      transform_rows = trans.NumRows(),
      transform_cols = trans.NumCols();
    } else {  // an rspecifier -> not a global transform.
      if (!transform_reader.Open(transform_rspecifier_or_rxfilename, "")) {
        KALDI_ERR << "Problem opening transforms with rspecifier "
                  << '"' << transform_rspecifier_or_rxfilename << '"';
      }
      std::cout << "Reading info from key: " << key << std::endl;
      const Matrix<BaseFloat> &trans = transform_reader.Value(key);
      transform_rows = trans.NumRows(),
      transform_cols = trans.NumCols();
    }
    std::cout << "Transform matrix size is : " << transform_rows << " x " << transform_cols << std::endl;


    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
