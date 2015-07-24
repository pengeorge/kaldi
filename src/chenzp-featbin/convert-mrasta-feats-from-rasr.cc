// featbin/compute-plp-feats.cc

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
#include "feat/feature-plp.h"
#include "feat/wave-reader.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    const char *usage =
        "Convert MRASTA features from RASR archive to kaldi files.\n"
        "Usage:  convert-mrasta-feats-from-rasr [options...] <utt-list-rxfilename> <text-feats-dir> <feats-wspecifier>\n";

    // construct all the global objects
    ParseOptions po(usage);
    bool subtract_mean = false;
    // Define defaults for gobal options
    std::string output_format = "kaldi";

    // Register the options
    po.Register("output-format", &output_format, "Format of the output "
                "files [kaldi, htk]");
    po.Register("subtract-mean", &subtract_mean, "Subtract mean of each "
                "feature file [CMS]. ");

    po.Read(argc, argv);
    
    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string utt_list_rxfilename = po.GetArg(1);
    std::string text_feats_dir = po.GetArg(2);
    std::string output_wspecifier = po.GetArg(3);

    BaseFloatMatrixWriter kaldi_writer;  // typedef to TableWriter<something>.
    TableWriter<HtkMatrixHolder> htk_writer;

    if (output_format == "kaldi") {
      if (!kaldi_writer.Open(output_wspecifier))
        KALDI_ERR << "Could not initialize output with wspecifier "
                  << output_wspecifier;
    } else if (output_format == "htk") {
      if (!htk_writer.Open(output_wspecifier))
        KALDI_ERR << "Could not initialize output with wspecifier "
                  << output_wspecifier;
    } else {
      KALDI_ERR << "Invalid output_format string " << output_format;
    }

    int32 num_utts = 0, num_success = 0;
    Input ulist(utt_list_rxfilename);  // no binary argment: never binary.
    std::string utt;
    /* read each line from utt list file */
    while (std::getline(ulist.Stream(), utt)) {
      num_utts++;
      //is >> text_feats_dir >> "/" >> utt;
      std::string feat_file = text_feats_dir + "/" + utt;
      std::ifstream fin(feat_file.c_str());
      if (!fin.good()) {
        KALDI_ERR << "Cannot open file " << feat_file.c_str();
      }
      Matrix<BaseFloat> features;
      features.Read(fin, false);
//      try {
//        int32 rows_out; // # frames 
//        int32 col_num = -1; // feature dim + 2
//        BaseFloat frame_duration = 0.0;
//        Input text_feats(text_feats_dir + "/" + utt);
//        std::string line;
//        int32 r = 0;
//        while (std::getline(text_feats.Stream(), line)) {
//          std::vector<BaseFloat> split_line;
//          SplitStringToFloats(line, " \r", true, &split_line);
//          if (col_num != -1) {
//            if (split_line.size() != col_num) {
//              KALDI_ERR << "Column number does not match: " << split_line.size() << " != " << col_num;
//            }
//          } else {
//            col_num = split_line.size();
//            frame_duration = split_line[1] - split_line[0];
//          }
//          Vector<BaseFloat> featVec(col_num-2);
//          for (int32 k=2; k < col_num; k++) {
//            featVec(k-2) = split_line[k];
//          }
//          features.Row(r) = featVec;
//          r++;
//        }
//      } catch (...) {
//        KALDI_WARN << "Failed to convert feature format from RASR for utterance "
//                   << utt;
//        continue;
//      }
      if (subtract_mean) {
        Vector<BaseFloat> mean(features.NumCols());
        mean.AddRowSumMat(1.0, features);
        mean.Scale(1.0 / features.NumRows());
        for (size_t i = 0; i < features.NumRows(); i++)
          features.Row(i).AddVec(-1.0, mean);
      }
      if (output_format == "kaldi") {
        kaldi_writer.Write(utt, features);
      } else {
        std::pair<Matrix<BaseFloat>, HtkHeader> p;
        p.first.Resize(features.NumRows(), features.NumCols());
        p.first.CopyFromMat(features);
        HtkHeader header = {
          features.NumRows(),
          100000,  // 10ms shift
          static_cast<int16>(sizeof(float)*features.NumCols()),
          013 | // PLP
          020000 // C0 [no option currently to use energy in PLP.
        };
        p.second = header;
        htk_writer.Write(utt, p);
      }
      if (num_utts % 10 == 0)
        KALDI_LOG << "Processed " << num_utts << " utterances";
      KALDI_VLOG(2) << "Processed features for key " << utt;
      num_success++;
    }
    KALDI_LOG << " Done " << num_success << " out of " << num_utts
              << " utterances.";
    return (num_success != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}

