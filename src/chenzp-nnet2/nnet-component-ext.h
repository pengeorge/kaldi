// nnet2/nnet-component.h

// Copyright 2011-2013  Karel Vesely
//           2012-2014  Johns Hopkins University (author: Daniel Povey)
//                2013  Xiaohui Zhang    
//                2014  Vijayaditya Peddinti
//           2014-2015  Guoguo Chen

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

#ifndef KALDI_NNET2_NNET_COMPONENT_EXT_H_
#define KALDI_NNET2_NNET_COMPONENT_EXT_H_

#include "base/kaldi-common.h"
#include "itf/options-itf.h"
#include "matrix/matrix-lib.h"
#include "cudamatrix/cu-matrix-lib.h"
#include "thread/kaldi-mutex.h"
#include "nnet2/nnet-precondition-online.h"
#include "nnet2/nnet-component.h"

#include <iostream>

namespace kaldi {
namespace nnet2 {

class VectorMixComponent: public UpdatableComponent {
 public:
  virtual int32 InputDim() const { return block_dim_ * num_blocks_ + const_component_dim_; }
  virtual int32 OutputDim() const { return block_dim_ + const_component_dim_; }
  virtual int32 GetParameterDim() const;
  virtual void Vectorize(VectorBase<BaseFloat> *params) const;
  virtual void UnVectorize(const VectorBase<BaseFloat> &params);

  // Note: num_blocks must divide input_dim.
  void Init(BaseFloat learning_rate, int32 block_dim,
                    BaseFloat param_stddev, BaseFloat bias_stddev,
                    int32 num_blocks, int32 const_component_dim = 0);
  virtual void InitFromString(std::string args);
  
  VectorMixComponent() { } // use Init to really initialize.
  virtual std::string Type() const { return "VectorMixComponent"; }
  virtual bool BackpropNeedsInput() const { return true; }
  virtual bool BackpropNeedsOutput() const { return false; }
  using Component::Propagate; // to avoid name hiding
  virtual void Propagate(const ChunkInfo &in_info,
                         const ChunkInfo &out_info,
                         const CuMatrixBase<BaseFloat> &in,
                         CuMatrixBase<BaseFloat> *out) const; 
  virtual void Backprop(const ChunkInfo &in_info,
                        const ChunkInfo &out_info,
                        const CuMatrixBase<BaseFloat> &in_value,
                        const CuMatrixBase<BaseFloat> &out_value,                        
                        const CuMatrixBase<BaseFloat> &out_deriv,
                        Component *to_update, // may be identical to "this".
                        CuMatrix<BaseFloat> *in_deriv) const;
  virtual void SetZero(bool treat_as_gradient);
  virtual void Read(std::istream &is, bool binary);
  virtual void Write(std::ostream &os, bool binary) const;
  virtual BaseFloat DotProduct(const UpdatableComponent &other) const;
  virtual Component* Copy() const;
  virtual void PerturbParams(BaseFloat stddev);
  virtual void Scale(BaseFloat scale);
  virtual void Add(BaseFloat alpha, const UpdatableComponent &other);
 protected:
  virtual void Update(
      const CuMatrixBase<BaseFloat> &in_value,
      const CuMatrixBase<BaseFloat> &out_deriv) {
    UpdateSimple(in_value, out_deriv);
  }
  // UpdateSimple is used when *this is a gradient.  Child classes may
  // override this.
  virtual void UpdateSimple(
      const CuMatrixBase<BaseFloat> &in_value,
      const CuMatrixBase<BaseFloat> &out_deriv);
  
  CuMatrix<BaseFloat> linear_params_;
  CuVector<BaseFloat> bias_params_;
  int32 num_blocks_;
  int32 block_dim_;
  int32 const_component_dim_;
 private:
  KALDI_DISALLOW_COPY_AND_ASSIGN(VectorMixComponent);

};


} // namespace nnet2
} // namespace kaldi

#endif
