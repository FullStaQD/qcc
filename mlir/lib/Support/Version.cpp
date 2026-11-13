// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Support/Version.h"

#include "qcc/Config/Config.h"

#include "VCSRevision.h"

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"

namespace qcc {

void printVersion(llvm::raw_ostream& os) {
  os << QCC_VERSION;
#ifdef QCC_REVISION
  os << " (" << llvm::StringRef(QCC_REVISION).take_front(7) << ")";
#endif
  os << "\n";
}

} // namespace qcc
