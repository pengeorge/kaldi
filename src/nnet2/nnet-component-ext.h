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
#include "nnet2/nnet-component-ext.h"

#include <iostream>

namespace kaldi {
namespace nnet2 {

/*
class WithConstComponent {
 public:
   WithConstComponent(int32 const_dim = 0):const_dim_(const_dim) { };
  virtual void ResetConst(int32 const_dim = 0) {const_dim_ = const_dim; };
 protected:
  int32 const_dim_;
};*/

class VectorMixComponent: public UpdatableComponent {
 public:
  virtual int32 InputDim() const { return block_dim_ * num_blocks_ + const_dim_; }
  virtual int32 OutputDim() const { return block_dim_ + const_dim_; }
  virtual int32 GetParameterDim() const;
  virtual void Vectorize(VectorBase<BaseFloat> *params) const;
  virtual void UnVectorize(const VectorBase<BaseFloat> &params);

  // Note: num_blocks must divide input_dim.
  void Init(BaseFloat learning_rate, int32 block_dim,
                    BaseFloat param_stddev, BaseFloat bias_stddev,
                    int32 num_blocks, int32 const_dim = 0);
  virtual void InitFromString(std::string args);
  
  VectorMixComponent() { } // use Init to really initialize.
  virtual void ResetConst(int32 const_dim = 0) {const_dim_ = const_dim; };
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
  virtual std::string Info() const;
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
  int32 const_dim_;
 private:
  KALDI_DISALLOW_COPY_AND_ASSIGN(VectorMixComponent);

};

class AffineComponentExt: public AffineComponent {
 public:
  explicit AffineComponentExt(const AffineComponentExt &other);
  explicit AffineComponentExt(const AffineComponent &base, int32 const_dim = 0);
  explicit AffineComponentExt(const AffineComponentPreconditioned &base, int32 const_dim = 0);
  // The next constructor is used in converting from nnet1.
  AffineComponentExt(const CuMatrixBase<BaseFloat> &linear_params,
                  const CuVectorBase<BaseFloat> &bias_params,
                  BaseFloat learning_rate, int32 const_dim = 0);
  virtual int32 InputDim() const { return linear_params_.NumCols() + const_dim_; }
  virtual int32 OutputDim() const { return linear_params_.NumRows() + const_dim_; }
  virtual void ResetConst(int32 const_dim = 0) {const_dim_ = const_dim; };
  void Init(BaseFloat learning_rate,
            int32 input_dim, int32 output_dim,
            BaseFloat param_stddev, BaseFloat bias_stddev, int32 const_dim = 0);
  void Init(BaseFloat learning_rate,
            std::string matrix_filename);

  virtual std::string Info() const;
  virtual void InitFromString(std::string args);
  
  AffineComponentExt() { } // use Init to really initialize.
  virtual std::string Type() const { return "AffineComponentExt"; }
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
  virtual void Read(std::istream &is, bool binary);
  virtual void Write(std::ostream &os, bool binary) const;
  virtual Component* Copy() const;
  virtual void SetParams(const VectorBase<BaseFloat> &bias,
                         const MatrixBase<BaseFloat> &linear,
                         int32 const_dim = 0);

  virtual int32 GetParameterDim() const;
  virtual void Vectorize(VectorBase<BaseFloat> *params) const;
  virtual void UnVectorize(const VectorBase<BaseFloat> &params);

 protected:
  // This function Update() is for extensibility; child classes may override this.
  virtual void Update(
      const CuMatrixBase<BaseFloat> &in_value,
      const CuMatrixBase<BaseFloat> &out_deriv) {
    UpdateSimple(in_value, out_deriv);
  }
  // UpdateSimple is used when *this is a gradient.  Child classes may
  // or may not override this.
  virtual void UpdateSimple(
      const CuMatrixBase<BaseFloat> &in_value,
      const CuMatrixBase<BaseFloat> &out_deriv);  

  const AffineComponentExt &operator = (const AffineComponentExt &other); // Disallow.
  int32 const_dim_;
};

/// FixedAffineComponentExt is an affine transform that is supplied
/// at network initialization time and is not trainable.
class FixedAffineComponentExt: public FixedAffineComponent {
 public:
  FixedAffineComponentExt() { } 
  virtual void ResetConst(int32 const_dim = 0) {const_dim_ = const_dim; };
  virtual std::string Type() const { return "FixedAffineComponentExt"; }
  virtual std::string Info() const;

  /// matrix should be of size input-dim+1 to output-dim, last col is offset
  void Init(const CuMatrixBase<BaseFloat> &matrix, int32 const_dim = 0); 

  // InitFromString takes only the option matrix=<string>,
  // where the string is the filename of a Kaldi-format matrix to read.
  virtual void InitFromString(std::string args);
  
  virtual int32 InputDim() const { return linear_params_.NumCols() + const_dim_; }
  virtual int32 OutputDim() const { return linear_params_.NumRows() + const_dim_; }
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
  virtual bool BackpropNeedsInput() const { return false; }
  virtual bool BackpropNeedsOutput() const { return false; }
  virtual Component* Copy() const;
  virtual void Read(std::istream &is, bool binary);
  virtual void Write(std::ostream &os, bool binary) const;

  // Function to provide access to linear_params_.
  const CuMatrix<BaseFloat> &LinearParams() const { return linear_params_; }
 protected:
  friend class AffineComponentExt;
  CuMatrix<BaseFloat> linear_params_;
  CuVector<BaseFloat> bias_params_;
  int32 const_dim_;
  
  KALDI_DISALLOW_COPY_AND_ASSIGN(FixedAffineComponentExt);
};


class TanhComponentExt: public TanhComponent {
 public:
  TanhComponentExt(int32 dim, int32 const_dim): TanhComponent(dim), const_dim_(const_dim) { }
  TanhComponentExt(const TanhComponentExt &other): TanhComponent(other), const_dim_(other.const_dim_) { }
  TanhComponentExt(const TanhComponent &other, int32 const_dim = 0) {
    Init(other.InputDim() + const_dim, const_dim);
  }
  TanhComponentExt() { }
  virtual void ResetConst(int32 const_dim = 0) {dim_ += const_dim - const_dim_; const_dim_ = const_dim; };
  virtual std::string Type() const { return "TanhComponentExt"; }
  void Init(int32 dim, int32 const_dim) { dim_ = dim; const_dim_ = const_dim, count_ = 0.0; }
  virtual void InitFromString(std::string args); 
  virtual Component* Copy() const { return new TanhComponentExt(*this); }
  virtual bool BackpropNeedsInput() const { return false; }
  virtual bool BackpropNeedsOutput() const { return true; }
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
  virtual void Read(std::istream &is, bool binary); // This Read function
  // requires that the Component has the correct type.
  
  /// Write component to stream
  virtual void Write(std::ostream &os, bool binary) const;
  virtual std::string Info() const;
  virtual void UpdateStats(const CuMatrixBase<BaseFloat> &out_value,
                   const CuMatrixBase<BaseFloat> *deriv);
 protected:
  int32 const_dim_;
 private:
  TanhComponentExt &operator = (const TanhComponentExt &other); // Disallow.
};


class PnormComponentExt: public PnormComponent {
 public:
  void Init(int32 input_dim, int32 output_dim, BaseFloat p, int32 const_dim = 0);
  explicit PnormComponentExt(int32 input_dim, int32 output_dim, BaseFloat p, int32 const_dim = 0) {
    Init(input_dim, output_dim, p, const_dim);
  }
  PnormComponentExt(): input_dim_(0), output_dim_(0), p_(0), const_dim_(0) { }
  PnormComponentExt(const PnormComponentExt &other)
    : input_dim_(other.input_dim_), output_dim_(other.output_dim_),
      p_(other.p_), const_dim_(other.const_dim_) { }
  //TODO how to copy "p" from PnormComponent without modifying class PnormComponent
  PnormComponentExt(const PnormComponent &other, int32 const_dim = 0) {
    Init(other.InputDim(), other.OutputDim(), 2, const_dim);
  }
//    : input_dim_(other.InputDim()), output_dim_(other.OutputDim()),
//      p_(2), const_dim_(const_dim) { }
  virtual void ResetConst(int32 const_dim = 0) {const_dim_ = const_dim; };
  virtual std::string Type() const { return "PnormComponentExt"; }
  virtual void InitFromString(std::string args); 
  virtual int32 InputDim() const { return input_dim_ + const_dim_; }
  virtual int32 OutputDim() const { return output_dim_ + const_dim_; }
  using Component::Propagate; // to avoid name hiding
  virtual void Propagate(const ChunkInfo &in_info,
                         const ChunkInfo &out_info,
                         const CuMatrixBase<BaseFloat> &in,
                         CuMatrixBase<BaseFloat> *out) const; 
  virtual void Backprop(const ChunkInfo &in_info,
                        const ChunkInfo &out_info,
                        const CuMatrixBase<BaseFloat> &in_value,
                        const CuMatrixBase<BaseFloat> &,  //out_value,                        
                        const CuMatrixBase<BaseFloat> &out_deriv,
                        Component *to_update, // may be identical to "this".
                        CuMatrix<BaseFloat> *in_deriv) const;
  virtual bool BackpropNeedsInput() const { return true; }
  virtual bool BackpropNeedsOutput() const { return true; }
  virtual Component* Copy() const { return new PnormComponentExt(input_dim_,
                                                              output_dim_, p_, const_dim_); }
  
  virtual void Read(std::istream &is, bool binary); // This Read function
  // requires that the Component has the correct type.
  
  /// Write component to stream
  virtual void Write(std::ostream &os, bool binary) const;

  virtual std::string Info() const;
 protected:
  int32 input_dim_;
  int32 output_dim_;
  BaseFloat p_;
  int32 const_dim_;
};

class NormalizeComponentExt: public NormalizeComponent {
 public:
  NormalizeComponentExt(int32 dim, int32 const_dim): NormalizeComponent(dim), const_dim_(const_dim) { }
  NormalizeComponentExt(const NormalizeComponentExt &other)
    : NormalizeComponent(other), const_dim_(other.const_dim_) { }
  NormalizeComponentExt(const NormalizeComponent &other, int32 const_dim = 0) {
    Init(other.InputDim() + const_dim, const_dim);
  }
  NormalizeComponentExt() : NormalizeComponent(), const_dim_(0) { }
  virtual void ResetConst(int32 const_dim = 0) {dim_ += const_dim - const_dim_; const_dim_ = const_dim; };
  virtual std::string Type() const { return "NormalizeComponentExt"; }
  void Init(int32 dim, int32 const_dim) { dim_ = dim; const_dim_ = const_dim; }
  virtual void InitFromString(std::string args); 
  virtual Component* Copy() const { return new NormalizeComponentExt(*this); }
  virtual bool BackpropNeedsInput() const { return true; }
  virtual bool BackpropNeedsOutput() const { return true; }
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
  virtual void Read(std::istream &is, bool binary); // This Read function
  // requires that the Component has the correct type.
  
  /// Write component to stream
  virtual void Write(std::ostream &os, bool binary) const;
  virtual std::string Info() const;
 protected:
  int32 const_dim_;
 private:
  NormalizeComponentExt &operator = (const NormalizeComponentExt &other); // Disallow.
  static const BaseFloat kNormFloor;
  // about 0.7e-20.  We need a value that's exactly representable in
  // float and whose inverse square root is also exactly representable
  // in float (hence, an even power of two).
};

} // namespace nnet2
} // namespace kaldi

#endif
