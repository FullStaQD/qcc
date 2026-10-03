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
#include "llvm/ADT/SmallVector.h"

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
      verifyGarbageRecords();
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
      for (Operation* user : result.getUsers()) {
        if (!isa_and_present<MagicDialect>(user->getDialect())) {
          user->emitOpError() << "uses a chain value: only magic ops are allowed to consume chains";
          valid = false;
        }
      }
    }
  }

  /// Every result is recorded at most once. Chain values are affine, so no ion is measured twice.
  void verifyMeasurements() {
    function.walk([&](MZDOp mzd) {
      for (auto [ion, bit] : llvm::zip_equal(mzd.getChain().getType().getIons(), mzd.getBits())) {
        if (!bit.use_empty() && (!bit.hasOneUse() || !isa<aux::RecordIntOp>(*bit.user_begin()))) {
          mzd.emitOpError() << "must have its result for ion " << ion
                            << " recorded by at most one 'aux.record_int' and used nowhere else";
          valid = false;
        }
      }
    });
  }

  /// The garbage records come last, so that the results of the program are the leading bits of the output.
  void verifyGarbageRecords() {
    const MagicDialect::GarbageResultAttrHelper garbageResult(function.getContext());
    aux::RecordIntOp firstGarbage;
    function.walk([&](aux::RecordIntOp record) {
      if (garbageResult.isAttrPresent(record)) {
        if (!firstGarbage) {
          firstGarbage = record;
        }
        return;
      }
      if (firstGarbage) {
        record.emitOpError()
            .append("records a result of the program after a garbage result: the records marked '",
                    MagicDialect::GarbageResultAttrHelper::getNameStr(), "' come last")
            .attachNote(firstGarbage.getLoc())
            .append("the first garbage result is recorded here");
        valid = false;
      }
    });
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
