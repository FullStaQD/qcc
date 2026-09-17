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

#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/raw_ostream.h"

#include <vector>

namespace qcc {

llvm::ArrayRef<Target> getTargets() {
  static const std::vector<Target> targets = {
      {.name = "qir",
       .description = "QIR (LLVM-based) target",
       .addLoweringPasses = [](mlir::PassManager& pm,
                               llvm::ArrayRef<llvm::StringRef> /*features*/) { addLoweringPassesQIR(pm); }},
#if QCC_ENABLE_HISEPQ
      {.name = "hisepq",
       .description = "HiSEP-Q QISA target (RISC-V based)",
       .features = hisepqFeatures,
       .addLoweringPasses = [](mlir::PassManager& pm,
                               llvm::ArrayRef<llvm::StringRef> features) { addLoweringPassesHiSEPQ(pm, features); },
       .emitNative =
           [](llvm::Module& module, llvm::raw_pwrite_stream& os, const NativeCodegenOptions& options,
              llvm::ArrayRef<llvm::StringRef> features) { return emitNativeHiSEPQ(module, os, options, features); }},
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

mlir::FailureOr<llvm::SmallVector<llvm::StringRef>> parseFeatures(const Target& target, llvm::StringRef mattr) {
  llvm::SmallVector<llvm::StringRef> flags;
  mattr.split(flags, ',', /*MaxSplit=*/-1, /*KeepEmpty=*/false);

  llvm::SmallVector<llvm::StringRef> names;
  for (const llvm::StringRef flag : flags) {
    const llvm::StringRef name = flag.starts_with("+") ? flag.drop_front() : "";
    if (llvm::none_of(target.features, [&](const Feature& feature) { return feature.name == name; })) {
      llvm::errs() << "error: unknown feature '" << flag << "' for --target=" << target.name << "\n";
      return mlir::failure();
    }
    names.push_back(name);
  }
  return names;
}

} // namespace qcc
