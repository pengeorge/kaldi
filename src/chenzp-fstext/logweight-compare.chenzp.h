/*
 * =====================================================================================
 *
 *       Filename:  logweight-compare.chenzp.h
 *
 *    Description:  
 *
 *        Version:  1.0
 *        Created:  2014年03月31日 19时14分03秒
 *       Revision:  none
 *       Compiler:  gcc
 *
 *         Author:  Zhipeng Chen 
 *   Organization:  
 *
 * =====================================================================================
 */

#ifndef KALDI_FSTEXT_LOGWEIGHT_COMPARE_H_
#define KALDI_FSTEXT_LOGWEIGHT_COMPARE_H_

#include "fst/fstlib.h"
#include "base/kaldi-common.h"

namespace fst {
inline int Compare(const LogWeight &w1,
                   const LogWeight &w2) {
  float f1 = w1.Value(), f2 = w2.Value();
  if (f1 == f2) return 0;
  else if (f1 > f2) return -1;
  else return 1;
}

}

#endif
