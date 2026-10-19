// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/Aux_/AuxUnpackRecordInt.h" // IWYU pragma: keep

#include "qcc/Dialect/Aux_/IR/Aux_.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <map>

namespace qcc {

#define GEN_PASS_DEF_AUXUNPACKRECORDINT
#include "qcc/Conversion/Aux_/AuxUnpackRecordInt.h.inc"

using namespace mlir;

/// Adds the bits packed into `value` to `bits`, keyed by their position. Fails unless `value` is an `arith.ori` tree
/// of `arith.shli(arith.extui(%bit), k)` / `arith.extui(%bit)` with an `i1` `%bit` and distinct constant `k`.
static LogicalResult collectBits(Value value, std::map<int64_t, Value>& bits) {
  if (auto ori = value.getDefiningOp<arith::OrIOp>()) {
    return success(succeeded(collectBits(ori.getLhs(), bits)) && succeeded(collectBits(ori.getRhs(), bits)));
  }

  int64_t position = 0;
  if (auto shli = value.getDefiningOp<arith::ShLIOp>()) {
    APInt shift;
    // A shift by the bit width or more is poison.
    if (!matchPattern(shli.getRhs(), m_ConstantInt(&shift)) || shift.uge(shift.getBitWidth())) {
      return failure();
    }
    position = static_cast<int64_t>(shift.getZExtValue());
    value = shli.getLhs();
  }

  auto extui = value.getDefiningOp<arith::ExtUIOp>();
  if (!extui || !extui.getIn().getType().isInteger(1)) {
    return failure();
  }
  return success(bits.emplace(position, extui.getIn()).second);
}

/// Erases `op` and, transitively, the operand definitions it leaves without users.
static void eraseDeadTree(Operation* op) {
  SmallVector<Operation*> worklist{op};
  // An op is queued once per user that is erased, so it may come up again after it is gone.
  SmallPtrSet<Operation*, 8> erased;
  while (!worklist.empty()) {
    Operation* current = worklist.pop_back_val();
    if (erased.contains(current) || !isOpTriviallyDead(current)) {
      continue;
    }
    for (Value operand : current->getOperands()) {
      if (Operation* definition = operand.getDefiningOp()) {
        worklist.push_back(definition);
      }
    }
    erased.insert(current);
    current->erase();
  }
}

/// Replaces `record` by one record per packed bit if it records a packed bit string.
static void unpack(aux::RecordIntOp record) {
  std::map<int64_t, Value> bits;
  if (failed(collectBits(record.getValue(), bits))) {
    return;
  }
  // The positions are exactly 0 .. n-1, so the records keep the meaning of the bits.
  if (bits.begin()->first != 0 || bits.rbegin()->first != static_cast<int64_t>(bits.size()) - 1) {
    return;
  }

  OpBuilder builder(record);
  for (const auto& [_, bit] : bits) {
    aux::RecordIntOp::create(builder, record.getLoc(), bit);
  }
  Operation* root = record.getValue().getDefiningOp();
  record.erase();
  eraseDeadTree(root);
}

namespace {

struct AuxUnpackRecordInt final : impl::AuxUnpackRecordIntBase<AuxUnpackRecordInt> {
  using AuxUnpackRecordIntBase::AuxUnpackRecordIntBase;

protected:
  void runOnOperation() override {
    SmallVector<aux::RecordIntOp> records;
    getOperation()->walk([&](aux::RecordIntOp record) { records.push_back(record); });
    for (aux::RecordIntOp record : records) {
      unpack(record);
    }
  }
};

} // namespace
} // namespace qcc
