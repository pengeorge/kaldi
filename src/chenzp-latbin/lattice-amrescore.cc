// latbin/lattice-amrescore.cc

// Copyright 2015 Tsinghua University (author: Zhipeng Chen)

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

#define _DEBUG

#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "fstext/fstext-lib.h"
#include "fstext/kaldi-fst-io.h"
#include "lat/kaldi-lattice.h"
#include "chenzp-fstext/rescale-dag.h"

#ifdef _DEBUG
static void saveLattice(const kaldi::Lattice &lat, std::string key, std::string wspecifier) {
  kaldi::LatticeWriter writer(wspecifier);
  writer.Write(key, lat);
}

static void saveFST(const fst::VectorFst<fst::StdArc> &fst, std::string key, std::string wspecifier, bool opt = false) {
  kaldi::TableWriter<fst::VectorFstHolder> writer(wspecifier);
  if (!opt) {
    writer.Write(key, fst);
    return;
  }

  fst::VectorFst<fst::StdArc> tmp = fst, tmp2;
  RmEpsilon(&tmp);
  Determinize(tmp, &tmp2);
  writer.Write(key, tmp2);
}
#endif

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace fst;
    typedef kaldi::int32 int32;
    typedef kaldi::int64 int64;
    using fst::SymbolTable;
    using fst::VectorFst;
    using fst::StdArc;
    using fst::ReadFstKaldi;

    const char *usage =
        "Add lm_scale * [cost of best path through LM FST] to graph-cost of\n"
        "paths through lattice.  Does this by composing with LM FST, then\n"
        "lattice-determinizing (it has to negate weights first if lm_scale<0)\n"
        "Usage: lattice-amrescore [options] lattice-rspecifier E.fst L.fst lattice-wspecifier\n"
        " e.g.: lattice-amrescore ark:in.lats ark:out.lats\n";
      
    ParseOptions po(usage);
    BaseFloat acoustic_scale = 0.1;
    BaseFloat lm_scale = 1.0;
    int32 n = 50;
    
    po.Register("acoustic-scale", &acoustic_scale, "Scaling factor for acoustic likelihoods; used in lattice pruning"); 
    po.Register("lm-scale", &lm_scale, "Scaling factor for language model costs; used in lattice pruning");
    po.Register("n", &n, "Maximum number of paths for score tuning");
    po.Read(argc, argv);

    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string lats_rspecifier = po.GetArg(1),
        E_filename = po.GetArg(2),
        L_filename = po.GetArg(3),
        lats_wspecifier = po.GetArg(4);

    // Read as compact lattice
    // Use regular lattice when we need it in for efficient
    // composition and determinization.
    SequentialCompactLatticeReader lattice_reader(lats_rspecifier);
    
    VectorFst<StdArc> *pE = ReadFstKaldi(E_filename);
    VectorFst<StdArc> *pL = ReadFstKaldi(L_filename);

    // Write as compact lattice.
    CompactLatticeWriter tuned_lattice_writer(lats_wspecifier); 

    // Generate L' and compose L'xE
    KALDI_LOG << "Generate L' and compose L'xE";
    VectorFst<StdArc> LixE;
    {
      VectorFst<StdArc> Li = *pL;
      Invert(&Li);
      ArcSort(&Li, OLabelCompare<StdArc>());
      Compose(Li, *pE, &LixE);
      RmEpsilon(&LixE);
    }
    delete pE;
#ifdef _DEBUG
    saveFST(LixE, "key", "ark:LixE.fsts", false);
#endif


    int32 n_done = 0, n_fail = 0;
    
    // LM and AM scales for ShortestPath
    vector<vector<double> > scale_shortestpath = fst::LatticeScale(lm_scale, acoustic_scale);
    // Scale for FST converting (to zero)
    vector<vector<double> > scale_0 = fst::LatticeScale(0.0, 0.0);
    // Scale for FST converting (lm to zero)
    // TODO check the meaning of 0.0 and 1.0 in scales
    vector<vector<double> > scale_am_only = fst::LatticeScale(0.0, 1.0);
    // Scale for FST converting (am to zero)
    vector<vector<double> > scale_lm_only = fst::LatticeScale(1.0, 0.0);

    // Iterate the lattice of each utterance
    for (; !lattice_reader.Done(); lattice_reader.Next()) {
      std::string key = lattice_reader.Key();
      KALDI_LOG << "Lattice key: " << key;
      Lattice lat;
      {
        CompactLattice clat = lattice_reader.Value();
        lattice_reader.FreeCurrent();

        // TODO how to involve alignment when doing confusion ?
        RemoveAlignmentsFromCompactLattice(&clat); // remove the alignments...

        ConvertLattice(clat, &lat); // convert to non-compact form.. won't introduce
        // extra states because already removed alignments.
      }
      
      // 1. Convert to FSTs with StdArc
      KALDI_LOG << "Convert to FSTs with StdArc";
      VectorFst<StdArc> fst_0, fst_am;
      {
        Lattice lat_0, lat_am;
        lat_0 = lat_am = lat;

        ScaleLattice(scale_0, &lat_0); // scales to zero.
        ConvertLattice(lat_0, &fst_0); // this adds up the (lm,acoustic) costs to get
        // the normal (tropical) costs.
        Project(&fst_0, PROJECT_OUTPUT);
        RemoveEpsLocal(&fst_0);

        ScaleLattice(scale_am_only, &lat_am); // scales lm to zero.
        ConvertLattice(lat_am, &fst_am); // this adds up the (lm,acoustic) costs to get
        // the normal (tropical) costs.
        Project(&fst_am, PROJECT_OUTPUT);
        RemoveEpsLocal(&fst_am);
      }
#ifdef _DEBUG
      saveFST(fst_am, key, "ark:fst_am.fsts");
#endif

      VectorFst<StdArc> s2s; // sequence to sequence FST with confusion weights
      {
        // 2. Generate L x Lat_0
        KALDI_LOG << "Generate L x Lat_0";
        VectorFst<StdArc> LxLat0;
        ArcSort(pL, OLabelCompare<StdArc>());
        Compose(*pL, fst_0, &LxLat0);
        RmEpsilon(&LxLat0);
#ifdef _DEBUG
        saveFST(LxLat0, key, "ark:LxLat0.fsts");
#endif

        // 3. Generate (Lat_0 x (Li x E)) x (L x Lat_0)
        KALDI_LOG << "Generate (Lat_0 x (Li x E)) x (L x Lat_0)";
        {
          VectorFst<StdArc> tmp;
          ArcSort(&fst_0, OLabelCompare<StdArc>());
          Compose(fst_0, LixE, &tmp);
#ifdef _DEBUG
          saveFST(tmp, "key", "ark:Lat0xLixE.fsts");
#endif
          ArcSort(&tmp, OLabelCompare<StdArc>());
          Compose(tmp, LxLat0, &s2s);
          RmEpsilon(&s2s);
#ifdef _DEBUG
          saveFST(s2s, "key", "ark:Lat0xLixExLxLat0.fsts");
#endif
          //Determinize(tmp, &tmp2);
        }
      }

      // 4. Iterate top n paths and get weights for each H 
      KALDI_LOG << "Iterate top n paths and get weights for each H";
      ScaleLattice(scale_shortestpath, &lat);
      vector<Lattice> nbest_lats;
      {
        Lattice nbest_lat;
        fst::ShortestPath(lat, &nbest_lat, n);
        fst::ConvertNbestToVector(nbest_lat, &nbest_lats);
      }

      if (nbest_lats.empty()) {
        KALDI_WARN << "Possibly empty lattice for utterance-id " << key
          << "(no N-best entries)";
      } else {
        Lattice lat_union; 
        KALDI_LOG << "Union tuned paths: " << nbest_lats.size();
        for (int32 k = 0; k < static_cast<int32>(nbest_lats.size()); k++) {
          std::ostringstream os;
          //os << key << "-" << (k+1); // so if key is "utt_id", the keys
          // of the n-best are utt_id-1, utt_id-2, utt_id-3, etc.
          //std::string nbest_key = os.str();
          Lattice H_tuned = nbest_lats[k];

#ifdef _DEBUG
          {
            std::ostringstream os1, os2;
            os1 << "H_with_score" << k;
            os2 << "ark:" << os1.str() << ".fsts";
            saveLattice(H_tuned, os1.str(), os2.str());
          }
#endif

          ScaleLattice(scale_0, &(nbest_lats[k]));
          ScaleLattice(scale_lm_only, &H_tuned);
#ifdef _DEBUG
          {
            std::ostringstream os3, os4;
            os3 << "H_with_LM" << k;
            os4 << "ark:" << os3.str() << ".fsts";
            saveLattice(H_tuned, os3.str(), os4.str());
          }
#endif

          LogArc::Weight acoustic_weight;
          {
            VectorFst<StdArc> H;
            ConvertLattice(nbest_lats[k], &H); // this adds up the (lm,acoustic) costs to get
            // the normal (tropical) costs.
            Project(&H, fst::PROJECT_OUTPUT);
            RmEpsilon(&H);
#ifdef _DEBUG
            {
              std::ostringstream os;
              os << "ark:H" << k << ".fsts";
              saveFST(H, "key", os.str());
            }
#endif

            VectorFst<StdArc> fst_confusion_given_H;
            ArcSort(&H, OLabelCompare<StdArc>());
            Compose(H, s2s, &fst_confusion_given_H);
#ifdef _DEBUG
            {
              std::ostringstream os;
              os << "ark:H" << k << "xLat0xLixExLxLat0.fsts";
              saveFST(fst_confusion_given_H, "key", os.str());
            }
#endif
            {
              VectorFst<LogArc> fst_log;
              Cast(fst_confusion_given_H, &fst_log);
              RescaleDagToStochastic(&fst_log);
              Cast(fst_log, &fst_confusion_given_H);
            }
#ifdef _DEBUG
            {
              std::ostringstream os;
              os << "ark:stoch_H" << k << "xLat0xLixExLxLat0.fsts";
              saveFST(fst_confusion_given_H, "key", os.str());
            }
#endif

            VectorFst<StdArc> fst_tuned_for_H;
            ArcSort(&fst_confusion_given_H, OLabelCompare<StdArc>());
            Compose(fst_confusion_given_H, fst_am, &fst_tuned_for_H);
#ifdef _DEBUG
            {
              std::ostringstream os;
              os << "ark:H" << k << "xLat0xLixExLxLat0xAM.fsts";
              saveFST(fst_tuned_for_H, "key", os.str());
            }
#endif
            Project(&fst_tuned_for_H, PROJECT_OUTPUT); // so it can be determinized
            RmEpsilon(&fst_tuned_for_H);
            {
              VectorFst<StdArc> tmp = fst_tuned_for_H;
              Determinize(tmp, &fst_tuned_for_H);
            }
#ifdef _DEBUG
            {
              std::ostringstream os;
              os << "ark:det_H" << k << "xLat0xLixExLxLat0xAM.fsts";
              saveFST(fst_tuned_for_H, "key", os.str());
            }
#endif
            {
              VectorFst<LogArc> fst_log;
              Cast(fst_tuned_for_H, &fst_log);
              acoustic_weight = ComputeDagTotalWeight(fst_log);
              KALDI_LOG << "Total weight of path " << k << " is " << acoustic_weight.Value();
            }
          }
          
          // Set acoustic score on 1st arc
          LatticeArc::StateId s = H_tuned.Start();
          KALDI_ASSERT(H_tuned.NumArcs(s) == 1);
          ArcIterator<Lattice > aiter(H_tuned, s);
          LatticeArc first_arc = aiter.Value();
          KALDI_LOG << "VALUE1 of 1st arc is " << first_arc.weight.Value1();
          KALDI_LOG << "VALUE2 of 1st arc is " << first_arc.weight.Value2();
          first_arc.weight.SetValue2(acoustic_weight.Value());
          H_tuned.DeleteArcs(s);
          H_tuned.AddArc(s, first_arc);
#ifdef _DEBUG
          {
            std::ostringstream os, os2;
            os << "H" << k << "_tuned";
            os2 << "ark:H" << k << "_tuned.fsts";
            saveLattice(H_tuned, os.str(), os2.str());
          }
#endif
          
          Union(&lat_union, H_tuned);
        }
#ifdef _DEBUG
        saveLattice(lat_union, "union_H", "ark:union_H.fsts");
#endif

        KALDI_LOG << "Optimize: det and min";
        {
          Lattice tmp;
          RmEpsilon(&lat_union);
          Project(&lat_union, PROJECT_OUTPUT);
          //Disambiguate(lat_union, &tmp);
          //saveLattice(tmp, "disam_union_H", "ark:disam_union_H.fsts");
          tmp = lat_union;
          Determinize(tmp, &lat_union);
#ifdef _DEBUG
          saveLattice(lat_union, "det_union_H", "ark:det_union_H.fsts");
#endif
          Minimize(&lat_union);
#ifdef _DEBUG
          saveLattice(lat_union, "min_det_union_H", "ark:min_det_union_H.fsts");
#endif
        }

        CompactLattice clat_tuned;
        ConvertLattice(lat_union, &clat_tuned); // write in compact form.
        tuned_lattice_writer.Write(key, clat_tuned);
        n_done++;
      }
    }
    delete pL;

    KALDI_LOG << "Done " << n_done << " lattices, failed for " << n_fail;
    return (n_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
