// chenzp-fstext/rescale-dag-inl.h

// Copyright 2009-2011  Microsoft Corporation;  Jan Silovsky

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

#ifndef KALDI_FSTEXT_RESCALE_DAG_INL_H_
#define KALDI_FSTEXT_RESCALE_DAG_INL_H_
#include <cstring>
#include "base/kaldi-common.h"
#include "util/stl-utils.h"
#include "fstext/fstext-utils.h"
#include "chenzp-fstext/rescale-dag.h"

namespace fst {

// Only support DAG with a single initial state.
template<class Arc>
bool IsDAG(ExpandedFst<Arc> &fst) {
  typedef typename Arc::StateId StateId;
  typedef typename Arc::Weight Weight;
  if (fst.Start() == kNoStateId) return true;
  StateId num_states = fst.NumStates();

  // Should probably use Weight instead of float here, but would
  // involve some painful comparators.
  vector<int32> cur_num_in_arcs(num_states, 0);
  vector<bool> queued(num_states, false);

  // Calculate the incoming degree for each state
  for (StateIterator<Fst<Arc> > siter(fst); !siter.Done(); siter.Next()) {
    const StateId &s = siter.Value();
    for (ArcIterator<Fst<Arc> > aiter(fst, s); !aiter.Done(); aiter.Next()) {
      const Arc &arc = aiter.Value();
      cur_num_in_arcs[arc.nextstate]++;
    }
  }

  std::queue<StateId> q;  // FIFO queue.

  {
    StateId is = fst.Start();
    if (cur_num_in_arcs[is] != 0)
      return false;
    q.push(is);
    queued[is] = true;
  }

  while (!q.empty()) {
    StateId s = q.front();
    q.pop();

    for (ArcIterator<Fst<Arc> > aiter(fst, s); !aiter.Done(); aiter.Next()) {
      const Arc &arc = aiter.Value();
      cur_num_in_arcs[arc.nextstate]--;
      if (cur_num_in_arcs[arc.nextstate] == 0 && !queued[arc.nextstate]) {
        q.push(arc.nextstate);
        queued[arc.nextstate] = true;
      }
    }
  }
  for (StateIterator<Fst<Arc> > siter(fst); !siter.Done(); siter.Next()) {
    const StateId &s = siter.Value();
    if (!queued[s]) {
      return false;
    }
  }
  return true;
}

// Only support DAG with a single initial state.
template<class Arc>
inline typename Arc::Weight
ComputeDagTotalWeight(ExpandedFst<Arc> &fst) {
  typedef typename Arc::StateId StateId;
  typedef typename Arc::Weight Weight;
  if (fst.Start() == kNoStateId) return Weight::Zero();
  StateId num_states = fst.NumStates();

  float zero = Weight::Zero().Value();

  // Should probably use Weight instead of float here, but would
  // involve some painful comparators.
  vector<float> cur_tot(num_states, zero);
  vector<int32> cur_num_in_arcs(num_states, 0);
  vector<bool> queued(num_states, false);

  // Calculate the incoming degree for each state
  for (StateIterator<Fst<Arc> > siter(fst); !siter.Done(); siter.Next()) {
    const StateId &s = siter.Value();
    for (ArcIterator<Fst<Arc> > aiter(fst, s); !aiter.Done(); aiter.Next()) {
      const Arc &arc = aiter.Value();
      cur_num_in_arcs[arc.nextstate]++;
    }
  }

  std::queue<StateId> q;  // FIFO queue.

  Weight total_final = Weight::Zero();
  {
    StateId is = fst.Start();
    float one = static_cast<float>(Weight::One().Value());
    if (cur_num_in_arcs[is] != 0)
      KALDI_ERR << "ComputeDagTotalWeight failed: not a DAG, initial state has input arcs";
    cur_tot[is] = one;
    q.push(is);
    queued[is] = true;
  }

  while (!q.empty()) {
    StateId s = q.front();
    q.pop();
    Weight w = Weight(cur_tot[s]);

    Weight final = fst.Final(s);
    if (final != Weight::Zero()) {
      total_final = Plus(total_final, Times(w, final));
    }
    for (ArcIterator<Fst<Arc> > aiter(fst, s); !aiter.Done(); aiter.Next()) {
      const Arc &arc = aiter.Value();
      Weight next_weight = Times(w, arc.weight);
      cur_tot[arc.nextstate] = Plus(Weight(cur_tot[arc.nextstate]), next_weight).Value();
      cur_num_in_arcs[arc.nextstate]--;
      if (cur_num_in_arcs[arc.nextstate] == 0 && !queued[arc.nextstate]) {
        q.push(arc.nextstate);
        queued[arc.nextstate] = true;
      }
    }
  }
  for (StateIterator<Fst<Arc> > siter(fst); !siter.Done(); siter.Next()) {
    const StateId &s = siter.Value();
    if (!queued[s]) {
      KALDI_ERR << "[WARNING] ComputeDagTotalWeight failed: not a DAG";
      break;
    }
  }
  return total_final;
}


  
template<class Arc>
inline void RescaleDag(MutableFst<Arc> *fst, typename Arc::Weight rescale) {
  typedef typename Arc::StateId StateId;
  // Multiplies all final-probs in the FST by this rescaling amount.
  for (StateIterator<MutableFst<Arc> > siter(*fst); !siter.Done(); siter.Next()) {
    StateId s = siter.Value();
    fst->SetFinal(s, Times(rescale, fst->Final(s)));
  }
}

template<class Arc> // StdArc or LogArc
inline typename Arc::Weight RescaleDagToStochastic(MutableFst<Arc> *fst) {
  // Rescales the FST until it sums to one (within its own semiring).
  // Returns the amount it rescaled by.  Must be of the
  // LogArc or StdArc type.
  typedef typename Arc::Weight Weight;

  if (fst->Start() == kNoStateId)
    return Weight::One();  // can't rescale empty FST.

  Weight cur_tot = ComputeDagTotalWeight(*fst);
  Weight factor = Weight(-cur_tot.Value());
  RescaleDag(fst, factor);
  return factor;
}


} // namespace fst.

#endif
