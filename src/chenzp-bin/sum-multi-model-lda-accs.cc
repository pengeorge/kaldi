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
        "Usage: sum-multi-model-lda-accs [options] <stats-out> <class-map> <summed-stats-in1> <summed-stats-in2> ...\n";

    bool binary = true;
    ParseOptions po(usage);
    po.Register("binary", &binary, "Write accumulators in binary mode.");
    po.Read(argc, argv);

    if (po.NumArgs() < 3) {
      po.PrintUsage();
      exit(1);
    }

    LdaEstimateExt ldaSum;
    std::string stats_out_filename = po.GetArg(1);
    std::string class_map_in_filename = po.GetArg(2);

    SequentialTableReader<BasicVectorVectorHolder<int32> > class_map_reader(class_map_in_filename);
    KALDI_ASSERT(!class_map_reader.Done());
    std::vector<std::vector<int32> > model_class_map = class_map_reader.Value();

    // Find maximum mapped class_id
    int32 model_num = 0;
    int32 num_clusters = -1;
    std::vector<std::vector<int32> >::iterator this_class_map = model_class_map.begin();
    for (; this_class_map != model_class_map.end(); ++this_class_map, model_num++) {
      std::vector<int32>::iterator it = this_class_map->begin();
      for (; it != this_class_map->end(); ++it) {
        if (*it > num_clusters) {
          num_clusters = *it;
        }
      }
    }
    num_clusters++;
    if (model_num != po.NumArgs() - 2) {
      KALDI_ERR << "Number of models mismatch: " << model_num << " vs. " << (po.NumArgs() - 2);
    }

    // Accumulate LDA statistics from multiple models
    for (int32 i = 3; i <= po.NumArgs(); i++) {
      LdaEstimateExt lda;
      bool binary_in, add = false;
      Input ki(po.GetArg(i), &binary_in);
      lda.Read(ki.Stream(), binary_in, add);
      if (i == 3) {
        KALDI_LOG << "Multi-model LDA: #clusters " << num_clusters << ", feat_dim " << lda.Dim();
        ldaSum.Init(num_clusters, lda.Dim());
      }
      const std::vector<int32> &this_class_map = model_class_map[i - 3];
      KALDI_LOG << "Number of classes in model " << (i - 3) << ": " << this_class_map.size();
      if (this_class_map.size() != lda.NumClasses()) {
        KALDI_ERR << "Number of classes in model " << (i - 3) << " mismatch: "
                  << this_class_map.size() << " vs. " << lda.NumClasses();
      }
      for (int32 j = 0; j < this_class_map.size(); j++) {
        ldaSum.AccumulateSS(lda, j, this_class_map[j]);
      }
    }

    Output ko(stats_out_filename, binary);
    ldaSum.Write(ko.Stream(), binary);
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}


