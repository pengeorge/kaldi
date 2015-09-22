// transform/lda-estimate.h

// Copyright 2009-2011  Jan Silovsky
//           2015       Zhipeng Chen

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

#ifndef KALDI_TRANSFORM_LDA_ESTIMATE_EXT_H_
#define KALDI_TRANSFORM_LDA_ESTIMATE_EXT_H_

#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "matrix/matrix-lib.h"
#include "transform/lda-estimate.h"

namespace kaldi {

/** Extended Class for computing linear discriminant analysis (LDA) transform.
    C.f. \ref transform_lda.
 */
class LdaEstimateExt : public LdaEstimate {
 public:
  LdaEstimateExt() {}

  /// Accumulates sufficient statistics
  void AccumulateSS(const LdaEstimateExt &src, int32 src_class_id, int32 tgt_class_id);

};

}  // End namespace kaldi

#endif  // KALDI_TRANSFORM_LDA_ESTIMATE_EXT_H_

