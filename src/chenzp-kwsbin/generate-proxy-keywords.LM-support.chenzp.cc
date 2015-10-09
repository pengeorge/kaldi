// kwsbin/generate-proxy-keywords.cc

// Copyright 2012  Johns Hopkins University (Author: Guoguo Chen)

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

const unsigned long MIN_FREE_RAM = 512*1024; // set minimum available requirement to 512MB

#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "fstext/fstext-utils.h"
#include "fstext/kaldi-fst-io.h"
#include "fstext/prune-special.h"
#include <fst/union.h>

// For multi-threads
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include <pthread.h>
// For fork
#include <sys/types.h>
#include <sys/wait.h>

#include "chenzp-util/mem-util.h"

namespace fst {

bool PrintProxyFstPath(const VectorFst<StdArc> &proxy,
                       vector<vector<StdArc::Label> > *path,
                       vector<StdArc::Weight> *weight,
                       StdArc::StateId cur_state,
                       vector<StdArc::Label> cur_path,
                       StdArc::Weight cur_weight) {
  if (proxy.Final(cur_state) != StdArc::Weight::Zero()) {
    // Assumes only final state has non-zero weight.
    cur_weight = Times(proxy.Final(cur_state), cur_weight);
    path->push_back(cur_path);
    weight->push_back(cur_weight);
    return true;
  }

  for (ArcIterator<StdFst> aiter(proxy, cur_state);
       !aiter.Done(); aiter.Next()) {
    const StdArc &arc = aiter.Value();
    StdArc::Weight temp_weight = Times(arc.weight, cur_weight);
    cur_path.push_back(arc.ilabel);
    PrintProxyFstPath(proxy, path, weight,
                      arc.nextstate, cur_path, temp_weight);
    cur_path.pop_back();
  }

  return true;
}
}

using namespace kaldi;
using namespace fst;
typedef kaldi::int32 int32;
typedef kaldi::uint64 uint64;
typedef StdArc::StateId StateId;
typedef StdArc::Weight Weight;
pid_t jpid; // Current job process ID
VectorFst<StdArc> *L2xE;
VectorFst<StdArc> *L1;
VectorFst<StdArc> *additional_fst;
TableWriter<VectorFstHolder> *p_proxy_writer;
TableWriter<BasicVectorHolder<double> > *p_kwlist_writer;
RandomAccessTableReader<VectorFstHolder> *p_prior_reader;
const VectorFst<StdArc> *fstprior;

struct JobPara {
  std::string key;
  std::vector<int32> keyword;
  int32 max_states;
  int32 phone_nbest;
  int32 proxy_nbest;
  int32 proxy_nbest0;
  double phone_beam;
  double proxy_beam;
  ParseOptions *p_po;
  VectorFst<StdArc> *additional_fst;
};

int funProcessJob(void *jobpara) {

  pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);
  pthread_setcanceltype(PTHREAD_CANCEL_ASYNCHRONOUS, NULL);

  std::string &key = ((JobPara *)jobpara)->key;
  std::vector<int32> &keyword = ((JobPara *)jobpara)->keyword;
  int32 max_states = ((JobPara*)jobpara)->max_states;
  int32 phone_nbest = ((JobPara*)jobpara)->phone_nbest;
  int32 proxy_nbest = ((JobPara*)jobpara)->proxy_nbest;
  int32 proxy_nbest0 = ((JobPara*)jobpara)->proxy_nbest0;
  double phone_beam = ((JobPara*)jobpara)->phone_beam;
  double proxy_beam = ((JobPara*)jobpara)->proxy_beam;
  ParseOptions *p_po = ((JobPara*)jobpara)->p_po; 
  VectorFst<StdArc> *additional_fst = ((JobPara*)jobpara)->additional_fst;
  try {
      VectorFst<StdArc> proxy;
      VectorFst<StdArc> tmp_proxy;
      MakeLinearAcceptor(keyword, &proxy);

      // Composing K and L2xE. We assume L2xE is ilabel sorted.
      KALDI_VLOG(1) << "K: " << proxy.NumStates() << " s, " << NumArcs(proxy) << " a.";
      KALDI_VLOG(1) << "Compose(K, L2xE)";
      ArcSort(&proxy, OLabelCompare<StdArc>());
      Compose(proxy, *L2xE, &tmp_proxy);

      // Processing KxL2xE.
      KALDI_VLOG(1) << "Project(KxL2xE, PROJECT_OUTPUT)";
      Project(&tmp_proxy, PROJECT_OUTPUT);
      if (phone_beam >= 0) {
        KALDI_VLOG(1) << "Prune(KxL2xE, " << phone_beam << ")";
        Prune(&tmp_proxy, phone_beam);
      }
      KALDI_VLOG(1) << "KxL2xE: " << tmp_proxy.NumStates() << " s, " << NumArcs(tmp_proxy) << " a.";
      if (phone_nbest > 0) {
        KALDI_VLOG(1) << "ShortestPath(KxL2xE, " << phone_nbest << ")";
        RmEpsilon(&tmp_proxy);
        ShortestPath(tmp_proxy, &proxy, phone_nbest, true, true);
        tmp_proxy.DeleteStates();   // Not needed for now.
        KALDI_VLOG(1) << "Determinize(KxL2xE)";
        Determinize(proxy, &tmp_proxy);
        proxy.DeleteStates();       // Not needed for now.
      }
      KALDI_VLOG(1) << "ArcSort(KxL2xE, OLabel)";
      proxy = tmp_proxy;
      tmp_proxy.DeleteStates();     // Not needed for now.
      ArcSort(&proxy, OLabelCompare<StdArc>());

      // Processing KxL2xExL1'.
      RmEpsilon(&proxy);
      ArcSort(&proxy, OLabelCompare<StdArc>());
      if (proxy_beam >= 0) {
        // We only use the delayed FST when pruning is requested, because we do
        // the optimization in pruning.
        // Composing KxL2xE and L1'. We assume L1' is ilabel sorted.
        KALDI_VLOG(1) << "Compose(KxL2xE, L1')";
        ComposeFst<StdArc> lazy_compose(proxy, *L1);
        proxy.DeleteStates();

        KALDI_VLOG(1) << "Project(KxL2xExL1', PROJECT_OUTPUT)";
        ProjectFst<StdArc> lazy_project(lazy_compose, PROJECT_OUTPUT);

        // This will likely be the most time consuming part, we use a special
        // pruning algorithm where we don't expand the full FST.
        KALDI_VLOG(1) << "Prune(KxL2xExL1', " << proxy_beam << ")";
        PruneSpecial(lazy_project, &tmp_proxy, proxy_beam, max_states);
/*      if (false && additional_fst) {  // this would cause efficiency problem
          RmEpsilon(&tmp_proxy);
          KALDI_VLOG(1) << "KxL2xExL1 (eps removed): " << tmp_proxy.NumStates() << " s, " << NumArcs(tmp_proxy) << " a.";
          KALDI_VLOG(1) << "ArcSort(KxL2xExL1, OLabel)"; // requires additional FST to be sorted by ilabel
          ArcSort(&tmp_proxy, OLabelCompare<StdArc>());
          KALDI_VLOG(1) << "Compose(KxL2xExL1, G')";
          ComposeFst<StdArc> lazy_compose_G(tmp_proxy, *additional_fst);
          tmp_proxy.DeleteStates();
          //KALDI_VLOG(1) << "KxL2xExL1xG': " << NumArcs(lazy_compose_G) << " a.";
          KALDI_VLOG(1) << "Prune(KxL2xExL1'xG', " << proxy_beam << ")";
          PruneSpecial(lazy_compose_G, &tmp_proxy, proxy_beam, max_states);
          KALDI_VLOG(1) << "KxL2xExL1xG' (pruned): " << tmp_proxy.NumStates() << " s, " << NumArcs(tmp_proxy) << " a.";
        }*/
      } else {
        // If no pruning is requested, we do the normal composition.
        KALDI_VLOG(1) << "Compose(KxL2xE, L1')";
        Compose(proxy, *L1, &tmp_proxy);
        proxy.DeleteStates();

        KALDI_VLOG(1) << "Project(KxL2xExL1', PROJECT_OUTPUT)";
        Project(&tmp_proxy, PROJECT_OUTPUT);
        KALDI_VLOG(1) << "KxL2xExL1: " << tmp_proxy.NumStates() << " s, " << NumArcs(tmp_proxy) << " a.";
     /* if (false && additional_fst) { // This may NOT WORK !!!
          proxy = tmp_proxy;
          tmp_proxy.DeleteStates(); // Not needed for now.
          RmEpsilon(&proxy);
          KALDI_VLOG(1) << "KxL2xExL1 (eps removed): " << proxy.NumStates() << " s, " << NumArcs(proxy) << " a.";
          KALDI_VLOG(1) << "ArcSort(KxL2xExL1, OLabel)"; // requires additional FST to be sorted by ilabel
          ArcSort(&proxy, OLabelCompare<StdArc>());
          KALDI_VLOG(1) << "Compose(KxL2xExL1, G')";
          Compose(proxy, *additional_fst, &tmp_proxy);
          proxy.DeleteStates();
          KALDI_VLOG(1) << "KxL2xExL1xG': " << tmp_proxy.NumStates() << " s, " << NumArcs(tmp_proxy) << " a.";
        }*/
      }
      // Compose with additional FST (we can also compose additional FST before proxy_beam pruning)
/*    if (false && additional_fst) {// this would cause efficiency problem
        proxy = tmp_proxy;
        tmp_proxy.DeleteStates(); // Not needed for now.
        RmEpsilon(&proxy);
        KALDI_VLOG(1) << "KxL2xExL1 (eps removed): " << proxy.NumStates() << " s, " << NumArcs(proxy) << " a.";
        KALDI_VLOG(1) << "ArcSort(KxL2xExL1, OLabel)"; // requires additional FST to be sorted by ilabel
        ArcSort(&proxy, OLabelCompare<StdArc>());
        //ComposeFst<StdArc> lazy_compose(proxy, *(jobpara.additional_fst));
        KALDI_VLOG(1) << "Compose(KxL2xExL1, G')";
        Compose(proxy, *additional_fst, &tmp_proxy);
        proxy.DeleteStates();
        KALDI_VLOG(1) << "KxL2xExL1xG': " << tmp_proxy.NumStates() << " s, " << NumArcs(tmp_proxy) << " a.";
      }*/
      if (proxy_nbest > 0) {
        // If no additional_fst, or nbest0 not specified, or nbest0 is illegal,
        // just ignore nbest0 and use proxy_nbest.
        if (!additional_fst || proxy_nbest0 == -1 || proxy_nbest0 < proxy_nbest) {
          proxy_nbest0 = proxy_nbest;
        }
        proxy = tmp_proxy;
        tmp_proxy.DeleteStates(); // Not needed for now.
        //KALDI_VLOG(1) << "KxL2xExL1[xG']: " << proxy.NumStates() << " s, " << NumArcs(proxy) << " a.";
        RmEpsilon(&proxy);
        KALDI_VLOG(1) << "KxL2xExL1 (eps removed): " << proxy.NumStates() << " s, " << NumArcs(proxy) << " a.";
        KALDI_VLOG(1) << "ShortestPath(KxL2xExL1', " << proxy_nbest0 << ")";
        ShortestPath(proxy, &tmp_proxy, proxy_nbest0, true, true);
        KALDI_VLOG(1) << "KxL2xExL1 (" << proxy_nbest0 << " shortest paths): " << tmp_proxy.NumStates() << " s, " << NumArcs(tmp_proxy) << " a.";
        proxy.DeleteStates();     // Not needed for now.
        // Force including the prior proxies (chenzp, Nov 18,2014)
        if (p_prior_reader && p_prior_reader->HasKey(key)) {
          //const VectorFst<StdArc> &fstprior(p_prior_reader->Value(key));
          fstprior = &(p_prior_reader->Value(key));
          VectorFst<StdArc> projected_prior_fst;
          MakeLinearAcceptor(keyword, &proxy);
          Compose(proxy, *fstprior, &projected_prior_fst);
          KALDI_VLOG(1) << "Prior FST: " << projected_prior_fst.NumStates() << " s, " << NumArcs(projected_prior_fst) << " a.";
          Project(&projected_prior_fst, PROJECT_OUTPUT);
          Union(&tmp_proxy, projected_prior_fst);
          projected_prior_fst.DeleteStates();
          KALDI_VLOG(1) << "After including prior proxies: " << tmp_proxy.NumStates() << " s, " << NumArcs(tmp_proxy) << " a.";
        } else {
          KALDI_VLOG(1) << "No key found in prior FSTs";
        }
      }
      if (additional_fst) {
        proxy = tmp_proxy;
        tmp_proxy.DeleteStates(); // Not needed for now.
        RmEpsilon(&proxy);
        KALDI_VLOG(1) << "KxL2xExL1 (eps removed): " << proxy.NumStates() << " s, " << NumArcs(proxy) << " a.";
        KALDI_VLOG(1) << "ArcSort(KxL2xExL1, OLabel)"; // requires additional FST to be sorted by ilabel
        ArcSort(&proxy, OLabelCompare<StdArc>());
        //ComposeFst<StdArc> lazy_compose(proxy, *(jobpara.additional_fst));
        KALDI_VLOG(1) << "Compose(KxL2xExL1, G')";
        Compose(proxy, *additional_fst, &tmp_proxy);
        proxy.DeleteStates();
        KALDI_VLOG(1) << "KxL2xExL1xG': " << tmp_proxy.NumStates() << " s, " << NumArcs(tmp_proxy) << " a.";
        if (proxy_nbest > 0 && proxy_nbest < proxy_nbest0) {
          proxy = tmp_proxy;
          tmp_proxy.DeleteStates(); // Not needed for now.
          RmEpsilon(&proxy);
          KALDI_VLOG(1) << "KxL2xExL1xG' (eps removed): " << proxy.NumStates() << " s, " << NumArcs(proxy) << " a.";
          KALDI_VLOG(1) << "ShortestPath(KxL2xExL1'xG', " << proxy_nbest << ")";
          ShortestPath(proxy, &tmp_proxy, proxy_nbest, true, true);
          KALDI_VLOG(1) << "KxL2xExL1xG' (" << proxy_nbest << " shortest paths): " << tmp_proxy.NumStates() << " s, " << NumArcs(tmp_proxy) << " a.";
          proxy.DeleteStates();     // Not needed for now.
        }
      }
      KALDI_VLOG(1) << "RmEpsilon(KxL2xExL1')";
      RmEpsilon(&tmp_proxy);
      KALDI_VLOG(1) << "Determinize(KxL2xExL1')";
      Determinize(tmp_proxy, &proxy);
      tmp_proxy.DeleteStates();
      KALDI_VLOG(1) << "ArcSort(KxL2xExL1', OLabel)";
      ArcSort(&proxy, fst::OLabelCompare<StdArc>());
      KALDI_VLOG(1) << "Final KxL2xExL1: " << proxy.NumStates() << " s, " << NumArcs(proxy) << " a.";

      // Write the proxy FST.
      p_proxy_writer->Write(key, proxy);

      // Print the proxy FST with each line looks like "kwid weight proxy"
      if (p_po->NumArgs() >= 5) {
        if (proxy.Properties(kAcyclic, true) == 0) {
          KALDI_WARN << "Proxy FST has cycles, skip printing paths for " << key;
        } else {
          vector<vector<StdArc::Label> > path;
          vector<StdArc::Weight> weight;
          PrintProxyFstPath(proxy, &path, &weight, proxy.Start(),
                            vector<StdArc::Label>(), StdArc::Weight::One());
          KALDI_ASSERT(path.size() == weight.size());
          for (int32 i = 0; i < path.size(); i++) {
            vector<double> kwlist;
            kwlist.push_back(static_cast<double>(weight[i].Value()));
            for (int32 j = 0; j < path[i].size(); j++) {
              kwlist.push_back(static_cast<double>(path[i][j]));
            }
            p_kwlist_writer->Write(key, kwlist);
          }
        }
      }
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return 1;
  }
  return 0;
}

pthread_t mtid; // Monitor thread ID

void *funThreadMonitor(void *para) {
  while (1) {
    sleep(30);
    if (jpid == 0) {
      continue;
    }
    unsigned long total, free, buffer, cache;
    double vm, resident;
    process_mem_usage(vm, resident, jpid); 
    //get_raminfo(total, free, buffer);
    //unsigned long available = (free + buffer) / 1024;
    unsigned long available = get_availableRam(total, free, buffer, cache);
    if (available < MIN_FREE_RAM) {
      KALDI_VLOG(1) << "[I] Total/Free/Buffer/Cached (KB): " << total << ", " << free << ", " << buffer << ", " << cache;
      KALDI_VLOG(1) << "[W] PID: " << jpid << ". Memory Usage: " << resident << " KB";
      if (2 * resident > total - available) { // Only kill those processes occupying more than half used memory
        KALDI_VLOG(1) << "[W] Only " << available << " KB available. Current job will be killed.";
        if (jpid > 0) {
          kill(jpid, SIGINT);
        }
      }
    }
  }
  return ((void *)0);
}


int main(int argc, char *argv[]) {
  try {
    int err;
    // Create a thread to monitor memory usage.
    if ((err = pthread_create(&mtid, NULL, funThreadMonitor, NULL))) {
      KALDI_VLOG(1) << "[E] Cannot create monitor thread, memory monitor will not work.";
    }


    const char *usage =
        "Convert the keywords into in-vocabulary words using the given phone\n"
        "level edit distance fst (E.fst). The large lexicon (L2.fst) and\n"
        "inverted small lexicon (L1'.fst) are also expected to be present. We\n"
        "actually use the composed FST L2xE.fst to be more efficient. Ideally\n"
        "we should have used L2xExL1'.fst but this is quite computationally\n"
        "expensive at command level. Keywords.int is in the transcription\n"
        "format. If kwlist-wspecifier is given, the program also prints out\n"
        "the proxy fst in a format where each line is \"kwid weight proxy\".\n"
        "\n"
        "Usage: generate-proxy-keywords [options] <L2xE.fst> <L1'.fst> \\\n"
        "    <keyword-rspecifier> <proxy-wspecifier> [kwlist-wspecifier] \n"
        " e.g.: generate-proxy-keywords L2xE.fst L1'.fst ark:keywords.int \\\n"
        "                           ark:proxy.fsts [ark,t:proxy.kwlist.txt]\n";

    ParseOptions po(usage);

    int32 max_states = 100000;
    int32 phone_nbest = 50;
    int32 proxy_nbest = 100;
    int32 proxy_nbest0 = -1;
    double phone_beam = 5;
    double proxy_beam = 5;
    std::string prior_rspecifier;
    std::string additional_fst_filename;
    po.Register("phone-nbest", &phone_nbest, "Prune KxL2xE transducer to only "
                "contain top n phone sequences, -1 means all sequences.");
    po.Register("proxy-nbest", &proxy_nbest, "Prune KxL2xExL1'[xG'] transducer to "
                "only contain top n proxy keywords, -1 means all proxies.");
    po.Register("phone-beam", &phone_beam, "Prune KxL2xE transducer to the "
                "given beam, -1 means no prune.");
    po.Register("proxy-beam", &proxy_beam, "Prune KxL2xExL1' transducer to the "
                "given beam, -1 means no prune.");
    po.Register("max-states", &max_states, "Prune kxL2xExL1' transducer to the "
                "given number of states, 0 means no prune.");
    po.Register("prior", &prior_rspecifier, "Results of the composition of keywords "
                "and prior FSTs would be forced including in the proxies.");
    po.Register("additional-fst", &additional_fst_filename, "Proxy FSTs would be composed "
                "with this to introduce additional weights (e.g. LM weights).");
    po.Register("proxy-nbest0", &proxy_nbest0, "Prune KxL2xExL1' transducer to "
                "only contain top n0 proxy keywords before additional-fst is "
                "composed, -1 means using proxy-nbest only.");

    po.Read(argc, argv);

    // Checks input options.
    if (phone_nbest != -1 && phone_nbest <= 0) {
      KALDI_ERR << "--phone-nbest must either be -1 or positive.";
      exit(1);
    }
    if (proxy_nbest != -1 && proxy_nbest <= 0) {
      KALDI_ERR << "--proxy-nbest must either be -1 or positive.";
      exit(1);
    }
    if (proxy_nbest0 != -1 && proxy_nbest0 <= 0) {
      KALDI_ERR << "--proxy-nbest0 must either be -1 or positive.";
      exit(1);
    }
    if (phone_beam != -1 && phone_beam < 0) {
      KALDI_ERR << "--phone-beam must either be -1 or non-negative.";
      exit(1);
    }
    if (proxy_beam != -1 && proxy_beam <=0) {
      KALDI_ERR << "--proxy-beam must either be -1 or non-negative.";
      exit(1);
    }

    if (po.NumArgs() < 4 || po.NumArgs() > 5) {
      po.PrintUsage();
      exit(1);
    }

    std::string L2xE_filename = po.GetArg(1),
        L1_filename = po.GetArg(2),
        keyword_rspecifier = po.GetArg(3),
        proxy_wspecifier = po.GetArg(4),
        kwlist_wspecifier = (po.NumArgs() >= 5) ? po.GetArg(5) : "";

    L2xE = ReadFstKaldi(L2xE_filename);
    L1 = ReadFstKaldi(L1_filename);

    KALDI_VLOG(1) << "L2xE: " << L2xE->NumStates() << " states, " << NumArcs(*L2xE) << " arcs.";
    KALDI_VLOG(1) << "L1: " << L1->NumStates() << " states, " << NumArcs(*L1) << " arcs.";

    if (!additional_fst_filename.empty()) {
      additional_fst = ReadFstKaldi(additional_fst_filename);
      KALDI_VLOG(1) << "G': " << additional_fst->NumStates() << " states, " << NumArcs(*additional_fst) << " arcs.";
    } else {
      additional_fst = NULL;
    }

    SequentialInt32VectorReader keyword_reader(keyword_rspecifier);
    TableWriter<VectorFstHolder> proxy_writer(proxy_wspecifier);
    TableWriter<BasicVectorHolder<double> > kwlist_writer(kwlist_wspecifier);
    p_proxy_writer = &proxy_writer;
    p_kwlist_writer = &kwlist_writer;

    RandomAccessTableReader<VectorFstHolder> prior_reader(prior_rspecifier);
    // check if prior_rspecifier is set or not
    if (!prior_rspecifier.empty()) {
      p_prior_reader = &prior_reader;
    } else {
      p_prior_reader = NULL;
    }

    // Processing the keywords.
    int32 n_done = 0;
    for (; !keyword_reader.Done(); keyword_reader.Next()) {
      JobPara jobpara;
      jobpara.p_po = &po;
      jobpara.max_states = max_states;
      jobpara.phone_beam = phone_beam;
      jobpara.phone_nbest = phone_nbest;
      jobpara.proxy_beam = proxy_beam;
      jobpara.proxy_nbest = proxy_nbest;
      jobpara.proxy_nbest0 = proxy_nbest0;
      jobpara.key = keyword_reader.Key();
      jobpara.keyword = keyword_reader.Value();
      jobpara.additional_fst = additional_fst;
      keyword_reader.FreeCurrent();


      KALDI_LOG << "Processing " << jobpara.key;
      // DO NOT REMOVE the following calling to Haskey
      if (p_prior_reader && p_prior_reader->HasKey(jobpara.key)) { // this line ensures that prior_reader would not be deconstructed after 1st keyword is processed
        KALDI_VLOG(1) << "Prior FST of Key " << jobpara.key << " exists.";
      }

      do {
        pid_t pid = fork();
        if (pid < 0) {
          KALDI_ERR << "[E] Error in fork";
          return -1;
        }
        if (pid == 0) { // child process
          funProcessJob(&jobpara);
          return 0;
        } else { // master process
          jpid = pid;
          int status;
          waitpid(pid, &status, 0);
          if (status == 2) {
            KALDI_VLOG(1) << "[E] Out of memory when processing " << jobpara.key << ", killed.";
            if (--jobpara.proxy_beam > 2) {
              KALDI_VLOG(1) << "[I] Try setting proxy_beam to " << jobpara.proxy_beam;
              continue;
            } else {
              KALDI_VLOG(1) << "[I] Skip expanding " << jobpara.key;
              break;
            }
          } else if (status == 1) {
            KALDI_VLOG(1) << "[E] Exception caught when processing " << jobpara.key << ", skip expanding.";
            break;
          } else {
            n_done++;
            break;
          }
        }
      } while (1);
    }

    delete L1;
    delete L2xE;
    if (additional_fst) {
      delete additional_fst;
    }
    KALDI_LOG << "Done " << n_done << " keywords";
    //return (n_done != 0 ? 0 : 1);    
    return 0;    // always return 0 (chenzp Mar 20,2014)
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
