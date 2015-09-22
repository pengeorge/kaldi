// transform/lda-estimate.cc

// Copyright 2009-2011  Jan Silovsky
//                2013  Johns Hopkins University
//                2015  Zhipeng Chen

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


#include "chenzp-transform/lda-estimate-ext.h"

namespace kaldi {

void LdaEstimateExt::AccumulateSS(const LdaEstimateExt &srcLDA, int32 src_class_id, int32 tgt_class_id) {
  KALDI_ASSERT(src_class_id >= 0 && tgt_class_id >= 0);
  KALDI_ASSERT(src_class_id < srcLDA.NumClasses());
  KALDI_ASSERT(tgt_class_id < NumClasses());
  KALDI_ASSERT(srcLDA.Dim() == Dim());

  zero_acc_(tgt_class_id) += srcLDA.zero_acc_(src_class_id);
  first_acc_.Row(tgt_class_id).AddVec(1.0, srcLDA.first_acc_.Row(src_class_id));
  total_second_acc_.AddSp(1.0, srcLDA.total_second_acc_);
}

}  // End of namespace kaldi
