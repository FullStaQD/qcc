// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// HiSEP-Q backend implementation. This is the ONLY place in the project allowed
// to depend on the HiSEP-Q LLVM fork (its headers and libraries); it is compiled
// only when QCC_ENABLE_HISEP_Q is enabled.
//
// TODO: For now this is a stub, add actual pipeline ASAP.
//
// ===----------------------------------------------------------------------===//

#include "qcc/Target/HiSEPQ/HiSEPQTarget.h"

namespace qcc {

void addLoweringPassesHiSEPQ(mlir::PassManager& /*pm*/) {
  // Intentionally empty until the HiSEP-Q pipeline lands.
}

} // namespace qcc
