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
#include "mlir/Interfaces/FunctionInterfaces.h"
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
    // A program is one function, and it creates the chains of every trap once. The op verifier guarantees that every
    // magic op is inside a function, so walking the functions reaches them all.
    bool duplicate = false;

    getOperation().walk([&](FunctionOpInterface function) {
      InitOp firstInit;
      function.walk([&](InitOp init) {
        if (!firstInit) {
          firstInit = init;
          return;
        }
        init.emitError()
            .append("a program has at most one 'magic.init': one op creates the chains of all traps")
            .attachNote(firstInit.getLoc())
            .append("the program's 'magic.init' is here");
        duplicate = true;
      });
    });

    if (duplicate) {
      return signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc::magic
