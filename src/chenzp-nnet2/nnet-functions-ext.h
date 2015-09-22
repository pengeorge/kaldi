// nnet2/nnet-functions.h

// Copyright  2012  Johns Hopkins University (author: Daniel Povey)

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

#ifndef KALDI_CHENZP_NNET2_NNET_FUNCTIONS_H_
#define KALDI_CHENZP_NNET2_NNET_FUNCTIONS_H_

#include "base/kaldi-common.h"
#include "util/kaldi-io.h"
#include "matrix/matrix-lib.h"
#include "nnet2/nnet-component.h"
#include "nnet2/nnet-component-ext.h"
#include "nnet2/nnet-nnet.h"

#include <iostream>
#include <sstream>
#include <vector>


namespace kaldi {
namespace nnet2 {


void InsertComponentsAndResize(const Nnet &src_nnet, int32 c_to_insert, Nnet *dest_nnet);
/**
 */
void ExtendComponents(int32 num_to_extend, Nnet *dest_nnet, int32 const_dim);


} // namespace nnet2
} // namespace kaldi

#endif


