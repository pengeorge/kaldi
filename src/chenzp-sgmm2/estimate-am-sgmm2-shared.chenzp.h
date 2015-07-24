// sgmm2/estimate-am-sgmm2.h

// Copyright 2009-2011  Microsoft Corporation;  Lukas Burget;
//                      Saarland University (Author: Arnab Ghoshal);
//                      Ondrej Glembek;  Yanmin Qian;
// Copyright 2012-2013  Johns Hopkins University (Author: Daniel Povey)
//                      Liang Lu;  Arnab Ghoshal

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

#ifndef KALDI_SGMM2_ESTIMATE_AM_SGMM2_SHARED_H_
#define KALDI_SGMM2_ESTIMATE_AM_SGMM2_SHARED_H_ 1

#include <string>
#include <vector>

#include "sgmm2/am-sgmm2.h"
#include "gmm/model-common.h"
#include "itf/options-itf.h"
#include "thread/kaldi-thread.h"
#include "sgmm2/estimate-am-sgmm2.h"

namespace kaldi {

/** \class MleAmSgmm2AccsShared
 *  Class for the accumulators associated with the phonetic-subspace model
 *  parameters
 */
class MleAmSgmm2AccsShared {
 public:
  explicit MleAmSgmm2AccsShared(BaseFloat rand_prune = 1.0e-05, bool single_gamma = true)
      : total_frames_(0.0), total_like_(0.0), feature_dim_(0),
        phn_space_dim_(0), spk_space_dim_(0), num_gaussians_(0),
        num_pdfs_(0), num_groups_(0), num_models_(0), single_gamma_(single_gamma), rand_prune_(rand_prune) {}

  MleAmSgmm2AccsShared(const AmSgmm2 &model, SgmmUpdateFlagsType flags,
                 bool have_spk_vecs,
                 BaseFloat rand_prune = 1.0e-05)
      : total_frames_(0.0), total_like_(0.0), rand_prune_(rand_prune) {
    ResizeAccumulators(model, flags, have_spk_vecs);
  }

  ~MleAmSgmm2AccsShared();

  void Read(std::istream &in_stream, bool binary, bool add);
  //void SetNumAndDim(const AmSgmm2 &model);
  void Write(std::ostream &out_stream, bool binary) const;

  /// Checks the various accumulators for correct sizes given a model. With
  /// wrong sizes, assertion failure occurs. When the show_properties argument
  /// is set to true, dimensions and presence/absence of the various
  /// accumulators are printed. For use when accumulators are read from file.
  void Check(const AmSgmm2 &model, bool show_properties = true) const;
  void CheckShared(const std::vector<AmSgmm2 *> &models, bool show_properties = true) const;
  void CheckTotalGamma() const;

  /// Resizes the accumulators to the correct sizes given the model. The flags
  /// argument controls which accumulators to resize. 
  void ResizeAccumulators(const AmSgmm2 &model, SgmmUpdateFlagsType flags,
                          bool have_spk_vecs);

  /// Returns likelihood.
  BaseFloat Accumulate(const AmSgmm2 &model,
                       const Sgmm2PerFrameDerivedVars &frame_vars,
                       int32 pdf_index, // == j2.
                       BaseFloat weight,
                       Sgmm2PerSpkDerivedVars *spk_vars);

  /// Returns count accumulated (may differ from posteriors.Sum()
  /// due to weight pruning).
  BaseFloat AccumulateFromPosteriors(const AmSgmm2 &model,
                                     const Sgmm2PerFrameDerivedVars &frame_vars,
                                     const Matrix<BaseFloat> &posteriors,
                                     int32 pdf_index, // == j2.
                                     Sgmm2PerSpkDerivedVars *spk_vars);

  /// Accumulates global stats for the current speaker (if applicable).  If
  /// flags contains kSgmmSpeakerProjections (N), or
  /// kSgmmSpeakerWeightProjections (u), must call this after finishing the
  /// speaker's data.
  void CommitStatsForSpk(const AmSgmm2 &model,
                         const Sgmm2PerSpkDerivedVars &spk_vars);
  

  const std::vector<Matrix<double> > & GetGamma() const {
    return gamma_;
  }

  void AddGamma(const std::vector<Matrix<double> > &gamma) {
    model_num_groups_(num_models_) = gamma.size();
    mdl_gammas_.push_back(gamma);
    num_models_++;
  }
  /// Accessors
  void GetStateOccupancies(Vector<BaseFloat> *occs) const;
  int32 FeatureDim() const { return feature_dim_; }
  int32 PhoneSpaceDim() const { return phn_space_dim_; }
  int32 NumPdfs() const { return num_pdfs_; } // returns J2
  int32 NumGroups() const { return num_groups_; } // returns J1
  int32 NumGauss() const { return num_gaussians_; }

 private:
  /// The stats which are not tied to any state.
  /// Stats Y_{i} for phonetic-subspace projections M; Dim is [I][D][S].
  std::vector< Matrix<double> > Y_;
  /// Stats Z_{i} for speaker-subspace projections N. Dim is [I][D][T].
  std::vector< Matrix<double> > Z_;
  /// R_{i}, quadratic term for speaker subspace estimation. Dim is [I][T][T]
  std::vector< SpMatrix<double> > R_;
  /// S_{i}^{-}, scatter of adapted feature vectors x_{i}(t). Dim is [I][D][D].
  std::vector< SpMatrix<double> > S_;

  /// The SGMM state specific stats.
  /// Statistics y_{jm} for state vectors v_{jm}. dimension is [J1][#mix][S].
  std::vector< Matrix<double> > y_;
  /// Gaussian occupancies gamma_{jmi} for each substate and Gaussian index,
  /// pooled over groups. Dim is [J1][#mix][I].
  std::vector< Matrix<double> > gamma_;

  /// [SSGMM] These a_{jmi} quantities are dimensionally the same
  /// as the gamma quantities.  They're needed to estimate the v_{jm}
  /// and w_i quantities in the symmetric SGMM.  Dimension is [J1][#mix][S]
  std::vector< Matrix<double> > a_;

  /// [SSGMM] each row is one of the t_i quantities in the less-exact
  /// version of the SSGMM update for the speaker weight projections.
  /// Dimension is [I][T]
  Matrix<double> t_;

  /// [SSGMM], this is a per-speaker variable storing the a_i^{(s)}
  /// quantities that we will use in order to compute the non-speaker-
  /// specific quantities [see eqs. 53 and 54 in techreport].  Note:
  /// there is a separate variable a_s_ in class MleSgmm2SpeakerAccs,
  /// which is the same thing but for purposes of computing
  /// the speaker-vector v^{(s)}.
  Vector<double> a_s_;
  
  /// the U_i quantities from the less-exact version of the SSGMM update for the
  /// speaker weight projections.  Dimension is [I][T][T]
  std::vector<SpMatrix<double> > U_;
  
  /// Sub-state occupancies gamma_{jm}^{(c)} for each sub-state.  In the
  /// SCTM version of the SGMM, for compactness we store two separate
  /// sets of gamma statistics, one to estimate the v_{jm} quantities
  /// and one to estimate the sub-state weights c_{jm}.
  std::vector< Vector<double> > gamma_c_;
  
  /// gamma_{i}^{(s)}.  Per-speaker counts for each Gaussian. Dimension is [I]
  /// Needed for stats R_.  This can be viewed as a temporary variable; it
  /// does not form part of the stats that we eventually dump to disk.
  Vector<double> gamma_s_;

  /// chenzp   Apr 29, 2015
  /// Dimension is [I]
  Vector<double> gamma_i_;
  //std::vector< SpMatrix<double> > S_means_;
  Vector<double> model_num_groups_;
  /// [L][J1][#mix][I]
  std::vector< std::vector< Matrix<double> > > mdl_gammas_;
  /// for speaker related symmetric SGMM.  Dimension is [L][J1][#mix][S]
  std::vector< std::vector< Matrix<double> > > mdl_as_;

  double total_frames_, total_like_;

  /// Dimensionality of various subspaces
  int32 feature_dim_, phn_space_dim_, spk_space_dim_;
  int32 num_gaussians_, num_pdfs_, num_groups_;  ///< Other model specifications
  int32 num_models_; // chenzp
  bool single_gamma_; // chenzp

  BaseFloat rand_prune_;

  KALDI_DISALLOW_COPY_AND_ASSIGN(MleAmSgmm2AccsShared);
  friend class MleAmSgmm2SharedUpdater;
  friend class EbwAmSgmm2Updater;
};

/** \class MleAmSgmmUpdater
 *  Contains the functions needed to update the SGMM parameters.
 */
class MleAmSgmm2SharedUpdater {
 public:
  explicit MleAmSgmm2SharedUpdater(const MleAmSgmm2Options &options)
      : options_(options) {}
  void Reconfigure(const MleAmSgmm2Options &options) {
    options_ = options;
  }

  void Update(const MleAmSgmm2AccsShared &accs,
              const std::vector<AmSgmm2 *> &models,
              SgmmUpdateFlagsType flags);
  
 private:
  friend class UpdateWClassShared;
  friend class UpdatePhoneVectorsClass;
  friend class EbwEstimateAmSgmm2;

  ///  Compute the Q_i quantities (Eq. 64).
  static void ComputeQ(const MleAmSgmm2AccsShared &accs,
                       const std::vector<AmSgmm2 *> &models,
                       std::vector< SpMatrix<double> > *Q);

  /// Compute the S_means quantities, minus sum: (Y_i M_i^T + M_i Y_I^T).
  static void ComputeSMeans(const MleAmSgmm2AccsShared &accs,
                            const std::vector<AmSgmm2*> &models,
                            std::vector< SpMatrix<double> > *S_means);
  friend class EbwAmSgmm2Updater;

  MleAmSgmm2Options options_;
  
  // Called from UpdatePhoneVectors; updates a subset of states
  // (relates to multi-threading).
  void UpdatePhoneVectorsInternal(const MleAmSgmm2AccsShared &accs,
                                  const std::vector<SpMatrix<double> > &H,
                                  const std::vector<Matrix<double> > &log_a,
                                  AmSgmm2 *model,
                                  double *auxf_impr,
                                  int32 num_threads,
                                  int32 thread_id) const;
  
  double UpdatePhoneVectors(const MleAmSgmm2AccsShared &accs,
                            const std::vector<SpMatrix<double> > &H,
                            const std::vector<Matrix<double> > &log_a,
                            AmSgmm2 *model) const;

  double UpdateM(const MleAmSgmm2AccsShared &accs,
                 const std::vector< SpMatrix<double> > &Q,
                 const Vector<double> &gamma_i,
                 AmSgmm2 *model);

  void RenormalizeV(const MleAmSgmm2AccsShared &accs, AmSgmm2 *model,
                    const Vector<double> &gamma_i,
                    const std::vector<SpMatrix<double> > &H);
    
  double UpdateN(const MleAmSgmm2AccsShared &accs, const Vector<double> &gamma_i,
                 AmSgmm2 *model);
  void RenormalizeN(const MleAmSgmm2AccsShared &accs, const Vector<double> &gamma_i,
                    AmSgmm2 *model);
  double UpdateVars(const MleAmSgmm2AccsShared &accs,
                    const std::vector< SpMatrix<double> > &S_means,
                    const Vector<double> &gamma_i,
                    const std::vector<AmSgmm2 *> &models);
  // Update for the phonetic-subspace weight projections w_i
  double UpdateW(const MleAmSgmm2AccsShared &accs,
                 const std::vector<Matrix<double> > &log_a,
                 const Vector<double> &gamma_i,
                 const std::vector<AmSgmm2 *> &models);
  // Update for the speaker-subspace weight projections u_i [SSGMM]
  double UpdateU(const MleAmSgmm2AccsShared &accs, const Vector<double> &gamma_i,
                 AmSgmm2 *model);

  /// Called, multithreaded, inside UpdateW
  static
  void UpdateWGetStats(const MleAmSgmm2AccsShared &accs,
                       int32 l,
                       const AmSgmm2 &model,
                       const Matrix<double> &w,
                       const std::vector<Matrix<double> > &log_a,
                       Matrix<double> *F_i,
                       Matrix<double> *g_i,
                       double *tot_like,
                       int32 num_threads, 
                       int32 thread_id);
  
  double UpdateSubstateWeights(const MleAmSgmm2AccsShared &accs,
                               AmSgmm2 *model);

  static void ComputeLogA(const MleAmSgmm2AccsShared &accs,
                          std::vector<Matrix<double> > *log_a); // [SSGMM]
  
  void ComputeMPrior(AmSgmm2 *model);  // TODO(arnab): Maybe make this static?
  double MapUpdateM(const MleAmSgmm2AccsShared &accs,
                    const std::vector< SpMatrix<double> > &Q,
                    const Vector<double> &gamma_i, AmSgmm2 *model);

  KALDI_DISALLOW_COPY_AND_ASSIGN(MleAmSgmm2SharedUpdater);
  MleAmSgmm2SharedUpdater() {}  // Prevent unconfigured updater.
};


// This class, used in multi-core implementation of the updates of the "w_i"
// quantities, was previously in estimate-am-sgmm.cc, but is being moved to the
// header so it can be used in estimate-am-sgmm-ebw.cc.  It is responsible for
// computing, in parallel, the F_i and g_i quantities used in the updates of
// w_i.
class UpdateWClassShared: public MultiThreadable {
 public:
  UpdateWClassShared(const MleAmSgmm2AccsShared &accs,
               int32 l,
               const AmSgmm2 &model,
               const Matrix<double> &w,
               const std::vector<Matrix<double> > &log_a,
               Matrix<double> *F_i,
               Matrix<double> *g_i,
               double *tot_like):
      accs_(accs), l_(l), model_(model), w_(w), log_a_(log_a),
      F_i_ptr_(F_i), g_i_ptr_(g_i), tot_like_ptr_(tot_like) {
    tot_like_ = 0.0;
    F_i_.Resize(F_i->NumRows(), F_i->NumCols());
    g_i_.Resize(g_i->NumRows(), g_i->NumCols());
  }
    
  ~UpdateWClassShared() {
    F_i_ptr_->AddMat(1.0, F_i_, kNoTrans);
    g_i_ptr_->AddMat(1.0, g_i_, kNoTrans);
    *tot_like_ptr_ += tot_like_;
  }
  
  inline void operator() () {
    // Note: give them local copy of the sums we're computing,
    // which will be propagated to the total sums in the destructor.
    MleAmSgmm2SharedUpdater::UpdateWGetStats(accs_, l_, model_, w_, log_a_,
                                      &F_i_, &g_i_, &tot_like_,
                                      num_threads_, thread_id_);
  }
 private:
  const MleAmSgmm2AccsShared &accs_;
  int32 l_;
  const AmSgmm2 &model_;
  const Matrix<double> &w_;
  const std::vector<Matrix<double> > &log_a_;
  Matrix<double> *F_i_ptr_;
  Matrix<double> *g_i_ptr_;
  Matrix<double> F_i_;
  Matrix<double> g_i_;
  double *tot_like_ptr_;
  double tot_like_;
};

}  // namespace kaldi


#endif  // KALDI_SGMM_ESTIMATE_AM_SGMM_SHARED_H_
