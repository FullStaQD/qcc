// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/IR/Magic.h"
#include "qcc/Dialect/Magic/Transforms/Passes.h" // IWYU pragma: keep

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep

using namespace mlir;

namespace qcc::magic {

#define GEN_PASS_DEF_MAGICVERIFY
#include "qcc/Dialect/Magic/Transforms/Passes.h.inc"

namespace {

struct MagicVerify final : impl::MagicVerifyBase<MagicVerify> {
  using MagicVerifyBase::MagicVerifyBase;

protected:
  void runOnOperation() override {
    // One `magic.init` creates every trap of the device, so a second one would describe a second program. Its
    // cross-trap checks (distinct trap ids, distinct ion ids) only cover the whole program because of this.
    InitOp firstInit;
    const WalkResult walk = getOperation().walk([&](InitOp init) {
      if (!firstInit) {
        firstInit = init;
        return WalkResult::advance();
      }
      init.emitError()
          .append("a program has at most one 'magic.init': one op creates the chains of all traps")
          .attachNote(firstInit.getLoc())
          .append("the program's 'magic.init' is here");
      return WalkResult::interrupt();
    });

    if (walk.wasInterrupted()) {
      return signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc::magic
