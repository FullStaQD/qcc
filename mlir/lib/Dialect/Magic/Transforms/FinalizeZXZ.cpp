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

#include "mlir/Dialect/Func/IR/FuncOps.h"
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

/// Walks one block in order and carries the pending Z rotations forward (per ion).
///
/// The rules below are operator products: in `a * b` the right factor `b` acts first. The leading `rz` of a result
/// is what stays pending.
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
  /// zxz(z1, x, z2) * rz(r) becomes rz(z1 + r + z2) * sym_zxz(z1 + r, x).
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

  /// sym_zxz(z, x) * rz(r) becomes rz(r) * sym_zxz(z + r, x).
  void absorb(SymZXZOp sym) {
    SmallVector<double> z;
    for (auto [ion, angle] : llvm::zip_equal(sym.getIons(), toDoubles(sym.getZ()))) {
      z.push_back(normalizeAngle(angle + pending.lookup(ion)));
    }
    sym.setZAttr(OpBuilder(sym).getF64ArrayAttr(z));
  }

  /// rz(a) * rz(r) becomes rz(a + r).
  void collect(RZOp rz) {
    for (auto [ion, angle] : llvm::zip_equal(rz.getIons(), toDoubles(rz.getAngles()))) {
      pending[ion] += angle;
    }
    rz.replaceAllUsesWith(rz.getChainIn());
    rz.erase();
  }

  /// op * rz(r) stays as it is, for an `op` the rotation cannot pass: rz(r) is emitted in front of it on the chains it
  /// consumes and nothing stays pending.
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
    func::FuncOp func = getOperation();
    if (!func.isExternal()) {
      Finalizer().run(func.front());
    }
  }
};

} // namespace
} // namespace qcc::magic
