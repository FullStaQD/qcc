// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/Magic/Device/MagicDevice.h"
#include "qcc/Dialect/Magic/IR/Magic.h"
#include "qcc/Dialect/Magic/Transforms/Passes.h" // IWYU pragma: keep
#include "qcc/Dialect/Magic/Transforms/Timing.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Sequence.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

using namespace mlir;

namespace qcc::magic {

#define GEN_PASS_DEF_MAGICVERIFY
#include "qcc/Dialect/Magic/Transforms/Passes.h.inc"

namespace {

/// Checks the whole-program rules of one program (function). Emits a diagnostic for every violation.
class ProgramVerifier {
public:
  explicit ProgramVerifier(func::FuncOp function) : function(function) {}

  LogicalResult verify() {
    function.walk([&](Operation* op) { verifyOp(op); });
    function.walk([&](InitOp init) {
      if (!firstInit) {
        firstInit = init;
        verifyInit(init);
        return;
      }
      init.emitError()
          .append("a program has at most one 'magic.init': one op creates the chains of all traps")
          .attachNote(firstInit.getLoc())
          .append("the program's 'magic.init' is here");
      valid = false;
    });
    if (firstInit) {
      verifyMeasurements();
      verifyTiming();
    }
    return success(valid);
  }

private:
  /// The rules for a single op that need the rest of the program.
  void verifyOp(Operation* op) {
    if (isa_and_present<MagicDialect>(op->getDialect()) && !op->hasTrait<Native>()) {
      op->emitOpError() << "is not native to the device and must be lowered before export";
      valid = false;
    }
    if (auto record = dyn_cast<aux::RecordIntOp>(op); record && !record.getValue().getDefiningOp<MZDOp>()) {
      record.emitOpError() << "records a value that is not a 'magic.mzd' result; a program records its measurements";
      valid = false;
    }
    if (isa<aux::RecordMemRefOp>(op)) {
      op->emitOpError() << "is not supported: a program records its measurements one by one";
      valid = false;
    }

    for (Value result : op->getResults()) {
      auto chain = dyn_cast<IonChainType>(result.getType());
      if (!chain) {
        continue;
      }
      if (result.use_empty() && chain.getNumIons() > 0) {
        op->emitOpError() << "produces a chain of trap " << chain.getTrap()
                          << " that is never measured: every chain ends in 'magic.mzd'";
        valid = false;
      }
      for (Operation* user : result.getUsers()) {
        if (!isa_and_present<MagicDialect>(user->getDialect())) {
          user->emitOpError() << "uses a chain value: only magic ops are allowed to consume chains";
          valid = false;
        }
      }
    }
  }

  /// The ion ids are 0 .. n - 1, assigned trap by trap in chain order.
  void verifyInit(InitOp init) {
    // `magic.init` lists its traps in increasing order.
    for (Value chainValue : init.getChains()) {
      const auto chain = cast<IonChainType>(chainValue.getType());
      const SmallVector<int64_t> expected = llvm::to_vector(llvm::seq<int64_t>(numIons, numIons + chain.getNumIons()));
      if (chain.getIons() != expected) {
        auto diag = init.emitOpError() << "expected trap " << chain.getTrap() << " to start with the ions [";
        llvm::interleaveComma(expected, diag);
        diag << "], got " << chain << ": ion ids are assigned trap by trap";
        valid = false;
      }
      numIons += chain.getNumIons();
    }
  }

  /// Every ion is measured once, every result is recorded once.
  void verifyMeasurements() {
    SmallVector<unsigned> measured(numIons, 0);
    function.walk([&](MZDOp mzd) {
      for (auto [ion, bit] : llvm::zip_equal(mzd.getChain().getType().getIons(), mzd.getBits())) {
        if (ion >= 0 && std::cmp_less(ion, measured.size())) {
          ++measured[ion];
        }
        if (!bit.hasOneUse() || !isa<aux::RecordIntOp>(*bit.user_begin())) {
          mzd.emitOpError() << "must have its result for ion " << ion
                            << " recorded by exactly one 'aux.record_int' and used nowhere else";
          valid = false;
        }
      }
    });
    for (auto [ion, count] : llvm::enumerate(measured)) {
      if (count != 1) {
        firstInit.emitOpError() << "starts a program that measures ion " << ion << " " << count
                                << " times: every ion is measured exactly once";
        valid = false;
      }
    }
  }

  /// The two traps of every shuttle have spent the same time.
  void verifyTiming() {
    forEachUnbalancedShuttle(function.front(), [&](ShuttleOp shuttle, Ticks fromTicks, Ticks toTicks) {
      shuttle.emitOpError() << "has unbalanced timing: trap " << shuttle.getFromIn().getType().getTrap()
                            << " has spent " << fromTicks << " ticks, but trap "
                            << shuttle.getToIn().getType().getTrap() << " " << toTicks
                            << "; the two traps of a shuttle must have spent the same time";
      valid = false;
    });
  }

  func::FuncOp function;
  InitOp firstInit;
  /// The number of ions `firstInit` creates.
  int64_t numIons = 0;
  bool valid = true;
};

struct MagicVerify final : impl::MagicVerifyBase<MagicVerify> {
  using MagicVerifyBase::MagicVerifyBase;

protected:
  void runOnOperation() override {
    // A program is one function. Functions without magic ops are none of our business and need no device.
    func::FuncOp function = getOperation();
    const WalkResult result = function.walk([](Operation* op) {
      return isa_and_present<MagicDialect>(op->getDialect()) ? WalkResult::interrupt() : WalkResult::advance();
    });
    if (!result.wasInterrupted()) {
      return;
    }

    // The lookup checks that the program fits the device: the traps exist and no chain exceeds its capacity.
    if (failed(MagicDevice::fromParentModuleChecked(function)) || failed(ProgramVerifier(function).verify())) {
      return signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc::magic
