// Copyright 2011-2012  Karel Vesely
//           2013-2014  Johns Hopkins University (author: Daniel Povey)
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

#include <iterator>
#include <sstream>
#include "nnet2/nnet-component.h"
#include "nnet2/nnet-component-ext.h"
#include "nnet2/nnet-precondition.h"
#include "nnet2/nnet-precondition-online.h"
#include "util/stl-utils.h"
#include "util/text-utils.h"
#include "util/kaldi-io.h"

namespace kaldi {
namespace nnet2 {

// This is like ExpectToken but for two tokens, and it
// will either accept token1 and then token2, or just token2.
// This is useful in Read functions where the first token
// may already have been consumed.
// (the same as the one in nnet2/nnet-component.cc)
static void ExpectOneOrTwoTokens(std::istream &is, bool binary,
                                 const std::string &token1,
                                 const std::string &token2) {
  KALDI_ASSERT(token1 != token2);
  std::string temp;
  ReadToken(is, binary, &temp);
  if (temp == token1) {
    ExpectToken(is, binary, token2);
  } else {
    if (temp != token2) {
      KALDI_ERR << "Expecting token " << token1 << " or " << token2
                << " but got " << temp;
    }
  }
}

bool ParseFromString(const std::string &name, std::string *string, int32 *param);
bool ParseFromString(const std::string &name, std::string *string, bool *param);
bool ParseFromString(const std::string &name, std::string *string, BaseFloat *param);
bool ParseFromString(const std::string &name, std::string *string, std::string *param);
bool ParseFromString(const std::string &name, std::string *string, std::vector<int32> *param);

void VectorMixComponent::SetZero(bool treat_as_gradient) {
  if (treat_as_gradient) {
    SetLearningRate(1.0);
  }
  linear_params_.SetZero();
  bias_params_.SetZero();
}

void VectorMixComponent::PerturbParams(BaseFloat stddev) {
  CuMatrix<BaseFloat> temp_linear_params(linear_params_);
  temp_linear_params.SetRandn();
  linear_params_.AddMat(stddev, temp_linear_params);

  CuVector<BaseFloat> temp_bias_params(bias_params_);
  temp_bias_params.SetRandn();
  bias_params_.AddVec(stddev, temp_bias_params);
}

BaseFloat VectorMixComponent::DotProduct(
    const UpdatableComponent &other_in) const {
  const VectorMixComponent *other =
      dynamic_cast<const VectorMixComponent*>(&other_in);
  return TraceMatMat(linear_params_, other->linear_params_, kTrans)
      + VecVec(bias_params_, other->bias_params_);
}

Component* VectorMixComponent::Copy() const {
  VectorMixComponent *ans = new VectorMixComponent();
  ans->learning_rate_ = learning_rate_;
  ans->linear_params_ = linear_params_;
  ans->bias_params_ = bias_params_;
  ans->num_blocks_ = num_blocks_;
  ans->block_dim_ = block_dim_;
  ans->const_component_dim_ = const_component_dim_;
  return ans;
}

void VectorMixComponent::Scale(BaseFloat scale) {
  linear_params_.Scale(scale);
  bias_params_.Scale(scale);
}

void VectorMixComponent::Add(BaseFloat alpha,
                               const UpdatableComponent &other_in) {
  const VectorMixComponent *other =
      dynamic_cast<const VectorMixComponent*>(&other_in);
  KALDI_ASSERT(other != NULL);
  linear_params_.AddMat(alpha, other->linear_params_);
  bias_params_.AddVec(alpha, other->bias_params_);
}

void VectorMixComponent::Propagate(const ChunkInfo &in_info,
                                   const ChunkInfo &out_info,
                                   const CuMatrixBase<BaseFloat> &in,
                                   CuMatrixBase<BaseFloat> *out) const  {
  in_info.CheckSize(in);
  out_info.CheckSize(*out);
  KALDI_ASSERT(in_info.NumChunks() == out_info.NumChunks());

  int32 num_frames = in.NumRows();
  KALDI_ASSERT(in.NumCols() == block_dim_ * num_blocks_ + const_component_dim_);
  KALDI_ASSERT(out->NumCols() == block_dim_ + const_component_dim_);
  KALDI_ASSERT(in.NumRows() == out->NumRows());

  if (const_component_dim_ > 0) {
    CuSubMatrix<BaseFloat> const_in(in, 0, num_frames, block_dim_ * num_blocks_, const_component_dim_);
    CuSubMatrix<BaseFloat> const_out(*out, 0, num_frames, block_dim_, const_component_dim_);
    const_out.CopyFromMat(const_in);
  }
  CuSubMatrix<BaseFloat> mix_out(*out, 0, num_frames, 0, block_dim_);
  mix_out.CopyRowsFromVec(bias_params_); // copies bias_params_ to each row of *mix_out.

  for (int32 b = 0; b < num_blocks_; b++) {
    CuSubMatrix<BaseFloat> in_block(in, 0, num_frames, b * block_dim_, block_dim_);
    CuSubVector<BaseFloat> param_vector = linear_params_.Row(b);
    CuMatrix<BaseFloat>    this_out(in_block);
    this_out.MulColsVec(param_vector);
    mix_out.AddMat(1.0, this_out);
  }
}

void VectorMixComponent::UpdateSimple(
    const CuMatrixBase<BaseFloat> &in_value,
    const CuMatrixBase<BaseFloat> &out_deriv) {
  CuSubMatrix<BaseFloat> out_deriv_for_update(out_deriv, 0, out_deriv.NumRows(), 0, block_dim_);
  bias_params_.AddRowSumMat(learning_rate_, out_deriv_for_update, 1.0);
  CuMatrix<BaseFloat> update_mat(out_deriv.NumCols(), in_value.NumCols());
  update_mat.AddMatMat(1.0, out_deriv, kTrans,
                           in_value, kNoTrans, 1.0); // without learning_rate_

  CuMatrix<BaseFloat> update_param(num_blocks_, block_dim_);
  for (int32 b = 0; b < num_blocks_; b++) {
    CuSubMatrix<BaseFloat> update_block(update_mat, 0, block_dim_,
                                        b * block_dim_, block_dim_);
    CuMatrix<BaseFloat> update_block_copy(update_block);
    CuSubVector<BaseFloat> update_param_block(update_param, b);
    update_param_block.CopyDiagFromMat(update_block_copy);
  }
  // Update the parameters.
  linear_params_.AddMat(learning_rate_, update_param);
}

void VectorMixComponent::Backprop(const ChunkInfo &,  //in_info,
                                    const ChunkInfo &,  //out_info,
                                    const CuMatrixBase<BaseFloat> &in_value,
                                    const CuMatrixBase<BaseFloat> &,  //out_value,
                                    const CuMatrixBase<BaseFloat> &out_deriv,
                                    Component *to_update_in,
                                    CuMatrix<BaseFloat> *in_deriv) const  {

  // This code mirrors the code in Propagate().
  int32 num_frames = in_value.NumRows();
  VectorMixComponent *to_update = dynamic_cast<VectorMixComponent*>(
      to_update_in);
  in_deriv->Resize(out_deriv.NumRows(), InputDim());
  KALDI_ASSERT(in_value.NumCols() == block_dim_ * num_blocks_ + const_component_dim_);
  KALDI_ASSERT(out_deriv.NumCols() == block_dim_ + const_component_dim_);

  if (const_component_dim_ > 0) {
    CuSubMatrix<BaseFloat> const_out_deriv(out_deriv, 0, num_frames, block_dim_, const_component_dim_);
    CuSubMatrix<BaseFloat> const_in_deriv(*in_deriv, 0, num_frames, block_dim_ * num_blocks_, const_component_dim_);
    const_in_deriv.CopyFromMat(const_out_deriv);
  }

  for (int32 b = 0; b < num_blocks_; b++) {
    CuSubMatrix<BaseFloat> out_deriv_block(out_deriv, 0, num_frames, 0, block_dim_);
    CuSubMatrix<BaseFloat> in_value_block(in_value, 0, num_frames, b * block_dim_, block_dim_);
    CuSubMatrix<BaseFloat> in_deriv_block(*in_deriv, 0, num_frames, b * block_dim_, block_dim_);
    CuSubVector<BaseFloat> param_vector = linear_params_.Row(b);
    in_deriv_block.CopyFromMat(out_deriv_block);
    in_deriv_block.MulColsVec(param_vector);
  }

  if (to_update != NULL)
    to_update->Update(in_value, out_deriv);
}


void VectorMixComponent::Init(BaseFloat learning_rate,
                                int32 block_dim,
                                BaseFloat param_stddev,
                                BaseFloat bias_stddev,
                                int32 num_blocks,
                                int32 const_component_dim) {
  UpdatableComponent::Init(learning_rate);
  KALDI_ASSERT(block_dim > 0 && param_stddev >= 0.0);

  linear_params_.Resize(num_blocks, block_dim);
  bias_params_.Resize(block_dim);

  linear_params_.SetRandn(); // sets to random normally distributed noise.
  linear_params_.Scale(param_stddev);
  bias_params_.SetRandn();
  bias_params_.Scale(bias_stddev);
  block_dim_ = block_dim;
  num_blocks_ = num_blocks;
  const_component_dim_ = const_component_dim;
}

void VectorMixComponent::InitFromString(std::string args) {
  std::string orig_args(args);
  bool ok = true;
  BaseFloat learning_rate = learning_rate_;
  int32 block_dim = -1, num_blocks = 1, const_component_dim = 0;
  ParseFromString("learning-rate", &args, &learning_rate); // optional.
  ok = ok && ParseFromString("block-dim", &args, &block_dim);
  ok = ok && ParseFromString("num-blocks", &args, &num_blocks);
  ok = ok && ParseFromString("const-component-dim", &args, &const_component_dim);
  BaseFloat param_stddev = 1.0 / std::sqrt(block_dim * num_blocks),
      bias_stddev = 1.0; // TODO should param_stddev be greater ?
  ParseFromString("param-stddev", &args, &param_stddev);
  ParseFromString("bias-stddev", &args, &bias_stddev);
  if (!args.empty())
    KALDI_ERR << "Could not process these elements in initializer: "
              << args;
  if (!ok)
    KALDI_ERR << "Bad initializer " << orig_args;
  Init(learning_rate, block_dim, param_stddev, bias_stddev, num_blocks, const_component_dim);
}


void VectorMixComponent::Read(std::istream &is, bool binary) {
  ExpectOneOrTwoTokens(is, binary, "<VectorMixComponent>", "<LearningRate>");
  ReadBasicType(is, binary, &learning_rate_);
  ExpectToken(is, binary, "<NumBlocks>");
  ReadBasicType(is, binary, &num_blocks_);
  ExpectToken(is, binary, "<ConstComponentDim>");
  ReadBasicType(is, binary, &const_component_dim_);
  ExpectToken(is, binary, "<LinearParams>");
  linear_params_.Read(is, binary);
  ExpectToken(is, binary, "<BiasParams>");
  bias_params_.Read(is, binary);
  ExpectToken(is, binary, "</VectorMixComponent>");
  KALDI_ASSERT(linear_params_.NumCols() == bias_params_.Dim());
  KALDI_ASSERT(linear_params_.NumRows() == num_blocks_);
  block_dim_ = linear_params_.NumCols();
}

void VectorMixComponent::Write(std::ostream &os, bool binary) const {
  WriteToken(os, binary, "<VectorMixComponent>");
  WriteToken(os, binary, "<LearningRate>");
  WriteBasicType(os, binary, learning_rate_);
  WriteToken(os, binary, "<NumBlocks>");
  WriteBasicType(os, binary, num_blocks_);
  WriteToken(os, binary, "<ConstComponentDim>");
  WriteBasicType(os, binary, const_component_dim_);
  WriteToken(os, binary, "<LinearParams>");
  linear_params_.Write(os, binary);
  WriteToken(os, binary, "<BiasParams>");
  bias_params_.Write(os, binary);
  WriteToken(os, binary, "</VectorMixComponent>");
}


int32 VectorMixComponent::GetParameterDim() const {
  // Note: num_blocks_ should divide both InputDim() and OutputDim().
  return block_dim_ * (num_blocks_ + 1);
}

void VectorMixComponent::Vectorize(VectorBase<BaseFloat> *params) const {
  int32 l = linear_params_.NumRows() * linear_params_.NumCols(),
      b = bias_params_.Dim();
  params->Range(0, l).CopyRowsFromMat(linear_params_);
  params->Range(l, b).CopyFromVec(bias_params_);
}
void VectorMixComponent::UnVectorize(const VectorBase<BaseFloat> &params) {
  int32 l = linear_params_.NumRows() * linear_params_.NumCols(),
      b = bias_params_.Dim();
  linear_params_.CopyRowsFromVec(params.Range(0, l));
  bias_params_.CopyFromVec(params.Range(l, b));
}


AffineComponentExt::AffineComponentExt(const AffineComponentExt &component):
    AffineComponent(component),
    const_component_dim_(component.const_component_dim_) { }

AffineComponentExt::AffineComponentExt(const AffineComponent &component, int32 const_dim):
    AffineComponent(component),
    const_component_dim_(const_dim) { }

AffineComponentExt::AffineComponentExt(const AffineComponentPreconditioned &component,
                                       int32 const_dim):
    AffineComponent(component),
    const_component_dim_(const_dim) { }

AffineComponentExt::AffineComponentExt(const CuMatrixBase<BaseFloat> &linear_params,
                                 const CuVectorBase<BaseFloat> &bias_params,
                                 BaseFloat learning_rate, int32 const_component_dim):
    AffineComponent(linear_params, bias_params, learning_rate),
    const_component_dim_(const_component_dim) {
}

void AffineComponentExt::SetParams(const VectorBase<BaseFloat> &bias,
                                const MatrixBase<BaseFloat> &linear,
                                int32 const_component_dim) {
  bias_params_ = bias;
  linear_params_ = linear;
  KALDI_ASSERT(bias_params_.Dim() == linear_params_.NumRows());
  const_component_dim_ = const_component_dim;
}

std::string AffineComponentExt::Info() const {
  std::stringstream stream;
  BaseFloat linear_params_size = static_cast<BaseFloat>(linear_params_.NumRows())
      * static_cast<BaseFloat>(linear_params_.NumCols());
  BaseFloat linear_stddev =
      std::sqrt(TraceMatMat(linear_params_, linear_params_, kTrans) /
                linear_params_size),
      bias_stddev = std::sqrt(VecVec(bias_params_, bias_params_) /
                              bias_params_.Dim());
  stream << Type() << ", input-dim=" << InputDim()
         << ", output-dim=" << OutputDim()
         << ", const-component-dim=" << const_component_dim_
         << ", linear-params-stddev=" << linear_stddev
         << ", bias-params-stddev=" << bias_stddev
         << ", learning-rate=" << LearningRate();
  return stream.str();
}

Component* AffineComponentExt::Copy() const {
  AffineComponentExt *ans = new AffineComponentExt();
  ans->learning_rate_ = learning_rate_;
  ans->linear_params_ = linear_params_;
  ans->bias_params_ = bias_params_;
  ans->const_component_dim_ = const_component_dim_;
  ans->is_gradient_ = is_gradient_;
  return ans;
}

void AffineComponentExt::Init(BaseFloat learning_rate,
                           int32 input_dim, int32 output_dim,
                           BaseFloat param_stddev, BaseFloat bias_stddev,
                           int32 const_component_dim) {
  AffineComponent::Init(learning_rate, input_dim, output_dim, param_stddev, bias_stddev);
  const_component_dim_ = const_component_dim;
}

void AffineComponentExt::InitFromString(std::string args) {
  std::string orig_args(args);
  bool ok = true;
  BaseFloat learning_rate = learning_rate_;
  std::string matrix_filename;
  int32 input_dim = -1, output_dim = -1, const_dim = -1;
  ParseFromString("learning-rate", &args, &learning_rate); // optional.
  if (ParseFromString("matrix", &args, &matrix_filename)) {
    AffineComponent::Init(learning_rate, matrix_filename);
    if (ParseFromString("trans-input-dim", &args, &input_dim))
      KALDI_ASSERT(input_dim == linear_params_.NumCols() &&
                   "trans-input-dim mismatch vs. matrix.");
    if (ParseFromString("trans-output-dim", &args, &output_dim))
      KALDI_ASSERT(output_dim == linear_params_.NumRows() &&
                   "trans-output-dim mismatch vs. matrix.");
  } else {
    ok = ok && ParseFromString("trans-input-dim", &args, &input_dim);
    ok = ok && ParseFromString("trans-output-dim", &args, &output_dim);
    ok = ok && ParseFromString("const-component-dim", &args, &const_dim);
    BaseFloat param_stddev = 1.0 / std::sqrt(input_dim),
        bias_stddev = 1.0;
    ParseFromString("param-stddev", &args, &param_stddev);
    ParseFromString("bias-stddev", &args, &bias_stddev);
    Init(learning_rate, input_dim, output_dim,
         param_stddev, bias_stddev, const_dim);
  }
  if (!args.empty())
    KALDI_ERR << "Could not process these elements in initializer: "
              << args;
  if (!ok)
    KALDI_ERR << "Bad initializer " << orig_args;
}


void AffineComponentExt::Propagate(const ChunkInfo &in_info,
                                const ChunkInfo &out_info,
                                const CuMatrixBase<BaseFloat> &in,
                                CuMatrixBase<BaseFloat> *out) const  {
  in_info.CheckSize(in);
  out_info.CheckSize(*out);
  KALDI_ASSERT(in_info.NumChunks() == out_info.NumChunks());
  
  CuSubMatrix<BaseFloat> trans_in(in, 0, in.NumRows(), 0, in.NumCols() - const_component_dim_);
  CuSubMatrix<BaseFloat> trans_out(*out, 0, in.NumRows(), 0, out->NumCols() - const_component_dim_);
  // No need for asserts as they'll happen within the matrix operations.
  trans_out.CopyRowsFromVec(bias_params_); // copies bias_params_ to each row
  // of *out.
  trans_out.AddMatMat(1.0, trans_in, kNoTrans, linear_params_, kTrans, 1.0);

  if (const_component_dim_ > 0) {
    CuSubMatrix<BaseFloat> const_in(in, 0, in.NumRows(), in.NumCols() - const_component_dim_, const_component_dim_);
    CuSubMatrix<BaseFloat> const_out(*out, 0, in.NumRows(), out->NumCols() - const_component_dim_, const_component_dim_);
    const_out.CopyFromMat(const_in);
  }
}

void AffineComponentExt::UpdateSimple(const CuMatrixBase<BaseFloat> &in_value,
                                   const CuMatrixBase<BaseFloat> &out_deriv) {
  CuSubMatrix<BaseFloat> trans_in_value(in_value, 0, in_value.NumRows(), 0, in_value.NumCols() - const_component_dim_);
  CuSubMatrix<BaseFloat> trans_out_deriv(out_deriv, 0, out_deriv.NumRows(), 0, out_deriv.NumCols() - const_component_dim_);
  bias_params_.AddRowSumMat(learning_rate_, trans_out_deriv, 1.0);
  linear_params_.AddMatMat(learning_rate_, trans_out_deriv, kTrans,
                           trans_in_value, kNoTrans, 1.0);
}

void AffineComponentExt::Backprop(const ChunkInfo &, //in_info,
                               const ChunkInfo &, //out_info,
                               const CuMatrixBase<BaseFloat> &in_value,
                               const CuMatrixBase<BaseFloat> &, //out_value,
                               const CuMatrixBase<BaseFloat> &out_deriv,
                               Component *to_update_in, // may be identical to "this".
                               CuMatrix<BaseFloat> *in_deriv) const {
  AffineComponentExt *to_update = dynamic_cast<AffineComponentExt*>(to_update_in);
  in_deriv->Resize(out_deriv.NumRows(), InputDim());
  int32 trans_in_dim = in_deriv->NumCols() - const_component_dim_;
  int32 trans_out_dim = out_deriv.NumCols() - const_component_dim_;
  CuSubMatrix<BaseFloat> trans_in_deriv(*in_deriv, 0, out_deriv.NumRows(), 0, trans_in_dim);
  CuSubMatrix<BaseFloat> trans_out_deriv(out_deriv, 0, out_deriv.NumRows(), 0, trans_out_dim);
  // Propagate the derivative back to the input.
  trans_in_deriv.AddMatMat(1.0, trans_out_deriv, kNoTrans, linear_params_, kNoTrans, 0.0);

  if (const_component_dim_ > 0) {
    CuSubMatrix<BaseFloat> const_in_deriv(*in_deriv, 0, out_deriv.NumRows(), trans_in_dim, const_component_dim_);
    CuSubMatrix<BaseFloat> const_out_deriv(out_deriv, 0, out_deriv.NumRows(), trans_out_dim, const_component_dim_);
    const_in_deriv.CopyFromMat(const_out_deriv);
  }

  if (to_update != NULL) {
    // Next update the model (must do this 2nd so the derivatives we propagate
    // are accurate, in case this == to_update_in.)
    if (to_update->is_gradient_)
      to_update->UpdateSimple(in_value, out_deriv);
    else  // the call below is to a virtual function that may be re-implemented
      to_update->Update(in_value, out_deriv);  // by child classes.
  }
}

void AffineComponentExt::Read(std::istream &is, bool binary) {
  std::ostringstream ostr_beg, ostr_end;
  ostr_beg << "<" << Type() << ">"; // e.g. "<AffineComponent>"
  ostr_end << "</" << Type() << ">"; // e.g. "</AffineComponent>"
  // might not see the "<AffineComponent>" part because
  // of how ReadNew() works.
  ExpectOneOrTwoTokens(is, binary, ostr_beg.str(), "<LearningRate>");
  ReadBasicType(is, binary, &learning_rate_);
  ExpectToken(is, binary, "<ConstComponentDim>");
  ReadBasicType(is, binary, &const_component_dim_);
  ExpectToken(is, binary, "<LinearParams>");
  linear_params_.Read(is, binary);
  ExpectToken(is, binary, "<BiasParams>");
  bias_params_.Read(is, binary);
  std::string tok;
  // back-compatibility code.  TODO: re-do this later.
  ReadToken(is, binary, &tok);
  if (tok == "<AvgInput>") { // discard the following.
    CuVector<BaseFloat> avg_input;
    avg_input.Read(is, binary);
    BaseFloat avg_input_count;
    ExpectToken(is, binary, "<AvgInputCount>");
    ReadBasicType(is, binary, &avg_input_count);
    ReadToken(is, binary, &tok);
  }
  if (tok == "<IsGradient>") {
    ReadBasicType(is, binary, &is_gradient_);
    ExpectToken(is, binary, ostr_end.str());
  } else {
    is_gradient_ = false;
    KALDI_ASSERT(tok == ostr_end.str());
  }
}

void AffineComponentExt::Write(std::ostream &os, bool binary) const {
  std::ostringstream ostr_beg, ostr_end;
  ostr_beg << "<" << Type() << ">"; // e.g. "<AffineComponent>"
  ostr_end << "</" << Type() << ">"; // e.g. "</AffineComponent>"
  WriteToken(os, binary, ostr_beg.str());
  WriteToken(os, binary, "<LearningRate>");
  WriteBasicType(os, binary, learning_rate_);
  WriteToken(os, binary, "<ConstComponentDim>");
  WriteBasicType(os, binary, const_component_dim_);
  WriteToken(os, binary, "<LinearParams>");
  linear_params_.Write(os, binary);
  WriteToken(os, binary, "<BiasParams>");
  bias_params_.Write(os, binary);
  WriteToken(os, binary, "<IsGradient>");
  WriteBasicType(os, binary, is_gradient_);
  WriteToken(os, binary, ostr_end.str());
}

int32 AffineComponentExt::GetParameterDim() const {
  return (linear_params_.NumCols() + 1) * linear_params_.NumRows();
}
void AffineComponentExt::Vectorize(VectorBase<BaseFloat> *params) const {
  params->Range(0, linear_params_.NumCols() * linear_params_.NumRows()).CopyRowsFromMat(linear_params_);
  params->Range(linear_params_.NumCols() * linear_params_.NumRows(),
                linear_params_.NumRows()).CopyFromVec(bias_params_);
}
void AffineComponentExt::UnVectorize(const VectorBase<BaseFloat> &params) {
  linear_params_.CopyRowsFromVec(params.Range(0, linear_params_.NumCols() * linear_params_.NumRows()));
  bias_params_.CopyFromVec(params.Range(linear_params_.NumCols() * linear_params_.NumRows(),
                                        linear_params_.NumRows()));
}

void FixedAffineComponentExt::Init(const CuMatrixBase<BaseFloat> &mat, int32 const_component_dim) {
  FixedAffineComponent::Init(mat);
  const_component_dim_ = const_component_dim;
}

void FixedAffineComponentExt::InitFromString(std::string args) {
  std::string orig_args = args;
  std::string filename;
  int32 const_component_dim;
  bool ok = ParseFromString("const-component-dim", &args, &const_component_dim)
            && ParseFromString("matrix", &args, &filename);

  if (!ok || !args.empty())
    KALDI_ERR << "Invalid initializer for layer of type "
              << Type() << ": \"" << orig_args << "\"";

  bool binary;
  Input ki(filename, &binary);
  CuMatrix<BaseFloat> mat;
  mat.Read(ki.Stream(), binary);
  KALDI_ASSERT(mat.NumRows() != 0);
  Init(mat, const_component_dim);
}

std::string FixedAffineComponentExt::Info() const {
  std::stringstream stream;
  stream << FixedAffineComponent::Info() << ", const-component-dim=" << const_component_dim_;
  return stream.str();
}

void FixedAffineComponentExt::Propagate(const ChunkInfo &in_info,
                                     const ChunkInfo &out_info,
                                     const CuMatrixBase<BaseFloat> &in,
                                     CuMatrixBase<BaseFloat> *out) const  {
  in_info.CheckSize(in);
  out_info.CheckSize(*out);
  KALDI_ASSERT(in_info.NumChunks() == out_info.NumChunks());
  
  if (const_component_dim_ > 0) {
    CuSubMatrix<BaseFloat> in_const(in, 0, in.NumRows(), linear_params_.NumCols(), const_component_dim_);
    CuSubMatrix<BaseFloat> out_const(*out, 0, out->NumRows(), linear_params_.NumRows(), const_component_dim_);
    out_const.CopyFromMat(in_const);
  }

  CuSubMatrix<BaseFloat> in_part(in, 0, in.NumRows(), 0, linear_params_.NumCols());
  CuSubMatrix<BaseFloat> out_part(*out, 0, out->NumRows(), 0, linear_params_.NumRows());
  out_part.AddMatMat(1.0, in_part, kNoTrans, linear_params_, kTrans, 0.0);
  out_part.AddVecToRows(1.0, bias_params_);
}

void FixedAffineComponentExt::Backprop(const ChunkInfo &,  //in_info,
                                    const ChunkInfo &,  //out_info,
                                    const CuMatrixBase<BaseFloat> &,  //in_value,
                                    const CuMatrixBase<BaseFloat> &,  //out_value,
                                    const CuMatrixBase<BaseFloat> &out_deriv,
                                    Component *,  //to_update, // may be identical to "this".
                                    CuMatrix<BaseFloat> *in_deriv) const  {
  in_deriv->Resize(out_deriv.NumRows(), InputDim());

  if (const_component_dim_ > 0) {
    CuSubMatrix<BaseFloat> in_deriv_const(*in_deriv, 0, in_deriv->NumRows(), linear_params_.NumCols(), const_component_dim_);
    CuSubMatrix<BaseFloat> out_deriv_const(out_deriv, 0, out_deriv.NumRows(), linear_params_.NumRows(), const_component_dim_);
    out_deriv_const.CopyFromMat(in_deriv_const);
  }

  CuSubMatrix<BaseFloat> in_deriv_part(*in_deriv, 0, in_deriv->NumRows(), 0, linear_params_.NumCols());
  CuSubMatrix<BaseFloat> out_deriv_part(out_deriv, 0, out_deriv.NumRows(), 0, linear_params_.NumRows());
  in_deriv_part.AddMatMat(1.0, out_deriv_part, kNoTrans, linear_params_, kNoTrans, 0.0);
}

Component* FixedAffineComponentExt::Copy() const {
  FixedAffineComponentExt *ans = new FixedAffineComponentExt();
  ans->linear_params_ = linear_params_;
  ans->bias_params_ = bias_params_;
  ans->const_component_dim_ = const_component_dim_;
  return ans;
}


void FixedAffineComponentExt::Write(std::ostream &os, bool binary) const {
  WriteToken(os, binary, "<FixedAffineComponentExt>");
  WriteToken(os, binary, "<LinearParams>");
  linear_params_.Write(os, binary);
  WriteToken(os, binary, "<BiasParams>");
  bias_params_.Write(os, binary);
  WriteToken(os, binary, "<ConstComponentDim>");
  WriteBasicType(os, binary, const_component_dim_);
  WriteToken(os, binary, "</FixedAffineComponentExt>");
}

void FixedAffineComponentExt::Read(std::istream &is, bool binary) {
  ExpectOneOrTwoTokens(is, binary, "<FixedAffineComponentExt>", "<LinearParams>");
  linear_params_.Read(is, binary);
  ExpectToken(is, binary, "<BiasParams>");
  bias_params_.Read(is, binary);
  ExpectToken(is, binary, "<ConstComponentDim>");
  ReadBasicType(is, binary, &const_component_dim_);
  ExpectToken(is, binary, "</FixedAffineComponentExt>");
}

void TanhComponentExt::Read(std::istream &is, bool binary) {
  std::ostringstream ostr_beg, ostr_end;
  ostr_beg << "<" << Type() << ">"; // e.g. "<SigmoidComponent>"
  ostr_end << "</" << Type() << ">"; // e.g. "</SigmoidComponent>"
  ExpectOneOrTwoTokens(is, binary, ostr_beg.str(), "<Dim>");
  ReadBasicType(is, binary, &dim_); // Read dimension.
  ExpectToken(is, binary, "<ConstDim>");
  ReadBasicType(is, binary, &const_dim_);
  std::string tok; // TODO: remove back-compatibility code.
  ReadToken(is, binary, &tok);
  if (tok == "<ValueSum>") {
    value_sum_.Read(is, binary);
    ExpectToken(is, binary, "<DerivSum>");
    deriv_sum_.Read(is, binary);
    ExpectToken(is, binary, "<Count>");
    ReadBasicType(is, binary, &count_);
    ExpectToken(is, binary, ostr_end.str());
  } else if (tok == "<Counts>") { // Back-compat code for SoftmaxComponent.
    value_sum_.Read(is, binary); // Set both value_sum_ and deriv_sum_ to the same value,
    // and count_ to its sum.
    count_ = value_sum_.Sum();
    ExpectToken(is, binary, ostr_end.str());
  } else {
    KALDI_ASSERT(tok == ostr_end.str());
  }
}

void TanhComponentExt::Write(std::ostream &os, bool binary) const {
  std::ostringstream ostr_beg, ostr_end;
  ostr_beg << "<" << Type() << ">"; // e.g. "<SigmoidComponent>"
  ostr_end << "</" << Type() << ">"; // e.g. "</SigmoidComponent>"
  WriteToken(os, binary, ostr_beg.str());
  WriteToken(os, binary, "<Dim>");
  WriteBasicType(os, binary, dim_);
  WriteToken(os, binary, "<ConstDim>");
  WriteBasicType(os, binary, const_dim_);
  WriteToken(os, binary, "<ValueSum>");
  value_sum_.Write(os, binary);
  WriteToken(os, binary, "<DerivSum>");
  deriv_sum_.Write(os, binary);
  WriteToken(os, binary, "<Count>");
  WriteBasicType(os, binary, count_);
  WriteToken(os, binary, ostr_end.str());
}

void TanhComponentExt::InitFromString(std::string args) {
  std::string orig_args(args);
  int32 dim, const_dim;
  bool ok = ParseFromString("dim", &args, &dim) && ParseFromString("const-dim", &args, &const_dim);
  if (!ok || !args.empty() || dim <= 0 || const_dim < 0)
    KALDI_ERR << "Invalid initializer for layer of type "
              << Type() << ": \"" << orig_args << "\"";
  Init(dim, const_dim);
}

void TanhComponentExt::Propagate(const ChunkInfo &in_info,
                              const ChunkInfo &out_info,
                              const CuMatrixBase<BaseFloat> &in,
                              CuMatrixBase<BaseFloat> *out) const  {
  // Apply tanh function to each element of the output...
  // the tanh function may be written as -1 + ( 2 / (1 + e^{-2 x})),
  // which is a scaled and shifted sigmoid.
  
  in_info.CheckSize(in);
  out_info.CheckSize(*out);
  KALDI_ASSERT(in_info.NumChunks() == out_info.NumChunks());
  int32 nonlinear_dim = dim_ - const_dim_;
  CuSubMatrix<BaseFloat> out_part(*out, 0, out->NumRows(), 0, nonlinear_dim);
  CuSubMatrix<BaseFloat> in_part(in, 0, in.NumRows(), 0, nonlinear_dim);
  out_part.Tanh(in_part);
  if (const_dim_ > 0) {
    CuSubMatrix<BaseFloat> out_const(*out, 0, out->NumRows(), nonlinear_dim, const_dim_);
    CuSubMatrix<BaseFloat> in_const(in, 0, in.NumRows(), nonlinear_dim, const_dim_);
    out_const.CopyFromMat(in_const);
  }
}

void TanhComponentExt::Backprop(const ChunkInfo &, //in_info,
                             const ChunkInfo &, //out_info,
                             const CuMatrixBase<BaseFloat> &, //in_value,
                             const CuMatrixBase<BaseFloat> &out_value,
                             const CuMatrixBase<BaseFloat> &out_deriv,
                             Component *to_update, // may be identical to "this".
                             CuMatrix<BaseFloat> *in_deriv) const {
  /*
    Note on the derivative of the tanh function:
    tanh'(x) = sech^2(x) = -(tanh(x)+1) (tanh(x)-1) = 1 - tanh^2(x)

    The element by element equation of what we're doing would be:
    in_deriv = out_deriv * (1.0 - out_value^2).
    We can accomplish this via calls to the matrix library. */

  int32 nonlinear_dim = dim_ - const_dim_;
  in_deriv->Resize(out_deriv.NumRows(), out_deriv.NumCols());

  if (const_dim_ > 0) {
    CuSubMatrix<BaseFloat> in_deriv_const(*in_deriv, 0, in_deriv->NumRows(), nonlinear_dim, const_dim_);
    CuSubMatrix<BaseFloat> out_deriv_const(out_deriv, 0, out_deriv.NumRows(), nonlinear_dim, const_dim_);
    out_deriv_const.CopyFromMat(in_deriv_const);
  }

  CuSubMatrix<BaseFloat> in_deriv_part(*in_deriv, 0, in_deriv->NumRows(), 0, nonlinear_dim);
  CuSubMatrix<BaseFloat> out_value_part(out_value, 0, out_value.NumRows(), 0, nonlinear_dim);
  CuSubMatrix<BaseFloat> out_deriv_part(out_deriv, 0, out_deriv.NumRows(), 0, nonlinear_dim);

  in_deriv_part.CopyFromMat(out_value_part);
  in_deriv_part.ApplyPow(2.0);
  in_deriv_part.Scale(-1.0);
  in_deriv_part.Add(1.0);

  // now in_deriv = (1.0 - out_value^2), the element-by-element derivative of
  // the nonlinearity.
  if (to_update != NULL)
    dynamic_cast<NonlinearComponent*>(to_update)->UpdateStats(out_value_part,
                                                              &in_deriv_part);
  in_deriv_part.MulElements(out_deriv_part);
}

void PnormComponentExt::Init(int32 input_dim, int32 output_dim, BaseFloat p, int32 const_dim)  {
  PnormComponent::Init(input_dim, output_dim, p);
  const_dim_ = const_dim;
}

void PnormComponentExt::InitFromString(std::string args) {
  std::string orig_args(args);
  int32 input_dim = 0;
  int32 output_dim = 0;
  BaseFloat p = 2;
  int32 const_dim = 0;
  bool ok = ParseFromString("output-dim", &args, &output_dim) &&
      ParseFromString("input-dim", &args, &input_dim) &&
      ParseFromString("const-dim", &args, &const_dim);
  ParseFromString("p", &args, &p);
  if (!ok || !args.empty() || output_dim <= 0 || const_dim < 0)
    KALDI_ERR << "Invalid initializer for layer of type "
              << Type() << ": \"" << orig_args << "\"";
  Init(input_dim, output_dim, p, const_dim);
}


void PnormComponentExt::Propagate(const ChunkInfo &in_info,
                               const ChunkInfo &out_info,
                               const CuMatrixBase<BaseFloat> &in,
                               CuMatrixBase<BaseFloat> *out) const  {
  in_info.CheckSize(in);
  out_info.CheckSize(*out);
  KALDI_ASSERT(in_info.NumChunks() == out_info.NumChunks());
  
  CuSubMatrix<BaseFloat> in_part(in, 0, in.NumRows(), 0, input_dim_);
  CuSubMatrix<BaseFloat> out_part(*out, 0, out->NumRows(), 0, output_dim_);
  out_part.GroupPnorm(in_part, p_);

  if (const_dim_ > 0) {
    CuSubMatrix<BaseFloat> in_const(in, 0, in.NumRows(), input_dim_, const_dim_);
    CuSubMatrix<BaseFloat> out_const(*out, 0, out->NumRows(), output_dim_, const_dim_);
    out_const.CopyFromMat(in_const);
  }
}

void PnormComponentExt::Backprop(const ChunkInfo &,  // in_info,
                              const ChunkInfo &,  // out_info,
                              const CuMatrixBase<BaseFloat> &in_value,
                              const CuMatrixBase<BaseFloat> &out_value,
                              const CuMatrixBase<BaseFloat> &out_deriv,
                              Component *to_update, 
                                // may be identical to "this".
                              CuMatrix<BaseFloat> *in_deriv) const  {
  in_deriv->Resize(in_value.NumRows(), in_value.NumCols(), kSetZero);

  if (const_dim_ > 0) {
    CuSubMatrix<BaseFloat> in_deriv_const(*in_deriv, 0, in_deriv->NumRows(), input_dim_, const_dim_);
    CuSubMatrix<BaseFloat> out_deriv_const(out_deriv, 0, out_deriv.NumRows(), output_dim_, const_dim_);
    out_deriv_const.CopyFromMat(in_deriv_const);
  }

  CuSubMatrix<BaseFloat> in_deriv_part(*in_deriv, 0, in_deriv->NumRows(), 0, input_dim_);
  CuSubMatrix<BaseFloat> out_deriv_part(out_deriv, 0, out_deriv.NumRows(), 0, output_dim_);
  CuSubMatrix<BaseFloat> in_value_part(in_value, 0, in_value.NumRows(), 0, input_dim_);
  CuSubMatrix<BaseFloat> out_value_part(out_value, 0, out_value.NumRows(), 0, output_dim_);
  in_deriv_part.GroupPnormDeriv(in_value_part, out_value_part, p_);
  in_deriv_part.MulRowsGroupMat(out_deriv_part);
}

void PnormComponentExt::Read(std::istream &is, bool binary) {
  ExpectOneOrTwoTokens(is, binary, "<PnormComponentExt>", "<InputDim>");
  ReadBasicType(is, binary, &input_dim_);
  ExpectToken(is, binary, "<OutputDim>");
  ReadBasicType(is, binary, &output_dim_);
  ExpectToken(is, binary, "<ConstDim>");
  ReadBasicType(is, binary, &const_dim_);
  ExpectToken(is, binary, "<P>");
  ReadBasicType(is, binary, &p_);
  ExpectToken(is, binary, "</PnormComponentExt>");
}

void PnormComponentExt::Write(std::ostream &os, bool binary) const {
  WriteToken(os, binary, "<PnormComponentExt>");
  WriteToken(os, binary, "<InputDim>");
  WriteBasicType(os, binary, input_dim_);
  WriteToken(os, binary, "<OutputDim>");
  WriteBasicType(os, binary, output_dim_);
  WriteToken(os, binary, "<ConstDim>");
  WriteBasicType(os, binary, const_dim_);
  WriteToken(os, binary, "<P>");
  WriteBasicType(os, binary, p_);
  WriteToken(os, binary, "</PnormComponentExt>");
}

std::string PnormComponentExt::Info() const {
  std::stringstream stream;
  stream << Type() << ", input-dim = " << input_dim_
         << ", output-dim = " << output_dim_
         << ", const-dim = " << const_dim_
     << ", p = " << p_;
  return stream.str();
}

const BaseFloat NormalizeComponentExt::kNormFloor = pow(2.0, -66);
// This component modifies the vector of activations by scaling it so that the
// root-mean-square equals 1.0.

void NormalizeComponentExt::Read(std::istream &is, bool binary) {
  std::ostringstream ostr_beg, ostr_end;
  ostr_beg << "<" << Type() << ">"; // e.g. "<SigmoidComponent>"
  ostr_end << "</" << Type() << ">"; // e.g. "</SigmoidComponent>"
  ExpectOneOrTwoTokens(is, binary, ostr_beg.str(), "<Dim>");
  ReadBasicType(is, binary, &dim_); // Read dimension.
  ExpectToken(is, binary, "<ConstDim>");
  ReadBasicType(is, binary, &const_dim_);
  std::string tok; // TODO: remove back-compatibility code.
  ReadToken(is, binary, &tok);
  if (tok == "<ValueSum>") {
    value_sum_.Read(is, binary);
    ExpectToken(is, binary, "<DerivSum>");
    deriv_sum_.Read(is, binary);
    ExpectToken(is, binary, "<Count>");
    ReadBasicType(is, binary, &count_);
    ExpectToken(is, binary, ostr_end.str());
  } else if (tok == "<Counts>") { // Back-compat code for SoftmaxComponent.
    value_sum_.Read(is, binary); // Set both value_sum_ and deriv_sum_ to the same value,
    // and count_ to its sum.
    count_ = value_sum_.Sum();
    ExpectToken(is, binary, ostr_end.str());
  } else {
    KALDI_ASSERT(tok == ostr_end.str());
  }
}

void NormalizeComponentExt::Write(std::ostream &os, bool binary) const {
  std::ostringstream ostr_beg, ostr_end;
  ostr_beg << "<" << Type() << ">"; // e.g. "<SigmoidComponent>"
  ostr_end << "</" << Type() << ">"; // e.g. "</SigmoidComponent>"
  WriteToken(os, binary, ostr_beg.str());
  WriteToken(os, binary, "<Dim>");
  WriteBasicType(os, binary, dim_);
  WriteToken(os, binary, "<ConstDim>");
  WriteBasicType(os, binary, const_dim_);
  WriteToken(os, binary, "<ValueSum>");
  value_sum_.Write(os, binary);
  WriteToken(os, binary, "<DerivSum>");
  deriv_sum_.Write(os, binary);
  WriteToken(os, binary, "<Count>");
  WriteBasicType(os, binary, count_);
  WriteToken(os, binary, ostr_end.str());
}

void NormalizeComponentExt::InitFromString(std::string args) {
  std::string orig_args(args);
  int32 dim, const_dim;
  bool ok = ParseFromString("dim", &args, &dim) && ParseFromString("const-dim", &args, &const_dim);
  if (!ok || !args.empty() || dim <= 0 || const_dim < 0)
    KALDI_ERR << "Invalid initializer for layer of type "
              << Type() << ": \"" << orig_args << "\"";
  Init(dim, const_dim);
}

void NormalizeComponentExt::Propagate(const ChunkInfo &in_info,
                                   const ChunkInfo &out_info,
                                   const CuMatrixBase<BaseFloat> &in,
                                   CuMatrixBase<BaseFloat> *out) const  {
  out->CopyFromMat(in);

  CuSubMatrix<BaseFloat> in_part(in, 0, in.NumRows(), 0, dim_);
  CuVector<BaseFloat> in_norm(in.NumRows());
  in_norm.AddDiagMat2(1.0 / dim_, in_part, kNoTrans, 0.0);
  in_norm.ApplyFloor(kNormFloor);
  in_norm.ApplyPow(-0.5);

  CuSubMatrix<BaseFloat> out_part(*out, 0, out->NumRows(), 0, dim_);
  out_part.MulRowsVec(in_norm);
}

/*
  A note on the derivative of NormalizeComponent...
  let both row_in and row_out be vectors of dimension D.
  Let p = row_in^T row_in / D, and let
      f = 1 / sqrt(max(kNormFloor, p)), and we compute row_out as:
row_out = f row_in.
  Suppose we have a quantity deriv_out which is the derivative
  of the objective function w.r.t. row_out.  We want to compute
  deriv_in which is the derivative of the objective function w.r.t.
  row_in.  Let the objective function be F.  One term is obvious: we have
     deriv_in = f deriv_out + ....
  next we have to take into account the derivative that gets back-propagated
  through f.  Obviously, dF/df = deriv_out^T row_in.
  And df/dp = (p <= kNormFloor ? 0.0 : -0.5 p^{-1.5}) = (f == 1 / sqrt(kNormFloor) ? 0.0 : -0.5 f^3),
  and dp/d(row_in) = 2/D row_in. [it's vector_valued].
  So this term in dF/d(row_in) equals:
    dF/df df/dp dp/d(row_in)   =    2/D (f == 1 / sqrt(kNormFloor)  ? 0.0 : -0.5 f^3) (deriv_out^T row_in) row_in
  So
     deriv_in = f deriv_out + (f == 1.0 ? 0.0 : -f^3 / D) (deriv_out^T row_in) row_in

*/

void NormalizeComponentExt::Backprop(const ChunkInfo &,  // in_info,
                                  const ChunkInfo &,  // out_info,
                                  const CuMatrixBase<BaseFloat> &in_value,
                                  const CuMatrixBase<BaseFloat> &out_value,
                                  const CuMatrixBase<BaseFloat> &out_deriv,
                                  Component *to_update, 
                                    // may be identical to "this".
                                  CuMatrix<BaseFloat> *in_deriv) const  {
  in_deriv->Resize(out_deriv.NumRows(), out_deriv.NumCols());

  if (const_dim_ > 0) {
    CuSubMatrix<BaseFloat> in_deriv_const(*in_deriv, 0, in_deriv->NumRows(), dim_, const_dim_);
    CuSubMatrix<BaseFloat> out_deriv_const(out_deriv, 0, out_deriv.NumRows(), dim_, const_dim_);
    out_deriv_const.CopyFromMat(in_deriv_const);
  }

  CuSubMatrix<BaseFloat> in_deriv_part(*in_deriv, 0, in_deriv->NumRows(), 0, dim_);
  CuSubMatrix<BaseFloat> out_deriv_part(out_deriv, 0, out_deriv.NumRows(), 0, dim_);
  CuSubMatrix<BaseFloat> in_value_part(in_value, 0, in_value.NumRows(), 0, dim_);
  CuSubMatrix<BaseFloat> out_value_part(out_value, 0, out_value.NumRows(), 0, dim_);

  CuVector<BaseFloat> in_norm(in_value_part.NumRows());
  in_norm.AddDiagMat2(1.0 / in_value_part.NumCols(),
                      in_value_part, kNoTrans, 0.0);
  in_norm.ApplyFloor(kNormFloor);
  in_norm.ApplyPow(-0.5);
  in_deriv_part.AddDiagVecMat(1.0, in_norm, out_deriv_part, kNoTrans, 0.0);
  in_norm.ReplaceValue(1.0 / sqrt(kNormFloor), 0.0);
  in_norm.ApplyPow(3.0);
  CuVector<BaseFloat> dot_products(in_deriv_part.NumRows());
  dot_products.AddDiagMatMat(1.0, out_deriv_part, kNoTrans, in_value_part, kTrans, 0.0);
  dot_products.MulElements(in_norm);

  in_deriv_part.AddDiagVecMat(-1.0 / in_value_part.NumCols(), dot_products, in_value_part, kNoTrans, 1.0);
}

} // namespace nnet2
} // namespace kaldi
