// sgmm2bin/sgmm2-est.cc

// Copyright 2009-2012  Saarland University (Author:  Arnab Ghoshal)
//                      Johns Hopkins University (Author: Daniel Povey)

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
#include "thread/kaldi-thread.h"
#include "sgmm2/am-sgmm2.h"
#include "hmm/transition-model.h"
#include "chenzp-sgmm2/estimate-am-sgmm2-shared.chenzp.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    typedef kaldi::int32 int32;
    const char *usage =
        "Estimate SGMM model parameters (no transition model) from accumulated stats.\n"
        "Usage: sgmm2-est-shared [options] <shared-stats-in> <model1-in> <model1-out> [<model2-in> <model2-out>... ]\n";

    bool binary_write = true;
    std::string update_flags_str = "MNwuS";
    std::string write_flags_str = "gsnu";
    kaldi::MleTransitionUpdateConfig tcfg;
    kaldi::MleAmSgmm2Options sgmm_opts;
    int32 increase_phn_dim = 0;
    int32 increase_spk_dim = 0;
    bool remove_speaker_space = false;
    bool spk_dep_weights = false;

    ParseOptions po(usage);
    po.Register("binary", &binary_write, "Write output in binary mode");
    po.Register("increase-phn-dim", &increase_phn_dim, "Increase phone-space "
                "dimension as far as allowed towards this target.");
    po.Register("increase-spk-dim", &increase_spk_dim, "Increase speaker-space "
                "dimension as far as allowed towards this target.");
    po.Register("spk-dep-weights", &spk_dep_weights, "If true, have speaker-"
                "dependent weights (symmetric SGMM)-- this option only makes"
                "a difference if you use the --increase-spk-dim option and "
                "are increasing the speaker dimension from zero.");
    po.Register("remove-speaker-space", &remove_speaker_space, "Remove speaker-specific "
                "projections N");
    po.Register("update-flags", &update_flags_str, "Which SGMM parameters to "
                "update: subset of vMNwcSt.");
    po.Register("write-flags", &write_flags_str, "Which SGMM parameters to "
                "write: subset of gsnu");
    po.Register("num-threads", &g_num_threads, "Number of threads to use in "
                "weight update and normalizer computation");
    tcfg.Register(&po);
    sgmm_opts.Register(&po);

    po.Read(argc, argv);
    if (po.NumArgs() < 3) {
      po.PrintUsage();
      exit(1);
    }
    std::string stats_filename = po.GetArg(1);
    int32 num_models = (po.NumArgs() - 1) / 2;
    std::vector<std::string> model_in_filenames(num_models), model_out_filenames(num_models);
    for (int32 l =0; l < num_models; l++) {
      model_in_filenames[l] = po.GetArg(l+l+2);
      model_out_filenames[l] = po.GetArg(l+l+3);
    }

    kaldi::SgmmUpdateFlagsType update_flags =
        StringToSgmmUpdateFlags(update_flags_str);
    kaldi::SgmmWriteFlagsType write_flags =
        StringToSgmmWriteFlags(write_flags_str);
    
    std::vector<AmSgmm2*> am_sgmms(num_models);
    std::vector<TransitionModel*> trans_models(num_models);
    for (int32 l = 0; l < num_models; l++) {
      bool binary;
      Input ki(model_in_filenames[l], &binary);
      trans_models[l] = new TransitionModel;
      trans_models[l]->Read(ki.Stream(), binary);
      am_sgmms[l] = new AmSgmm2;
      am_sgmms[l]->Read(ki.Stream(), binary);
    }

    MleAmSgmm2AccsShared sgmm_accs(1.0e-05, false);
    {
      bool binary;
      Input ki(stats_filename, &binary);
      sgmm_accs.Read(ki.Stream(), binary, true);  // true == add; doesn't matter here.
    }

    //sgmm_accs.SetNumAndDim(am_sgmm);
    sgmm_accs.CheckShared(am_sgmms, true); 

    { // Do the update.
      kaldi::MleAmSgmm2SharedUpdater updater(sgmm_opts);
      updater.Update(sgmm_accs, am_sgmms, update_flags);
    }

    if (increase_phn_dim != 0 || increase_spk_dim != 0) {
      // Feature normalizing transform matrix used to initialize the new columns
      // of the phonetic- or speaker-space projection matrices.
      for (int32 l = 0; l < num_models; l++) {
        kaldi::Matrix<BaseFloat> norm_xform;
        ComputeFeatureNormalizingTransform(am_sgmms[l]->full_ubm(), &norm_xform);
        if (increase_phn_dim != 0)
          am_sgmms[l]->IncreasePhoneSpaceDim(increase_phn_dim, norm_xform);
        if (increase_spk_dim != 0)
          am_sgmms[l]->IncreaseSpkSpaceDim(increase_spk_dim, norm_xform,
                                      spk_dep_weights);
      }
    }
    if (remove_speaker_space) {
      KALDI_LOG << "Removing speaker space (projections N_)";
      for (int32 l = 0; l < num_models; l++) {
        am_sgmms[l]->RemoveSpeakerSpace();
      }
    }

    for (int32 l = 0; l < num_models; l++) {
      am_sgmms[l]->ComputeDerivedVars(); // recompute normalizers, and possibly
      // weights.
    }
    
    for (int32 l = 0; l < num_models; l++) {
      Output ko(model_out_filenames[l], binary_write);
      trans_models[l]->Write(ko.Stream(), binary_write);
      am_sgmms[l]->Write(ko.Stream(), binary_write, write_flags);
      delete trans_models[l];
      delete am_sgmms[l];
      KALDI_LOG << "Written model to " << model_out_filenames[l];
    }
    
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}


