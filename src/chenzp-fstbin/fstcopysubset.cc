// fstbin/fstcopy.cc

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


//#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "fst/fstlib.h"
#include "fstext/table-matcher.h"
#include "fstext/fstext-utils.h"
#include "fstext/kaldi-fst-io.h"
#include <fstream>
#include <map>

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace fst;
    using kaldi::int32;

    const char *usage =
        "Copy tables/archives of FSTs, index by utterance-id\n"
        "\n"
        "Usage: fstcopysubset <fst-rspecifier> <fst-wspecifier>\n";
    
    std::string subset_key_file("");
    ParseOptions po(usage);
    po.Register("subset-key-file", &subset_key_file,
                "Key list of FSTs to copy");

    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string fst_rspecifier = po.GetArg(1),
        fst_wspecifier = po.GetArg(2);

    std::ifstream keylist(subset_key_file.c_str());
    if (!keylist) {
      KALDI_ERR << "Open subset key file failed.\n";
      return -1;
    }
    std::map<std::string, bool> isKeySubsetted;
    std::string key;
    while (keylist >> key) {
      isKeySubsetted[key] = true;
    }
    keylist.close();
    
    SequentialTableReader<VectorFstHolder> fst_reader(fst_rspecifier);
    TableWriter<VectorFstHolder> fst_writer(fst_wspecifier);
    int32 n_done = 0;
    
    for (; !fst_reader.Done(); fst_reader.Next()) {
      std::string key = fst_reader.Key();
      if (isKeySubsetted.find(key) != isKeySubsetted.end()) { 
        fst_writer.Write(key, fst_reader.Value());
        n_done++;
      }
    }

    KALDI_LOG << "Copied " << n_done << " FSTs.";
    return 0; //(n_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}

