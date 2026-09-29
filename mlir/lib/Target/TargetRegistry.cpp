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

#include <array>
#include <vector>

namespace qcc {

static constexpr auto qirCpus =
    std::to_array<Cpu>({{.name = "generic", .description = "Any QIR runtime", .features = {}}});
static constexpr auto noTargetCpus =
    std::to_array<Cpu>({{.name = "generic", .description = "No control hardware", .features = {}}});

llvm::ArrayRef<Target> getTargets() {
  static const std::vector<Target> targets = {
      {.name = "qir",
       .description = "QIR (LLVM-based) target",
       .cpus = qirCpus,
       .addLoweringPasses =
           [](mlir::PassManager& pm, llvm::ArrayRef<FeatureFlag> /*features*/) {
             addLoweringPassesQIR(pm);
             return mlir::success();
           },
       .lowersToLLVM = true},
#if QCC_ENABLE_HISEPQ
      {.name = "hisepq",
       .description = "HiSEP-Q QISA target (RISC-V based)",
       .features = hisepqFeatures,
       .cpus = hisepqCpus,
       .addLoweringPasses = [](mlir::PassManager& pm,
                               llvm::ArrayRef<FeatureFlag> features) { return addLoweringPassesHiSEPQ(pm, features); },
       .emitNative =
           [](llvm::Module& module, llvm::raw_pwrite_stream& os, const NativeCodegenOptions& options,
              llvm::ArrayRef<FeatureFlag> features) { return emitNativeHiSEPQ(module, os, options, features); },
       .lowersToLLVM = true},
#endif
      {.name = noTargetName,
       .description = "No QISA: no lowering for control electronics and no code generation",
       .cpus = noTargetCpus,
       .addLoweringPasses = [](mlir::PassManager& /*pm*/,
                               llvm::ArrayRef<FeatureFlag> /*features*/) { return mlir::success(); }},
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

mlir::FailureOr<llvm::SmallVector<FeatureFlag>> parseFeatures(const Target& target, llvm::StringRef mcpu,
                                                              llvm::StringRef mattr) {
  const Cpu* cpu = llvm::find_if(target.cpus, [&](const Cpu& candidate) { return candidate.name == mcpu; });
  if (cpu == target.cpus.end()) {
    llvm::errs() << "error: unknown CPU '" << mcpu << "' for --target=" << target.name << "\n";
    return mlir::failure();
  }

  llvm::SmallVector<FeatureFlag> flags;
  for (const llvm::StringRef name : cpu->features) {
    flags.push_back({.name = name, .enable = true});
  }

  llvm::SmallVector<llvm::StringRef> entries;
  mattr.split(entries, ',', /*MaxSplit=*/-1, /*KeepEmpty=*/false);
  for (const llvm::StringRef entry : entries) {
    FeatureFlag flag{.name = entry, .enable = !entry.starts_with("-")};
    if (entry.starts_with("+") || entry.starts_with("-")) {
      flag.name = entry.drop_front();
    }
    if (llvm::none_of(target.features, [&](const Feature& feature) { return feature.name == flag.name; })) {
      llvm::errs() << "error: unknown feature '" << entry << "' for --target=" << target.name << "\n";
      return mlir::failure();
    }
    flags.push_back(flag);
  }
  return flags;
}

} // namespace qcc
