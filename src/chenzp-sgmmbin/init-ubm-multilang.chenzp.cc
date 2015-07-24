// sgmmbin/init-ubm.cc

// Copyright 2009-2011   Saarland University
// Author:  Arnab Ghoshal

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
#include "gmm/diag-gmm.h"
#include "gmm/full-gmm.h"
#include "gmm/am-diag-gmm.h"
#include "hmm/transition-model.h"


int main(int argc, char *argv[]) {
  try {
    typedef kaldi::int32 int32;
    typedef kaldi::BaseFloat BaseFloat;

    const char *usage =
        "Cluster the Gaussians in a diagonal-GMM acoustic model\n"
        "to a single full-covariance or diagonal-covariance GMM.\n"
        "Usage: init-ubm [options] <model1-file> <state-occs1> [ <model2-file> <state-occs2> ... ] <gmm-out>\n";

    bool binary_write = true, fullcov_ubm = true;
    kaldi::ParseOptions po(usage);
    po.Register("binary", &binary_write, "Write output in binary mode");
    po.Register("fullcov-ubm", &fullcov_ubm, "Write out full covariance UBM.");
    kaldi::UbmClusteringOptions ubm_opts;
    ubm_opts.Register(&po);

    po.Read(argc, argv);

    if (po.NumArgs() < 3 || po.NumArgs() % 2 == 0) {
      po.PrintUsage();
      exit(1);
    }
    ubm_opts.Check();
    
    int32 num_lang = (po.NumArgs() - 1) / 2;
    std::vector<std::string> model_in_filenames(num_lang);
    std::vector<std::string> occs_in_filenames(num_lang);
    for (int k = 0; k < num_lang; k++) {
      model_in_filenames[k] = po.GetArg(k+k+1);
      occs_in_filenames[k] = po.GetArg(k+k+2);
    }
    std::string gmm_out_filename = po.GetArg(po.NumArgs());

    kaldi::AmDiagGmm am_gmm;
    kaldi::TransitionModel trans_model;
    {
      bool binary_read;
      kaldi::Input ki(model_in_filenames[0], &binary_read);
      trans_model.Read(ki.Stream(), binary_read);
      am_gmm.Read(ki.Stream(), binary_read);
      KALDI_LOG << "Read " << am_gmm.NumPdfs() << " pdfs from model " << model_in_filenames[0];
    }

    std::vector<kaldi::Vector<BaseFloat> *> arr_state_occs;
    arr_state_occs.resize(num_lang);
    arr_state_occs[0] = new kaldi::Vector<BaseFloat>;
    arr_state_occs[0]->Resize(am_gmm.NumPdfs());
    {
      bool binary_read;
      kaldi::Input ki(occs_in_filenames[0], &binary_read);
      arr_state_occs[0]->Read(ki.Stream(), binary_read);
    }

    for (int k = 1; k < num_lang; k++) {
      kaldi::AmDiagGmm this_am_gmm;
      kaldi::TransitionModel this_trans_model;
      bool binary_read;
      kaldi::Input ki_am(model_in_filenames[k], &binary_read);
      this_trans_model.Read(ki_am.Stream(), binary_read);
      this_am_gmm.Read(ki_am.Stream(), binary_read);
      for (int i = 0; i < this_am_gmm.NumPdfs(); i++) {
        am_gmm.AddPdf(this_am_gmm.GetPdf(i));
      }
      KALDI_LOG << "Add " << this_am_gmm.NumPdfs() << " pdfs from model " << model_in_filenames[k];

      arr_state_occs[k] = new kaldi::Vector<BaseFloat>;
      arr_state_occs[k]->Resize(this_am_gmm.NumPdfs());
      kaldi::Input ki_occs(occs_in_filenames[k], &binary_read);
      arr_state_occs[k]->Read(ki_occs.Stream(), binary_read);
      //state_stl_occs.reserve(state_stl_occs.size() + this_state_occs.Dim());
    }
    int32 tot_pdf_num = 0;
    for (int k = 0; k < num_lang; k++) {
      tot_pdf_num += arr_state_occs[k]->Dim();
    }
    kaldi::Vector<BaseFloat> state_occs(tot_pdf_num);
    int32 start = 0;
    for (int k = 0; k < num_lang; k++) {
      kaldi::SubVector<BaseFloat> sub(state_occs, start, arr_state_occs[k]->Dim());
      //KALDI_LOG << "Sub dim: " << sub.Dim() << ", occs_dim: " << arr_state_occs[k]->Dim();
      sub.CopyFromVec(*arr_state_occs[k]);
      start += arr_state_occs[k]->Dim();
      delete arr_state_occs[k];
    }
    KALDI_LOG << "Totally " << tot_pdf_num << " pdfs/occs";
    KALDI_ASSERT(am_gmm.NumPdfs() == tot_pdf_num);

    kaldi::DiagGmm ubm;
    ClusterGaussiansToUbm(am_gmm, state_occs, ubm_opts, &ubm);
    if (fullcov_ubm) {
      kaldi::FullGmm full_ubm;
      full_ubm.CopyFromDiagGmm(ubm);
      kaldi::Output ko(gmm_out_filename, binary_write);
      full_ubm.Write(ko.Stream(), binary_write);
    } else {
      kaldi::Output ko(gmm_out_filename, binary_write);
      ubm.Write(ko.Stream(), binary_write);
    }

    KALDI_LOG << "Written UBM to " << gmm_out_filename;
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}


