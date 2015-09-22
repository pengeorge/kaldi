// nnet2/nnet-functions.cc

// Copyright 2011-2012  Karel Vesely
//                      Johns Hopkins University (author: Daniel Povey)

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

#include "nnet2/nnet-nnet.h"
#include "util/stl-utils.h"
#include "chenzp-nnet2/nnet-functions-ext.h"

namespace kaldi {
namespace nnet2 {


void InsertComponentsAndResize(const Nnet &src_nnet,
                      int32 c_to_insert, // component-index before which to insert.
                      Nnet *dest_nnet) {
  KALDI_ASSERT(c_to_insert >= 0 && c_to_insert <= dest_nnet->NumComponents());
  int32 c_tot = dest_nnet->NumComponents() + src_nnet.NumComponents();
  std::vector<Component*> components(c_tot);

  for (int32 c = 0; c < c_to_insert; c++)
    components[c] = dest_nnet->GetComponent(c).Copy();

  for (int32 c = 0; c < src_nnet.NumComponents(); c++)
    components[c + c_to_insert] = src_nnet.GetComponent(c).Copy();

  const Component *last_insert_comp = components[src_nnet.NumComponents() - 1 + c_to_insert];
  int32 resize_pos = c_to_insert + src_nnet.NumComponents();
  const Component &next_comp = dest_nnet->GetComponent(c_to_insert);
  const AffineComponent *ac = dynamic_cast<const AffineComponent*>(&next_comp);
  if (!ac)
    KALDI_ERR << "The component after the last inserted one is not an AffineComponent: "
              << next_comp.Info();
  Component *extComp = ac->Copy();
  dynamic_cast<AffineComponent*>(extComp)->Resize(last_insert_comp->OutputDim(), ac->OutputDim());
  components[resize_pos] = extComp;
  for (int32 c = c_to_insert + 1; c < dest_nnet->NumComponents(); c++)
    components[c + src_nnet.NumComponents()] = dest_nnet->GetComponent(c).Copy();
  // Re-initialize "dest_nnet" from the resulting list of components.

  // The Init method will take ownership of the pointers in the vector:
  dest_nnet->Init(&components);
}

void ExtendComponents(int32 num_to_extend, Nnet *dest_nnet, int32 const_dim) {
  KALDI_ASSERT(num_to_extend >= 0 && num_to_extend <= dest_nnet->NumComponents());

  std::vector<Component*> components;
  Component *extComp;
  for (int32 c = 0; c < num_to_extend; c++) {
    const Component &comp = dest_nnet->GetComponent(c);
    KALDI_LOG << "Convert component " << c << ": " << comp.Type()
      << ", InputDim = " << comp.InputDim() << ", OutputDim = " << comp.OutputDim();
    if (comp.Type() == "AffineComponent") {
      extComp = new AffineComponentExt(dynamic_cast<const AffineComponent&>(comp), const_dim);
    } else if (comp.Type() == "AffineComponentPreconditioned") {
      extComp = new AffineComponentExt(dynamic_cast<const AffineComponentPreconditioned&>(comp), const_dim);
    } else if (comp.Type() == "FixedAffineComponentExt") {
      extComp = dynamic_cast<const FixedAffineComponentExt&>(comp).Copy();
      dynamic_cast<FixedAffineComponentExt*>(extComp)->ResetConst(const_dim);
    } else if (comp.Type() == "SpliceComponent") {
      const SpliceComponent &sc = dynamic_cast<const SpliceComponent&>(comp);
      extComp = new SpliceComponent();
      dynamic_cast<SpliceComponent*>(extComp)->Init(sc.InputDim() + const_dim, sc.Context(), const_dim);
    } else if (comp.Type() == "TanhComponent") {
      extComp = new TanhComponentExt(dynamic_cast<const TanhComponent&>(comp), const_dim);
    } else if (comp.Type() == "PnormComponent") {
      extComp = new PnormComponentExt(dynamic_cast<const PnormComponent&>(comp), const_dim);
    } else if (comp.Type() == "NormalizeComponent") {
      extComp = new NormalizeComponentExt(dynamic_cast<const NormalizeComponent&>(comp), const_dim);
    } else if (comp.Type() == "VectorMixComponent") {
      extComp = dynamic_cast<const VectorMixComponent&>(comp).Copy();
      dynamic_cast<VectorMixComponent*>(extComp)->ResetConst(const_dim);
    } else {
      KALDI_ERR << comp.Type() << " is not supported for extending const dimension";
    }
    KALDI_LOG << "  to " << extComp->Type()
      << ", InputDim = " << extComp->InputDim() << ", OutputDim = " << extComp->OutputDim();
    components.push_back(extComp);
  }


  if (num_to_extend < dest_nnet->NumComponents()) {
    const Component &comp = dest_nnet->GetComponent(num_to_extend);
    const AffineComponent *ac = dynamic_cast<const AffineComponent*>(&comp);
    if (!ac)
      KALDI_ERR << "The component after the last extended one is not an AffineComponent: "
                << comp.Info();
    extComp = ac->Copy();
    dynamic_cast<AffineComponent*>(extComp)->Resize(ac->InputDim() + const_dim, ac->OutputDim());
    components.push_back(extComp);
  }

  KALDI_LOG << "Remaining components:";
  for (int32 c = num_to_extend + 1; c < dest_nnet->NumComponents(); c++) {
    Component &comp = dest_nnet->GetComponent(c);
    KALDI_LOG << "component " << c << ": " << comp.Type()
          << ", InputDim = " << comp.InputDim()
          << ", OutputDim = " << comp.OutputDim();
    components.push_back(comp.Copy());
  }
  KALDI_LOG << "Totally " << components.size() << " components in new nnet.";
  // Re-initialize "dest_nnet" from the resulting list of components.
  // The Init method will take ownership of the pointers in the vector:
  dest_nnet->Init(&components);
}



} // namespace nnet2
} // namespace kaldi
