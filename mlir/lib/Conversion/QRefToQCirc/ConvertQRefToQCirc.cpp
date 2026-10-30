// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// `convert-qref-to-qcirc` walks each function once, in order. It keeps the current `!qcc.qubit` value of every static
// qubit: an op on qubit N consumes the current value of N, and its result becomes the new current value. An `scf.if`
// with qubit ops inside becomes a `qcf.if` in the same walk, whose regions start from their bindings.
//
// We do not use the dialect conversion framework: a reference does not map to one value but to a new value after every
// op on its qubit, which is no type conversion.
//
//===----------------------------------------------------------------------===//

#include "qcc/Conversion/QRefToQCirc/QRefToQCirc.h" // IWYU pragma: keep
#include "qcc/Dialect/QCF/IR/QCF.h"
#include "qcc/Dialect/QCirc/IR/QCirc.h"
#include "qcc/Dialect/QRef/IR/QRef.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h"

#include <cassert>
#include <cstdint>
#include <optional>

namespace qcc {

#define GEN_PASS_DEF_CONVERTQREFTOQCIRC
#include "qcc/Conversion/QRefToQCirc/QRefToQCirc.h.inc"

using namespace mlir;

/// Whether `type` is a qubit reference or holds them, e.g. an array of qubits.
static bool holdsQubitRefs(Type type) {
  if (auto shaped = dyn_cast<ShapedType>(type)) {
    type = shaped.getElementType();
  }
  return isa<QubitRefType>(type);
}

/// Whether an operand, a result or a block argument of a region of `op` holds qubit references.
static bool holdsQubitRefs(Operation* op) {
  auto holds = [](Value value) { return holdsQubitRefs(value.getType()); };
  return llvm::any_of(op->getOperands(), holds) || llvm::any_of(op->getResults(), holds) ||
         llvm::any_of(op->getRegions(), [&](Region& region) {
           return llvm::any_of(region, [&](Block& block) { return llvm::any_of(block.getArguments(), holds); });
         });
}

/// Whether `op` is a qref op: a gate, a measurement or a reset.
static bool isQRefOp(Operation* op) { return isa<qref::SingleOp, qref::PairOp, qref::MeasureOp, qref::ResetOp>(op); }

/// The index of the static qubit that `qubit` names. The preconditions ensure that it comes from `qcc.static_ref`.
static int64_t getIndex(Value qubit) {
  const std::optional<int64_t> index = getStaticRefIndex(qubit);
  assert(index && "every qubit comes from 'qcc.static_ref'");
  return *index;
}

/// The indices of the static qubits that the qref ops inside `op` act on, at any depth, in increasing order.
static SmallVector<int64_t> getActedOnIndices(Operation* op) {
  SmallVector<int64_t> indices;
  op->walk([&](Operation* nested) {
    if (!isQRefOp(nested)) {
      return;
    }
    for (Value operand : nested->getOperands()) {
      if (const std::optional<int64_t> index = getStaticRefIndex(operand)) {
        indices.push_back(*index);
      }
    }
  });
  llvm::sort(indices);
  indices.erase(llvm::unique(indices), indices.end());
  return indices;
}

namespace {

class FunctionConverter {
public:
  explicit FunctionConverter(func::FuncOp func) : func(func) {}

  LogicalResult run() {
    if (failed(checkPreconditions())) {
      return failure();
    }

    // The static qubits of the function: those that any `qcc.static_ref` names, whether acted on or not.
    SmallVector<int64_t> indices;
    func.walk([&](StaticRefOp staticRef) { llvm::append_range(indices, staticRef.getIndices()); });
    llvm::sort(indices);
    indices.erase(llvm::unique(indices), indices.end());

    Block& body = func.getBody().front();
    auto builder = OpBuilder::atBlockBegin(&body);
    auto staticOp = StaticOp::create(builder, func.getLoc(), indices);
    QubitMap qubits;
    for (auto [index, qubit] : llvm::zip_equal(indices, staticOp.getQubits())) {
      qubits[index] = qubit;
    }
    convertBlock(body, qubits);

    // Every use was a qref op, so the references are dead now.
    func.walk([](StaticRefOp staticRef) {
      assert(staticRef->use_empty() && "only qref ops use qubit references");
      staticRef.erase();
    });
    return success();
  }

private:
  /// The current value of each static qubit, by index.
  using QubitMap = llvm::DenseMap<int64_t, Value>;

  //===--------------------------------------------------------------------===//
  // Preconditions
  //===--------------------------------------------------------------------===//

  /// Checks that the function is self-contained, that its qubits are static and used only by qref ops, and that the
  /// qref ops sit at the top level or inside `scf.if`. Then the conversion cannot fail.
  LogicalResult checkPreconditions() {
    Region& body = func.getBody();
    if (!body.hasOneBlock()) {
      return func.emitOpError() << "acts on qubits, so it must have a single block: only 'scf.if' is supported as "
                                   "control flow around qubit ops";
    }
    if (llvm::any_of(func.getArgumentTypes(), [](Type type) { return holdsQubitRefs(type); })) {
      return func.emitOpError() << "has a qubit reference argument, but every qubit must come from 'qcc.static_ref'";
    }

    const WalkResult result = body.walk<WalkOrder::PreOrder>([&](Operation* op) {
      if (isa<CallOpInterface>(op)) {
        op->emitOpError() << "is not supported: a function acting on qubits must be self-contained";
        return WalkResult::interrupt();
      }
      if (isQRefOp(op)) {
        return succeeded(checkPlacement(op)) ? WalkResult::advance() : WalkResult::interrupt();
      }
      if (!isa<StaticRefOp>(op) && holdsQubitRefs(op)) {
        op->emitOpError() << "is not supported on qubit references: every qubit must come from 'qcc.static_ref', and "
                             "only gates, measurements and resets may use it";
        return WalkResult::interrupt();
      }
      return WalkResult::advance();
    });
    return failure(result.wasInterrupted());
  }

  /// Checks that the qref op `op` sits at the top level of the function or inside `scf.if`, at any depth.
  LogicalResult checkPlacement(Operation* op) {
    for (Operation* parent = op->getParentOp(); parent != func.getOperation(); parent = parent->getParentOp()) {
      if (!isa<scf::IfOp>(parent)) {
        InFlightDiagnostic diag = op->emitOpError()
                                  << "must sit at the top level of the function or inside 'scf.if', but is inside '"
                                  << parent->getName() << "'";
        diag.attachNote(parent->getLoc()) << "see the enclosing op";
        return diag;
      }
    }
    return success();
  }

  //===--------------------------------------------------------------------===//
  // Conversion
  //===--------------------------------------------------------------------===//

  /// Converts the ops of `block` in order, starting from the current qubit values in `qubits`, and updates them.
  static void convertBlock(Block& block, QubitMap& qubits) {
    for (Operation& op : llvm::make_early_inc_range(block)) {
      llvm::TypeSwitch<Operation*>(&op)
          .Case([&](qref::SingleOp single) { convertSingle(single, qubits); })
          .Case([&](qref::PairOp pair) { convertPair(pair, qubits); })
          .Case([&](qref::MeasureOp measure) { convertMeasure(measure, qubits); })
          .Case([&](qref::ResetOp reset) { convertReset(reset, qubits); })
          .Case([&](scf::IfOp ifOp) { convertIf(ifOp, qubits); });
    }
  }

  static void convertSingle(qref::SingleOp single, QubitMap& qubits) {
    const int64_t index = getIndex(single.getQubit());
    OpBuilder builder(single);
    auto singleOp =
        qcirc::SingleOp::create(builder, single.getLoc(), single.getGateKind(), qubits.at(index), single.getParams());
    qubits[index] = singleOp.getQubitOut();
    single.erase();
  }

  static void convertPair(qref::PairOp pair, QubitMap& qubits) {
    const int64_t lhs = getIndex(pair.getLhs());
    const int64_t rhs = getIndex(pair.getRhs());
    OpBuilder builder(pair);
    auto pairOp = qcirc::PairOp::create(builder, pair.getLoc(), pair.getGateKind(), qubits.at(lhs), qubits.at(rhs),
                                        pair.getParams());
    qubits[lhs] = pairOp.getLhsOut();
    qubits[rhs] = pairOp.getRhsOut();
    pair.erase();
  }

  static void convertMeasure(qref::MeasureOp measure, QubitMap& qubits) {
    const int64_t index = getIndex(measure.getQubit());
    OpBuilder builder(measure);
    auto measureOp = qcirc::MeasureOp::create(builder, measure.getLoc(), measure.getBasis(), qubits.at(index));
    qubits[index] = measureOp.getQubitOut();
    measure.getBit().replaceAllUsesWith(measureOp.getBit());
    measure.erase();
  }

  static void convertReset(qref::ResetOp reset, QubitMap& qubits) {
    const int64_t index = getIndex(reset.getQubit());
    OpBuilder builder(reset);
    auto resetOp = qcirc::ResetOp::create(builder, reset.getLoc(), reset.getBasis(), qubits.at(index));
    qubits[index] = resetOp.getQubitOut();
    reset.erase();
  }

  /// Converts an `scf.if` with qubit ops inside into a `qcf.if`. It binds the qubits its regions act on, in increasing
  /// order of their indices, and its classical results follow them. An `scf.if` without qubit ops stays.
  static void convertIf(scf::IfOp ifOp, QubitMap& qubits) {
    const SmallVector<int64_t> bound = getActedOnIndices(ifOp);
    if (bound.empty()) {
      return;
    }
    SmallVector<Value> qubitsIn;
    for (const int64_t index : bound) {
      qubitsIn.push_back(qubits.at(index));
    }

    OpBuilder builder(ifOp);
    auto qcfIf = qcf::IfOp::create(builder, ifOp.getLoc(), ifOp.getCondition(), qubitsIn, ifOp.getResultTypes(),
                                   /*addThenBlock=*/false, /*addElseBlock=*/false);
    // An omitted else region stays omitted: it passes the bound qubits on, and the `scf.if` has no results then.
    for (auto [from, to] : llvm::zip_equal(ifOp->getRegions(), qcfIf->getRegions())) {
      to.takeBody(from);
      if (!to.empty()) {
        convertRegion(to, bound, qubitsIn);
      }
    }

    for (auto [index, qubitOut] : llvm::zip_equal(bound, qcfIf.getResults().take_front(bound.size()))) {
      qubits[index] = qubitOut;
    }
    ifOp.replaceAllUsesWith(qcfIf.getClassicalResults());
    ifOp.erase();
  }

  /// Converts a region moved from an `scf.if` into a `qcf.if` that binds the static qubits `bound` to `qubitsIn`:
  /// adds the bindings as arguments, converts the ops, and yields the bound qubits ahead of the classical values.
  static void convertRegion(Region& region, ArrayRef<int64_t> bound, ValueRange qubitsIn) {
    Block& block = region.front();
    QubitMap qubits;
    for (auto [index, qubitIn] : llvm::zip_equal(bound, qubitsIn)) {
      qubits[index] = block.addArgument(qubitIn.getType(), qubitIn.getLoc());
    }
    convertBlock(block, qubits);

    auto yield = cast<scf::YieldOp>(block.getTerminator());
    SmallVector<Value> results;
    for (const int64_t index : bound) {
      results.push_back(qubits.at(index));
    }
    llvm::append_range(results, yield.getResults());
    OpBuilder builder(yield);
    qcf::YieldOp::create(builder, yield.getLoc(), results);
    yield.erase();
  }

  func::FuncOp func;
};

struct ConvertQRefToQCirc final : impl::ConvertQRefToQCircBase<ConvertQRefToQCirc> {
  using ConvertQRefToQCircBase::ConvertQRefToQCircBase;

protected:
  void runOnOperation() override {
    // Functions without qubit references, arguments included, are none of our business.
    func::FuncOp func = getOperation();
    const WalkResult holdsRefs =
        func.walk([](Operation* op) { return holdsQubitRefs(op) ? WalkResult::interrupt() : WalkResult::advance(); });
    if (!holdsRefs.wasInterrupted()) {
      return;
    }

    if (failed(FunctionConverter(func).run())) {
      signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
