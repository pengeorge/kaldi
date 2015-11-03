// chenzp-fstext/rescale-dag.h

// Copyright 2009-2011  Microsoft Corporation

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

#ifndef KALDI_FSTEXT_RESCALE_DAG_H_
#define KALDI_FSTEXT_RESCALE_DAG_H_
#include <algorithm>
#include <map>
#include <set>
#include <vector>
#include <fst/fstlib.h>
#include <fst/fst-decl.h>


namespace fst {

/// isDag checks if an FST is a directed acylic graph
template<class Arc>
bool IsDAG(ExpandedFst<Arc> &fst);

/// ComputeTotalWeight computes the total weight of the FST,
/// i.e. the sum of all paths.  It will only work for arcs of StdArc/LogArc type

template<class Arc>
inline typename Arc::Weight
ComputeDagTotalWeight(ExpandedFst<Arc> &fst);


/// Rescale multiplies (in the semiring) all weights and final probabilities in
/// the FST by this weight.
template<class Arc>
inline void RescaleDag(MutableFst<Arc> *fst, typename Arc::Weight rescale);


/// RescaleToStochastic uses a form of line search to compute the weight we must
/// apply to the FST using Rescale to make it so that the "total weight" of the
/// FST is unity, and applies this weight.  The projected use-case is that
/// you want to do push-weights but you're scared this might blow up, so you
/// do RescaleToStochastic, push-weights, and then Rescale with the inverse
/// (in the semiring) of that weight, so that you are equivalent to the
/// original FST and the "non-stochasticity" is distributed equally among
/// all states.
template<class Arc> // StdArc or LogArc
inline typename Arc::Weight RescaleDagToStochastic(MutableFst<Arc> *fst);

} // end namespace fst

#include "chenzp-fstext/rescale-dag-inl.h"

#endif
