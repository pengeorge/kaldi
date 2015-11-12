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

//#define _DEBUG
//#define _STATS
//#define _INPUT_S2S

#include <set>
#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "fstext/fstext-lib.h"
#include "fstext/kaldi-fst-io.h"
#include "lat/kaldi-lattice.h"
#include "chenzp-fstext/rescale-dag.h"
#include "fstext/prune-special.h"

using namespace fst;

#ifdef _DEBUG
static void saveLattice(const kaldi::Lattice &lat, std::string key, std::string wspecifier) {
  kaldi::LatticeWriter writer(wspecifier);
  writer.Write(key, lat);
}

static void saveFST(const VectorFst<StdArc> &fst, std::string key, std::string wspecifier, bool opt = false) {
  kaldi::TableWriter<fst::VectorFstHolder> writer(wspecifier);
  if (!opt) {
    writer.Write(key, fst);
    return;
  }

  VectorFst<StdArc> tmp = fst, tmp2;
  RmEpsilon(&tmp);
  Determinize(tmp, &tmp2);
  writer.Write(key, tmp2);
}
#endif

/**
 * filter fst_src by allowing only symbols in the given FST to be outputed.
 */
template<class Arc>
void filterFST(const VectorFst<Arc> &fst_src,
               const VectorFst<Arc> &fst_syms,
               VectorFst<Arc> *pfst_des) {
  typedef typename Arc::Label Label;
  typedef typename Arc::StateId StateId;
  typedef typename Arc::Weight Weight;
  std::set<Label> sym_set;
  sym_set.clear();
  for (StateIterator<Fst<Arc> > siter(fst_syms); !siter.Done(); siter.Next()) {
    const StateId &s = siter.Value();
    for (ArcIterator<Fst<Arc> > aiter(fst_syms, s); !aiter.Done(); aiter.Next()) {
      const Arc &arc = aiter.Value();
      sym_set.insert(arc.olabel);
    }
  }
  typename std::set<Label>::iterator si;
  VectorFst<Arc> fst_filter;
  StateId s = fst_filter.AddState();
  fst_filter.SetStart(s);
  for (si = sym_set.begin(); si != sym_set.end(); si++) {
    fst_filter.AddArc(s, Arc(*si, *si, Weight::One(), s));
  }
  fst_filter.SetFinal(s, Weight::One());
  Compose(fst_src, fst_filter, pfst_des); // fst_src should have been olabel-sorted
}

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
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
        "Usage: lattice-amrescore [options] <lattice-rspecifier> <E.fst> <L.fst> <lattice-wspecifier|s2s-FSTs-wspecifier>\n"
        " e.g.: lattice-amrescore ark:in.lats E.fst L.fst ark:out.lats\n";
      
    ParseOptions po(usage);
    BaseFloat acoustic_scale = 0.1;
    BaseFloat lm_scale = 1.0;
    int32 n = 1000;
    //int32 confused_path_nbest = 100;
    double confused_path_beam = 5;
    int32 max_states = 100000;
    std::string s2s_rxfilename;
    bool s2s_only = false;
#ifdef _INPUT_S2S
    std::string s2s_filename;
#endif
    //po.Register("confused-path-nbest", &confused_path_nbest, "Prune (Lat0xL'xE)x(LxLat0) transducer to "
    //            "only contain top n paths, -1 means all paths.");
    po.Register("confused-path-beam", &confused_path_beam, "Prune (Lat0xL'xE)x(LxLat0) transducer to the "
                "given beam, -1 means no prune.");
    po.Register("max-states", &max_states, "Prune (Lat0xL'xE)x(LxLat0) transducer to the "
                "given number of states, 0 means no prune.");
    
    po.Register("acoustic-scale", &acoustic_scale, "Scaling factor for acoustic likelihoods; used in lattice pruning"); 
    po.Register("lm-scale", &lm_scale, "Scaling factor for language model costs; used in lattice pruning");
    po.Register("n", &n, "Maximum number of paths for score tuning");
    po.Register("s2s-rxfilename", &s2s_rxfilename, "sequence to sequence confusion FSTs filename, with the same key as lattice-rspecifier");
    po.Register("s2s-only", &s2s_only, "generate sequence to sequence confusion FSTs only. This should be false if s2s_rxfilename is specified");
#ifdef _INPUT_S2S
    po.Register("s2s-filename", &s2s_filename, "sequence to sequence FST filename, only for debug");
#endif
    po.Read(argc, argv);

    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string lats_rspecifier = po.GetArg(1),
        E_filename = po.GetArg(2),
        L_filename = po.GetArg(3),
        lats_wspecifier = po.GetArg(4);

    if (!s2s_rxfilename.empty() && s2s_only) {
      po.PrintUsage();
      exit(1);
    }
    // Read as compact lattice
    // Use regular lattice when we need it in for efficient
    // composition and determinization.
    SequentialCompactLatticeReader lattice_reader(lats_rspecifier);
    RandomAccessTableReader<VectorFstHolder> s2s_reader(s2s_rxfilename);
    // Write as compact lattice.
    CompactLatticeWriter lattice_writer;
    TableWriter<VectorFstHolder> s2s_writer;
    if (!s2s_only) {
      lattice_writer.Open(lats_wspecifier);
    } else {
      s2s_writer.Open(lats_wspecifier);
    }
    
    VectorFst<StdArc> *pE, *pL;
    if (s2s_rxfilename.empty()) {
      pE = ReadFstKaldi(E_filename);
      pL = ReadFstKaldi(L_filename);
      ArcSort(pL, OLabelCompare<StdArc>());
      ArcSort(pE, ILabelCompare<StdArc>());
    }
#ifdef _INPUT_S2S
    VectorFst<StdArc> *ps2s;
    if (!s2s_filename.empty()) {
      ps2s = ReadFstKaldi(s2s_filename);
    } else {
      KALDI_ERR << "s2s filename is empty";
    }
#endif


    int32 n_done = 0, n_fail = 0;
    
    // LM and AM scales for ShortestPath
    vector<vector<double> > scale_shortestpath = fst::LatticeScale(lm_scale, acoustic_scale);
    vector<vector<double> > scale_shortestpath_reverse = fst::LatticeScale(1/lm_scale, 1/acoustic_scale);
    // Scale for FST converting (to zero)
    vector<vector<double> > scale_0 = fst::LatticeScale(0.0, 0.0);
    // Scale for FST converting (lm to zero)
    // TODO check the meaning of 0.0 and 1.0 in scales
    vector<vector<double> > scale_am_only = fst::LatticeScale(0.0, 1.0);
    // Scale for FST converting (am to zero)
    vector<vector<double> > scale_lm_only = fst::LatticeScale(1.0, 0.0);

#ifdef _STATS
    double retainRate = 0.0;
    double selfConfRate = 0.0;
#endif
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
      } // got lat
      
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
        RmEpsilon(&fst_0);

        ScaleLattice(scale_am_only, &lat_am); // scales lm to zero.
        ConvertLattice(lat_am, &fst_am); // this adds up the (lm,acoustic) costs to get
        // the normal (tropical) costs.
        Project(&fst_am, PROJECT_OUTPUT);
        RmEpsilon(&fst_am);
        VectorFst<StdArc> tmp = fst_am;
        Determinize(tmp, &fst_am);
        Minimize(&fst_am);
        ArcSort(&fst_am, ILabelCompare<StdArc>());
      }
#ifdef _DEBUG
      saveFST(fst_am, "key", "ark:fst_am.fsts");
#endif

      VectorFst<StdArc> s2s; // sequence to sequence FST with confusion weights
#ifdef _INPUT_S2S
      s2s = *ps2s;
#else
      if (!s2s_rxfilename.empty()) {
        if (!s2s_reader.HasKey(key)) {
          KALDI_ERR << "Wrong s2s file, key " << key << " not found.";
        }
        s2s = s2s_reader.Value(key);
      } else {
        // retain only words appearing in the lattice for efficiency
        KALDI_LOG << "Filtering L";
        VectorFst<StdArc> L;
        filterFST(*pL, fst_0, &L);
        RmEpsilon(&L);
#ifdef _DEBUG
        saveFST(L, "key", "ark:filtered_L.fsts");
#endif

        KALDI_LOG << "Generate Li x E";
        VectorFst<StdArc> LixE;
        {
          VectorFst<StdArc> Li = L;
          Invert(&Li);
          Compose(Li, *pE, &LixE); // *pE was ilabel-sorted
          RmEpsilon(&LixE);
        }
#ifdef _DEBUG
        saveFST(LixE, "key", "ark:filtered_LixE.fsts");
#endif

        {
          // 2. Generate L x Lat_0
          KALDI_LOG << "Generate L x Lat_0";
          VectorFst<StdArc> LxLat0;
          ArcSort(&L, OLabelCompare<StdArc>());
          Compose(L, fst_0, &LxLat0);
          RmEpsilon(&LxLat0);
#ifdef _DEBUG
          saveFST(LxLat0, "key", "ark:LxLat0.fsts");
#endif

          // 3. Generate (Lat_0 x (Li x E)) x L) x Lat_0
          {
            KALDI_LOG << "Generate Lat_0 x (Li x E)";
            VectorFst<StdArc> tmp;
            ArcSort(&fst_0, OLabelCompare<StdArc>());
            Compose(fst_0, LixE, &tmp);
#ifdef _DEBUG
            //saveFST(tmp, "key", "ark:Lat0xLixE.fsts");
#endif
            KALDI_LOG << "Generate Lat_0 x (Li x E) x L";
            ArcSort(&tmp, OLabelCompare<StdArc>());
            ArcSort(&L, ILabelCompare<StdArc>());
            if (confused_path_beam >= 0) {
              // We only use the delayed FST when pruning is requested, because we do
              // the optimization in pruning.
              // Composing KxL2xE and L1'. We assume L1' is ilabel sorted.
              ComposeFst<StdArc> lazy_compose(tmp, L);
              tmp.DeleteStates();

              //ProjectFst<StdArc> lazy_project(lazy_compose, PROJECT_OUTPUT);

              // This will likely be the most time consuming part, we use a special
              // pruning algorithm where we don't expand the full FST.
              KALDI_VLOG(1) << "Prune(Lat0xL'xE)xL, beam=" << confused_path_beam;
              PruneSpecial(lazy_compose, &s2s, confused_path_beam, max_states);
            } else {
              // If no pruning is requested, we do the normal composition.
              Compose(tmp, L, &s2s);
              RmEpsilon(&s2s);
            }
            KALDI_LOG << "Generate (Lat_0 x (Li x E) x L) x Lat_0";
            Compose(s2s, fst_0, &tmp);
            RmEpsilon(&tmp);
            s2s = tmp;
            /*
            ArcSort(&LxLat0, ILabelCompare<StdArc>());
            if (confused_path_beam >= 0) {
              // We only use the delayed FST when pruning is requested, because we do
              // the optimization in pruning.
              // Composing KxL2xE and L1'. We assume L1' is ilabel sorted.
              ComposeFst<StdArc> lazy_compose(tmp, LxLat0);
              tmp.DeleteStates();

              //ProjectFst<StdArc> lazy_project(lazy_compose, PROJECT_OUTPUT);

              // This will likely be the most time consuming part, we use a special
              // pruning algorithm where we don't expand the full FST.
              KALDI_VLOG(1) << "Prune(Lat0xL'xE)x(LxLat0), beam=" << confused_path_beam;
              PruneSpecial(lazy_compose, &s2s, confused_path_beam, max_states);
            } else {
              // If no pruning is requested, we do the normal composition.
              Compose(tmp, LxLat0, &s2s);
              RmEpsilon(&s2s);
            }*/
            ArcSort(&s2s, ILabelCompare<StdArc>());
#ifdef _DEBUG
            saveFST(s2s, "key", "ark:Lat0xLixExLxLat0.fsts");
#endif
            //Determinize(tmp, &tmp2);
          }
        }
      }
#endif // _INPUT_S2S

      if (s2s_only) {
        s2s_writer.Write(key, s2s);
        n_done++;
        continue;
      }

#ifdef _STATS
      VectorFst<StdArc> s2s_for_stats;
      {
        VectorFst<StdArc> tmp = s2s;
        Project(&tmp, PROJECT_OUTPUT);
        //Determinize(tmp, &s2s_for_stats); // this consumes too much memory for some lattices
        s2s_for_stats = tmp;
        RmEpsilon(&s2s_for_stats);
      }

      int32 retainNum = 0, selfConfNum = 0;
#endif


      // 4. Iterate top n paths and get weights for each H 
      ScaleLattice(scale_shortestpath, &lat);
      KALDI_LOG << "Getting " << n << " shortest";
      vector<Lattice> nbest_lats;
      {
        Lattice nbest_lat;
        fst::ShortestPath(lat, &nbest_lat, n);

        ScaleLattice(scale_shortestpath_reverse, &nbest_lat);
        fst::ConvertNbestToVector(nbest_lat, &nbest_lats);
      }

      if (nbest_lats.empty()) {
        KALDI_WARN << "Possibly empty lattice for utterance-id " << key
          << "(no N-best entries)";
      } else {
        Lattice lat_union; 
        KALDI_LOG << "Iterate top n paths and get weights for each H";
        KALDI_LOG << "Union tuned paths: " << nbest_lats.size();
        for (int32 k = 0; k < static_cast<int32>(nbest_lats.size()); k++) {
          std::ostringstream os;
          //os << key << "-" << (k+1); // so if key is "utt_id", the keys
          // of the n-best are utt_id-1, utt_id-2, utt_id-3, etc.
          //std::string nbest_key = os.str();
          Lattice H_tuned = nbest_lats[k];

          {
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
            //StdArc::Weight acoustic_weight;
            {
              VectorFst<StdArc> H;
              ConvertLattice(nbest_lats[k], &H);
              Project(&H, fst::PROJECT_OUTPUT);
              RmEpsilon(&H);
#ifdef _DEBUG
              {
                std::ostringstream os;
                os << "ark:H" << k << ".fsts";
                saveFST(H, "key", os.str());
              }
#endif

#ifdef _STATS
              {
                // Check whether s2s contains this H
                VectorFst<StdArc> tmp;
                Compose(H, s2s_for_stats, &tmp);
                RmEpsilon(&tmp);
                if (!(tmp.NumStates() == 0 || (tmp.NumStates() == 1 && tmp.NumArcs(tmp.Start()) == 0)) ) {
                  retainNum++;
                }
              }
#endif

              VectorFst<StdArc> fst_confusion_given_H;
              {
                VectorFst<StdArc> tmp;
                Compose(H, s2s, &tmp); // s2s was ilabel-sorted
                Project(&tmp, PROJECT_OUTPUT);
                RmEpsilon(&tmp);
                // LogArc
                VectorFst<LogArc> fst_log, tmp_log;
                Cast(tmp, &fst_log);
                Determinize(fst_log, &tmp_log);
                RmEpsilon(&tmp_log);
                Minimize(&tmp_log);
                RmEpsilon(&tmp_log);
                Cast(tmp_log, &fst_confusion_given_H);
                
                /* // StdArc
                Determinize(tmp, &fst_confusion_given_H);
                RmEpsilon(&fst_confusion_given_H);
                Minimize(&fst_confusion_given_H);
                RmEpsilon(&fst_confusion_given_H);
                */
              }
#ifdef _DEBUG
              {
                std::ostringstream os;
                os << "ark:H" << k << "xLat0xLixExLxLat0.fsts";
                saveFST(fst_confusion_given_H, "key", os.str());
              }
#endif
#ifdef _STATS
              {
                /*
                VectorFst<StdArc> tmp;
                Compose(H, fst_confusion_given_H, &tmp);
                RmEpsilon(&tmp);
                if (!(tmp.NumStates() == 0 || (tmp.NumStates() == 1 && tmp.NumArcs(tmp.Start()) == 0)) ) {
                  KALDI_LOG << "Confusion weight of H confused to H (before stoch): " << ComputeDagTotalWeight(tmp).Value();
                }
                */
              }
#endif
              {
                VectorFst<LogArc> fst_log;
                Cast(fst_confusion_given_H, &fst_log);
                RescaleDagToStochastic(&fst_log);
                Cast(fst_log, &fst_confusion_given_H);
              }
#ifdef _STATS
              {
                // Check whether fst_confusion_given_H contains this H
                VectorFst<StdArc> tmp;
                Compose(H, fst_confusion_given_H, &tmp);
                RmEpsilon(&tmp);
                if (!(tmp.NumStates() == 0 || (tmp.NumStates() == 1 && tmp.NumArcs(tmp.Start()) == 0)) ) {
                  selfConfNum++;
                  //KALDI_LOG << "Confusion weight of H confused to H (after stoch): " << ComputeDagTotalWeight(tmp).Value();
                }
              }
#endif

#ifdef _DEBUG
              {
                std::ostringstream os;
                os << "ark:stoch_H" << k << "xLat0xLixExLxLat0.fsts";
                saveFST(fst_confusion_given_H, "key", os.str());
              }
#endif

              // Get fst_tuned_for_H (full lattice with each path's weight = conf_weight + am_weight)
              VectorFst<StdArc> fst_tuned_for_H;
              Compose(fst_confusion_given_H, fst_am, &fst_tuned_for_H); // fst_am was ilabel-sorted
              //////////////////////////////
              //Compose(H, fst_am, &fst_tuned_for_H); // TEST, should result in original WER
              //////////////////////////////
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
                // LogArc
                VectorFst<LogArc> fst_log;
                Cast(fst_tuned_for_H, &fst_log);
                acoustic_weight = ComputeDagTotalWeight(fst_log);
                //acoustic_weight = ComputeDagTotalWeight(fst_tuned_for_H); //StdArc
                //KALDI_LOG << "Total weight of path " << k << " is " << acoustic_weight.Value();
              }
            }
            
            // Set acoustic score on 1st arc
            {
              LatticeArc::StateId s = H_tuned.Start();
              KALDI_ASSERT(H_tuned.NumArcs(s) == 1);
              ArcIterator<Lattice > aiter(H_tuned, s);
              LatticeArc first_arc = aiter.Value();
              first_arc.weight.SetValue2(acoustic_weight.Value());
              H_tuned.DeleteArcs(s);
              H_tuned.AddArc(s, first_arc);
            }
#ifdef _DEBUG
            {
              std::ostringstream os, os2;
              os << "H" << k << "_tuned";
              os2 << "ark:H" << k << "_tuned.fsts";
              saveLattice(H_tuned, os.str(), os2.str());
            }
#endif
          }

          Union(&lat_union, H_tuned);
          // Optimize every 10k paths, otherwise it may cause segmentation error in some case
          if (k % 10000 == 0) {
            Project(&lat_union, PROJECT_OUTPUT);
            RmEpsilon(&lat_union);
            {
              Lattice tmp = lat_union;
              Determinize(tmp, &lat_union);
            }
            Minimize(&lat_union);
          }
        }
#ifdef _DEBUG
        saveLattice(lat_union, "union_H", "ark:union_H.fsts");
#endif

#ifdef _STATS
        {
          double this_retainRate = 1.0 * retainNum / nbest_lats.size();
          double this_selfConfRate = 1.0 * selfConfNum / nbest_lats.size();
          retainRate += this_retainRate;
          selfConfRate += this_selfConfRate;
          KALDI_LOG << "Retained rate: " << this_retainRate * 100 << " %";
          KALDI_LOG << "Self confusion rate: " << this_selfConfRate * 100 << " %";
        }
#endif

        {
          KALDI_LOG << "Optimize: det and min";
          Lattice tmp;
          Project(&lat_union, PROJECT_OUTPUT);
          RmEpsilon(&lat_union);
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
        lattice_writer.Write(key, clat_tuned);
        n_done++;
      }
    }
    if (s2s_rxfilename.empty()) {
      delete pL;
      delete pE;
    }

#ifdef _STATS
    KALDI_LOG << "Average retained rate: " << 100.0 * retainRate / n_done << " %";
    KALDI_LOG << "Average self confusion rate: " << 100.0 * selfConfRate / n_done << " %";
#endif
    KALDI_LOG << "Done " << n_done << " lattices, failed for " << n_fail;
    return (n_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
