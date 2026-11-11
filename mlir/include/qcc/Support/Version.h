// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "llvm/Support/raw_ostream.h"

namespace qcc {

/// Prints the version and, if known (see QCC_APPEND_VC_REV), the commit this build is from, e.g.
/// "0.1.0-alpha.1 (abc1234)".
///
/// Tools register it with llvm::cl::SetVersionPrinter, so that --version prints it instead of LLVM's version.
void printVersion(llvm::raw_ostream& os);

} // namespace qcc
