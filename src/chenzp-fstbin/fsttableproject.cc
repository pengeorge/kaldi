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
#include "fstext/rescale.h"
#include "fstext/fstext-utils.h"
#include "fstext/fst-test-utils.h"

#include <fst/script/project.h>

// Just check that it compiles, for now.
int main(int argc, char **argv) {
  try {
    using namespace kaldi;
    using namespace fst;
    using kaldi::int32;

    const char *usage =
        "Project all FSTs in archive.\n"
        "Output to another archive.\n"
        "\n"
        "Usage:  fstisstochastic [ ark:in.fsts [ ark:out.fsts ] ]\n";


    ParseOptions po(usage);
    po.Read(argc, argv);

    if (po.NumArgs() > 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string fst_in_filename = po.GetOptArg(1);
    std::string fst_out_filename = po.GetOptArg(2);

    if (ClassifyRspecifier(fst_in_filename, NULL, NULL) == kNoRspecifier) {
      KALDI_ERR << "cannot support yet";
      //Project(&tmp_proxy, PROJECT_OUTPUT);
      return 1;
    } else { // Dealing with archives.
      SequentialTableReader<VectorFstHolder> fst_reader(fst_in_filename);
      TableWriter<VectorFstHolder> fst_writer(fst_out_filename);
      for (; !fst_reader.Done(); fst_reader.Next()) {
        std::string key = fst_reader.Key();
        VectorFst<StdArc> fst(fst_reader.Value());
        fst_reader.FreeCurrent();
        try {
          Project(&fst, PROJECT_OUTPUT); 
          fst_writer.Write(key, fst);
        } catch (const std::runtime_error e) {
          KALDI_WARN << "Error during projecting for key " << key;
        }
      }
    }
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
