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

#include <cstdint>
#include <utility>

using namespace mlir;

namespace qcc::magic {

#define GEN_PASS_DEF_MAGICVERIFY
#include "qcc/Dialect/Magic/Transforms/Passes.h.inc"

namespace {

/// Checks one program (function) against the device. Emits a diagnostic for every violation.
class ProgramVerifier {
public:
  ProgramVerifier(func::FuncOp function, MagicDevice device) : function(function), device(std::move(device)) {}

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
  /// The rules for a single op that need the device or the rest of the program.
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
      if (chain.getTrap() >= device.numTraps()) {
        op->emitOpError() << "produces a chain of trap " << chain.getTrap() << ", but the device has "
                          << device.numTraps() << " traps";
        valid = false;
        continue;
      }
      const IonCount capacity = device.capacity(static_cast<TrapId>(chain.getTrap()));
      if (chain.getNumIons() > capacity) {
        op->emitOpError() << "puts " << chain.getNumIons() << " ions into trap " << chain.getTrap()
                          << ", which holds at most " << capacity;
        valid = false;
      }
      if (result.use_empty() && chain.getNumIons() > 0) {
        op->emitOpError() << "produces a chain of trap " << chain.getTrap()
                          << " that is never measured: every chain ends in 'magic.mzd'";
        valid = false;
      }
      for (Operation* user : result.getUsers()) {
        if (!isa_and_present<MagicDialect>(user->getDialect())) {
          user->emitOpError() << "uses a chain value: chains end in 'magic.mzd'";
          valid = false;
        }
      }
    }
  }

  /// Identity placement: trap 0 holds the ions 0 .. o0 - 1, trap 1 the next o1, and so on, all active.
  void verifyInit(InitOp init) {
    SmallVector<bool> initialized(device.numTraps(), false);
    for (Value chainValue : init.getChains()) {
      auto chain = cast<IonChainType>(chainValue.getType());
      if (chain.getTrap() >= device.numTraps()) {
        continue; // reported by verifyOp
      }
      const auto trap = static_cast<TrapId>(chain.getTrap());
      initialized[trap] = true;
      int64_t first = 0;
      for (TrapId previous = 0; previous < trap; ++previous) {
        first += device.initialOccupancy(previous);
      }
      const SmallVector<int64_t> expected =
          llvm::to_vector(llvm::seq<int64_t>(first, first + device.initialOccupancy(trap)));
      if (chain.getIons() != expected) {
        auto diag = init.emitOpError() << "expected trap " << trap << " to start with the ions [";
        llvm::interleaveComma(expected, diag);
        diag << "] of the device, got " << chain;
        valid = false;
      }
    }
    for (TrapId trap = 0; trap < device.numTraps(); ++trap) {
      if (!initialized[trap] && device.initialOccupancy(trap) > 0) {
        init.emitOpError() << "does not create trap " << trap << ", which holds " << device.initialOccupancy(trap)
                           << " ions";
        valid = false;
      }
    }
  }

  /// Every ion is measured once, every result is recorded once.
  void verifyMeasurements() {
    SmallVector<unsigned> measured(device.numIons(), 0);
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
                                << " times: every ion of the device is measured exactly once";
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
  MagicDevice device;
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

    const FailureOr<MagicDevice> device = MagicDevice::fromParentModule(function);
    if (failed(device) || failed(ProgramVerifier(function, *device).verify())) {
      return signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc::magic
