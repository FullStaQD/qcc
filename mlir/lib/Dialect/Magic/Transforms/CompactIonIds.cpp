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

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/ADT/TypeSwitch.h"

#include <cstdint>
#include <iterator>

using namespace mlir;

namespace qcc::magic {

#define GEN_PASS_DEF_MAGICCOMPACTIONIDS
#include "qcc/Dialect/Magic/Transforms/Passes.h.inc"

namespace {

/// Maps the ion ids of a program to 0..N-1.
class IonRenumbering {
public:
  /// Numbers the ions in the order `init` lists them: trap by trap, front to back.
  explicit IonRenumbering(InitOp init) {
    for (Value chain : init.getChains()) {
      for (const int64_t ion : cast<IonChainType>(chain.getType()).getIons()) {
        newIds.try_emplace(ion, std::ssize(newIds));
      }
    }
  }

  /// Whether no ion changes its id.
  [[nodiscard]] bool isIdentity() const {
    return llvm::all_of(newIds, [](const auto& entry) { return entry.first == entry.second; });
  }

  [[nodiscard]] int64_t map(int64_t ion) const { return newIds.lookup(ion); }

  [[nodiscard]] SmallVector<int64_t> map(ArrayRef<int64_t> ions) const {
    return llvm::map_to_vector(ions, [&](int64_t ion) { return map(ion); });
  }

  [[nodiscard]] IonChainType map(IonChainType chain) const {
    const SmallVector<IonSlot> slots = llvm::map_to_vector(
        chain.getSlots(), [&](const IonSlot& slot) { return IonSlot{.ion = map(slot.ion), .active = slot.active}; });
    return IonChainType::get(chain.getContext(), chain.getTrap(), slots);
  }

private:
  llvm::DenseMap<int64_t, int64_t> newIds;
};

struct MagicCompactIonIds final : impl::MagicCompactIonIdsBase<MagicCompactIonIds> {
  using MagicCompactIonIdsBase::MagicCompactIonIdsBase;

protected:
  void runOnOperation() override {
    func::FuncOp func = getOperation();

    // Every ion of a program comes from its `magic.init`.
    InitOp init;
    bool unique = true;
    func.walk([&](InitOp op) {
      if (init) {
        op.emitOpError() << "is the second 'magic.init' of the program: expected at most one to number the ions by";
        unique = false;
      }
      init = op;
    });
    if (!unique) {
      return signalPassFailure();
    }
    if (!init) {
      return;
    }

    const IonRenumbering renumbering(init);
    if (renumbering.isIdentity()) {
      return;
    }

    func.walk([&](Operation* op) {
      for (Value result : op->getResults()) {
        if (auto chain = dyn_cast<IonChainType>(result.getType())) {
          result.setType(renumbering.map(chain));
        }
      }
      // The ops that name ions. The new ids keep the order of the old ones, so sorted lists stay sorted.
      llvm::TypeSwitch<Operation*>(op).Case<ZXZOp, RZOp, SymZXZOp, SwapOp, InterTrapZZOp>(
          [&](auto gate) { gate.setIons(renumbering.map(gate.getIons())); });
    });
  }
};

} // namespace
} // namespace qcc::magic
