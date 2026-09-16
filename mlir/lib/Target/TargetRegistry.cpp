// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Target/TargetRegistry.h"

#include "qcc/Config/Config.h"
#include "qcc/Target/QIR/QIRTarget.h"

#if QCC_ENABLE_HISEPQ
#include "qcc/Target/HiSEPQ/HiSEPQTarget.h"
#endif

#include <vector>

namespace qcc {

llvm::ArrayRef<Target> getTargets() {
  static const std::vector<Target> targets = {
      {.name = "qir",
       .description = "QIR (LLVM-based) target",
       .addLoweringPasses = [](mlir::PassManager& pm) { addLoweringPassesQIR(pm); }},
#if QCC_ENABLE_HISEPQ
      {.name = "hisepq",
       .description = "HiSEP-Q QISA target (RISC-V based)",
       .addLoweringPasses = [](mlir::PassManager& pm) { addLoweringPassesHiSEPQ(pm); },
       .emitNative = [](llvm::Module& module, llvm::raw_pwrite_stream& os,
                        const NativeCodegenOptions& options) { return emitNativeHiSEPQ(module, os, options); }},
#endif
  };

  return targets;
}

const Target* lookupTarget(llvm::StringRef name) {
  for (const Target& target : getTargets()) {
    if (target.name == name) {
      return &target;
    }
  }
  return nullptr;
}

} // namespace qcc
