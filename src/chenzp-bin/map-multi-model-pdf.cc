// bin/map-multi-model-pdf.cc

// Copyright 2015 Zhipeng Chen
//                

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

enum ClusterMethod {
  kMix
};

int main(int argc, char *argv[]) {
  using namespace kaldi;
  typedef kaldi::int32 int32;
  try {
    const char *usage =
        "Map pdf_id in each model to a global class_id by clustering.\n"
        "Usage:  map-multi-model-pdf [options] <output-pdf-map> <mdl-1> <mdl-2> ... <mdl-N>\n"
        "Typical usage:\n"
        " map-multi-model-pdf pdf_map ../101/exp/tri5_ali/final.mdl ../104/exp/tri5_ali/final.mdl\n";

    int32 cluster_method = kMix;
    ParseOptions po(usage);
    po.Register("cluster-method", &cluster_method, "the method for class clustering. (0: mix, 1: gmm-distance)");
    po.Read(argc, argv);

    if (po.NumArgs() < 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string pdf_map_wxfilename = po.GetArg(1);

    TransitionModel *trans_models = new TransitionModel[po.NumArgs() - 1];
    int32 total_pdf_num = 0;
    for (int32 k = 0; k < po.NumArgs() - 1; k++) {
      std::string model_rxfilename = po.GetArg(k+2);
      bool binary_read;
      Input ki(model_rxfilename, &binary_read);
      trans_models[k].Read(ki.Stream(), binary_read);
      total_pdf_num += trans_models[k].NumPdfs();
    }

    TableWriter<BasicVectorVectorHolder<int32> > model_pdf_map_writer(pdf_map_wxfilename);
    int32 mapped_class_num = 0;
    if (cluster_method == kMix) {
      int32 id_offset = 0;
      std::vector<std::vector<int32> > model_pdf_map;
      for (int32 k = 0; k < po.NumArgs() - 1; k++) {
        int32 pdf_num = trans_models[k].NumPdfs();
        std::vector<int32> pdf_map(pdf_num);
        for (int32 i = 0; i < pdf_num; i++) {
          pdf_map[i] = i + id_offset;
        }
        model_pdf_map.push_back(pdf_map);
        id_offset += pdf_num;
      }
      model_pdf_map_writer.Write("map", model_pdf_map);
      mapped_class_num = id_offset;
    } else {
      KALDI_ERR << "cluster-method " << cluster_method << " not supported.";
    }

    delete[] trans_models;
    KALDI_LOG << "Done mapping " << total_pdf_num << " pdfs to "
              << mapped_class_num << " classes.";

    KALDI_LOG << "Written multiple model pdf mapping file.";
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}


