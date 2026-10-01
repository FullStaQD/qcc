// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/Device/MagicDevice.h"
#include "qcc/Dialect/Magic/IR/Magic.h"
#include "qcc/Dialect/Magic/Transforms/Passes.h" // IWYU pragma: keep

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <numbers>

using namespace mlir;

namespace qcc::magic {

#define GEN_PASS_DEF_MAGICCOMPILEACTIVEZZTRIVIALLY
#include "qcc/Dialect/Magic/Transforms/Passes.h.inc"

/// Replaces `op` by one recode / delay / recode sequence per nonzero pair of its matrix.
static LogicalResult compileTrivially(ActiveZZOp op, const MagicDevice& device) {
  const IonChainType type = op.getChainIn().getType();
  if (type.getTrap() >= device.numTraps()) {
    return op.emitOpError() << "acts on trap " << type.getTrap() << ", but the device has " << device.numTraps()
                            << " traps";
  }
  const auto trap = static_cast<TrapId>(type.getTrap());
  if (type.getNumIons() > device.capacity(trap)) {
    return op.emitOpError() << "acts on " << type.getNumIons() << " ions, but trap " << trap << " holds at most "
                            << device.capacity(trap);
  }

  const SmallVector<int64_t> active = type.getActiveIons();
  const SmallVector<double> angles(op.getAngles().getValues<double>());
  const size_t numActive = active.size();

  OpBuilder builder(op);
  const Location loc = op.getLoc();
  Value chain = op.getChainIn();

  // The X sandwich for negative angles: X_i (Z_i Z_j) X_i = -Z_i Z_j.
  auto flip = [&](int64_t ion) { chain = SymZXZOp::create(builder, loc, chain, {ion}, {0.0}, {std::numbers::pi}); };

  for (size_t a = 0; a < numActive; ++a) {
    for (size_t b = a + 1; b < numActive; ++b) {
      const double angle = angles[(a * numActive) + b];
      if (angle == 0.0) {
        continue;
      }
      const int64_t ionA = active[a];
      const int64_t ionB = active[b];

      // The delay acts with the coupling for the ions present, active or not, indexed by chain position.
      const double coupling = device.coupling(trap, type.getNumIons())(type.getPosition(ionA), type.getPosition(ionB));
      assert(coupling > 0.0 && "coupling between any ions must be strictly positive");

      // Every other active ion must not take part.
      SmallVector<int64_t> others;
      llvm::copy_if(active, std::back_inserter(others), [&](int64_t ion) { return ion != ionA && ion != ionB; });
      if (!others.empty()) {
        chain = RecodeOp::create(builder, loc, chain, others);
      }

      // A delay of t seconds is an `active_zz` with angles t*J.
      const bool negative = angle < 0.0;
      const double seconds = std::abs(angle) / coupling;
      if (negative) {
        flip(ionA);
      }
      chain = DelayOp::create(builder, loc, chain.getType(), chain,
                              builder.getI64IntegerAttr(device.microsecondsToTicks(seconds * 1e6)));
      if (negative) {
        flip(ionA);
      }

      if (!others.empty()) {
        chain = RecodeOp::create(builder, loc, chain, others);
      }
    }
  }

  op.getChainOut().replaceAllUsesWith(chain);
  op.erase();
  return success();
}

namespace {

struct MagicCompileActiveZZTrivially final : impl::MagicCompileActiveZZTriviallyBase<MagicCompileActiveZZTrivially> {
  using MagicCompileActiveZZTriviallyBase::MagicCompileActiveZZTriviallyBase;

protected:
  void runOnOperation() override {
    SmallVector<ActiveZZOp> ops;
    getOperation().walk([&](ActiveZZOp op) { ops.push_back(op); });
    if (ops.empty()) {
      return;
    }

    const FailureOr<MagicDevice> device = MagicDevice::fromParentModule(getOperation());
    if (failed(device)) {
      return signalPassFailure();
    }
    for (ActiveZZOp op : ops) {
      if (failed(compileTrivially(op, *device))) {
        return signalPassFailure();
      }
    }
  }
};

} // namespace
} // namespace qcc::magic
