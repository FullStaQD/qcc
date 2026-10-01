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
#include "qcc/Dialect/QVec/Transforms/ZXZ.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h"

#include <cstdint>
#include <utility>

using namespace mlir;
using qcc::qvec::normalizeAngle;

namespace qcc::magic {

#define GEN_PASS_DEF_MAGICFINALIZEZXZ
#include "qcc/Dialect/Magic/Transforms/Passes.h.inc"

static SmallVector<double> toDoubles(ArrayAttr angles) {
  return llvm::map_to_vector(angles.getAsValueRange<FloatAttr>(),
                             [](const APFloat& angle) { return angle.convertToDouble(); });
}

namespace {

/// Walks one block in order and carries the Z rotation that is still to be applied, per ion, to the right.
class Finalizer {
public:
  void run(Block& block) {
    for (Operation& op : llvm::make_early_inc_range(block)) {
      llvm::TypeSwitch<Operation*>(&op)
          .Case([&](ZXZOp zxz) { finalize(zxz); })
          .Case([&](SymZXZOp sym) { absorb(sym); })
          .Case([&](RZOp rz) { collect(rz); })
          .Case([&](SwapOp swap) { std::swap(pending[swap.getIons()[0]], pending[swap.getIons()[1]]); })
          .Case([&](MZDOp mzd) {
            // Z rotations right before a Z-basis measurement do not change its statistics.
            for (const int64_t ion : mzd.getChain().getType().getIons()) {
              pending.erase(ion);
            }
          })
          // Diagonal (commute with Z rotations) or moving ions around (the rotation moves along): nothing to do.
          .Case<InitOp, DelayOp, RecodeOp, ShuttleOp, ActiveZZOp, InterTrapZZOp>([](Operation*) {})
          .Default([&](Operation* other) { flush(other); });
    }
  }

private:
  /// zxz(z1, x, z2) after rz(r) = rz(z1 + r + z2) after sym_zxz(z1 + r, x).
  void finalize(ZXZOp zxz) {
    SmallVector<double> z;
    SmallVector<double> x;
    for (auto [ion, z1, x1, z2] :
         llvm::zip_equal(zxz.getIons(), toDoubles(zxz.getZ1()), toDoubles(zxz.getX()), toDoubles(zxz.getZ2()))) {
      const double first = z1 + pending.lookup(ion);
      z.push_back(normalizeAngle(first));
      x.push_back(normalizeAngle(x1));
      pending[ion] = first + z2;
    }
    OpBuilder builder(zxz);
    auto sym = SymZXZOp::create(builder, zxz.getLoc(), zxz.getChainIn(), zxz.getIons(), z, x);
    zxz.replaceAllUsesWith(sym.getChainOut());
    zxz.erase();
  }

  /// sym_zxz(z, x) after rz(r) = rz(r) after sym_zxz(z + r, x): the rotation stays pending.
  void absorb(SymZXZOp sym) {
    SmallVector<double> z;
    for (auto [ion, angle] : llvm::zip_equal(sym.getIons(), toDoubles(sym.getZ()))) {
      z.push_back(normalizeAngle(angle + pending.lookup(ion)));
    }
    sym.setZAttr(OpBuilder(sym).getF64ArrayAttr(z));
  }

  void collect(RZOp rz) {
    for (auto [ion, angle] : llvm::zip_equal(rz.getIons(), toDoubles(rz.getAngles()))) {
      pending[ion] += angle;
    }
    rz.replaceAllUsesWith(rz.getChainIn());
    rz.erase();
  }

  /// Applies what is pending on the chains `op` consumes, right before it: `op` is not a magic op the rotations can
  /// pass.
  void flush(Operation* op) {
    OpBuilder builder(op);
    for (OpOperand& operand : op->getOpOperands()) {
      auto type = dyn_cast<IonChainType>(operand.get().getType());
      if (!type) {
        continue;
      }
      SmallVector<int64_t> ions;
      SmallVector<double> angles;
      for (const int64_t ion : type.getIons()) {
        const double angle = normalizeAngle(pending.lookup(ion));
        pending.erase(ion);
        if (angle != 0.0) {
          ions.push_back(ion);
          angles.push_back(angle);
        }
      }
      if (!ions.empty()) {
        operand.set(RZOp::create(builder, op->getLoc(), operand.get(), ions, angles));
      }
    }
  }

  /// The Z rotation per ion (id) that is still to be applied at the current point of the walk.
  llvm::DenseMap<int64_t, double> pending;
};

struct MagicFinalizeZXZ final : impl::MagicFinalizeZXZBase<MagicFinalizeZXZ> {
  using MagicFinalizeZXZBase::MagicFinalizeZXZBase;

protected:
  void runOnOperation() override {
    // Magic ops live in single-block regions (op verifier), and a chain never leaves its block.
    SmallVector<Block*> blocks;
    getOperation().walk([&](Block* block) {
      if (llvm::any_of(*block, [](Operation& op) { return isa_and_present<MagicDialect>(op.getDialect()); })) {
        blocks.push_back(block);
      }
    });
    for (Block* block : blocks) {
      Finalizer().run(*block);
    }
  }
};

} // namespace
} // namespace qcc::magic
