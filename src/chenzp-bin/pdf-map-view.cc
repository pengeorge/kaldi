// bin/sum-lda.cc

// Copyright 2014 LINSE/UFSC; Augusto Henrique Hentz

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

#include "util/common-utils.h"
#include "gmm/mle-am-diag-gmm.h"
#include "chenzp-transform/lda-estimate-ext.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    typedef kaldi::int32 int32;

    const char *usage =
        "Sum stats from multiple models (already summed in each model by sum-lda-accs).\n"
        "Usage: sum-multi-model-lda-accs [options] <stats-out> <pdf-map> <summed-stats-in1> <summed-stats-in2> ...\n";

    bool binary = false;
    ParseOptions po(usage);
    po.Register("binary", &binary, "Write accumulators in binary mode.");
    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    LdaEstimateExt ldaSum;
    std::string pdf_map_in_filename = po.GetArg(1);
    std::string out_filename = po.GetArg(2);

    SequentialTableReader<BasicVectorVectorHolder<int32> > pdf_map_reader(pdf_map_in_filename);
    Output ko(out_filename, binary);
    std::ostream &os = ko.Stream();

    KALDI_ASSERT(!pdf_map_reader.Done());
    std::vector<std::vector<int32> > model_pdf_map = pdf_map_reader.Value();

    // Find maximum mapped class_id
    int32 model_num = 0;
    int32 num_clusters = -1;
    std::vector<std::vector<int32> >::iterator this_pdf_map = model_pdf_map.begin();
    for (; this_pdf_map != model_pdf_map.end(); ++this_pdf_map, model_num++) {
      os << "Model " << model_num << "\n";
      std::vector<int32>::iterator it = this_pdf_map->begin();
      int32 i = 0;
      for (; it != this_pdf_map->end(); ++it, i++) {
        os << i << " --> " << *it << "\t";
        if (*it > num_clusters) {
          num_clusters = *it;
        }
      }
      os << "\n";
    }
    num_clusters++;
    os << "#clusters: " << num_clusters << "\n";

    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}


