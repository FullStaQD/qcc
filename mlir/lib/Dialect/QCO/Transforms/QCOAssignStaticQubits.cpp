// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QCO/Transforms/Passes.h" // IWYU pragma: keep

#include "mqt/Dialect/QCO/IR/QCODialect.h" // IWYU pragma: keep
#include "mqt/Dialect/QCO/IR/QCOOps.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Support/LLVM.h"

#include <cstdint>

namespace qcc {

#define GEN_PASS_DEF_QCOASSIGNSTATICQUBITS
#include "qcc/Dialect/QCO/Transforms/Passes.h.inc"

using namespace mlir;

namespace {

struct QCOAssignStaticQubits final : impl::QCOAssignStaticQubitsBase<QCOAssignStaticQubits> {
  using QCOAssignStaticQubitsBase::QCOAssignStaticQubitsBase;

protected:
  void runOnOperation() override {
    ModuleOp moduleOp = getOperation();

    // Module-wide and monotonic: two functions never share an index, so the
    // result stays correct whether or not the callees have been inlined.
    std::uint64_t nextIndex = 0;
    moduleOp.walk([&](qco::AllocOp allocOp) {
      OpBuilder builder(allocOp);
      auto staticOp = qco::StaticOp::create(builder, allocOp.getLoc(), nextIndex++);
      allocOp.getResult().replaceAllUsesWith(staticOp.getQubit());
      allocOp.erase();
    });
  }
};

} // namespace
} // namespace qcc
