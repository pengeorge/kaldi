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
#include "chenzp-nnet2/nnet-component-ext.h"
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

  if (const_component_dim_ != 0) {
    CuSubMatrix<BaseFloat> const_in(in, 0, num_frames, block_dim_ * num_blocks_, const_component_dim_);
    CuSubMatrix<BaseFloat> const_out(*out, 0, num_frames, block_dim_, const_component_dim_);
    const_out.CopyFromMat(const_in);
  }
  CuSubMatrix<BaseFloat> mix_out(*out, 0, num_frames, 0, block_dim_);
  mix_out.CopyRowsFromVec(bias_params_); // copies bias_params_ to each row of *mix_out.

  for (int32 b = 0; b < num_blocks_; b++) {
    CuSubMatrix<BaseFloat> in_block(in, 0, num_frames, b * block_dim_, block_dim_);
    CuSubVector<BaseFloat> param_vector = linear_params_.Row(b);
    CuMatrix<BaseFloat>    param_block(num_frames, block_dim_);
    param_block.CopyRowsFromVec(param_vector);
    CuMatrix<BaseFloat>    this_out(in_block);
    this_out.MulElements(param_block);
    mix_out.AddMat(1.0, this_out);
  }
}

void VectorMixComponent::UpdateSimple(
    const CuMatrixBase<BaseFloat> &in_value,
    const CuMatrixBase<BaseFloat> &out_deriv) {
  bias_params_.AddRowSumMat(learning_rate_, out_deriv, 1.0);
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

  if (const_component_dim_ != 0) {
    CuSubMatrix<BaseFloat> const_out_deriv(out_deriv, 0, num_frames, block_dim_, const_component_dim_);
    CuSubMatrix<BaseFloat> const_in_deriv(*in_deriv, 0, num_frames, block_dim_ * num_blocks_, const_component_dim_);
    const_in_deriv.CopyFromMat(const_out_deriv);
  }

  for (int32 b = 0; b < num_blocks_; b++) {
    CuSubMatrix<BaseFloat> out_deriv_block(out_deriv, 0, num_frames, 0, block_dim_);
    CuSubMatrix<BaseFloat> in_value_block(in_value, 0, num_frames, b * block_dim_, block_dim_);
    CuSubMatrix<BaseFloat> in_deriv_block(*in_deriv, 0, num_frames, b * block_dim_, block_dim_);
    CuSubVector<BaseFloat> param_vector = linear_params_.Row(b);
    CuMatrix<BaseFloat>    param_block(num_frames, block_dim_);
    param_block.CopyRowsFromVec(param_vector);
    in_deriv_block.CopyFromMat(out_deriv_block);
    in_deriv_block.MulElements(param_block);
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

} // namespace nnet2
} // namespace kaldi
