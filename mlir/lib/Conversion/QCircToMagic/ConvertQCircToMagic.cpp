// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM Exceptions. See <repo-root>/LICENSE.txt for
// license information. SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// `convert-qcirc-to-magic` walks each function once, in order. Qubit values are traced forward to the ions they hold
// (ion `i` = the `i`-th qubit of `qcc.static`), each gate is emitted on the current chain value of its trap, and the
// replaced operations are erased at the end.
//
// We do not use the dialect conversion framework here: A qubit has no magic value to be replaced with. Instead all
// qubits of a trap share a single chain.
//
//===----------------------------------------------------------------------===//

#include "qcc/Conversion/QCircToMagic/QCircToMagic.h" // IWYU pragma: keep
#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/Magic/Device/MagicDevice.h"
#include "qcc/Dialect/Magic/IR/Magic.h"
#include "qcc/Dialect/QCirc/IR/QCirc.h"
#include "qcc/Dialect/QCirc/Transforms/Angles.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/ErrorHandling.h"

#include <algorithm>
#include <cstdint>
#include <iterator>
#include <map>
#include <optional>
#include <utility>

namespace qcc {

#define GEN_PASS_DEF_CONVERTQCIRCTOMAGIC
#include "qcc/Conversion/QCircToMagic/QCircToMagic.h.inc"

using namespace mlir;
using namespace qcc::magic;

namespace {

class FunctionConverter {
public:
  FunctionConverter(StaticOp staticOp, MagicDevice device, StringRef passName)
      : staticOp(staticOp), device(std::move(device)), passName(passName), builder(staticOp->getContext()) {}

  LogicalResult run() {
    Block& block = *staticOp->getBlock();
    if (failed(createChains(block))) {
      return failure();
    }

    // The magic ops go in front of the current op, so the walk never meets them.
    for (Operation& op : llvm::make_early_inc_range(block)) {
      if (failed(convert(&op))) {
        return failure();
      }
    }
    emitMeasurements();

    for (Operation* op : llvm::reverse(replaced)) {
      op->dropAllUses();
      op->erase();
    }
    // Angle constants and the like that only fed the replaced ops.
    for (Operation& op : llvm::make_early_inc_range(llvm::reverse(block))) {
      if (isa_and_present<arith::ArithDialect>(op.getDialect()) && isOpTriviallyDead(&op)) {
        op.erase();
      }
    }
    return checkLegal(block);
  }

private:
  //===--------------------------------------------------------------------===//
  // Placement
  //===--------------------------------------------------------------------===//

  /// One `magic.init` at the start of `block` with the chains of all traps, replacing `qcc.static`. It creates one ion
  /// per qubit: the `i`-th qubit becomes ion `i`, whatever its index, so gaps in the indices cost no slots. If all ions
  /// fit into trap 0 they go there, which needs no shuttling. Otherwise they are filled in trap by trap, one ion less
  /// than the capacity each, as shuttling needs a free slot.
  LogicalResult createChains(Block& block) {
    const int64_t numQubits = std::ssize(staticOp.getQubits());

    MLIRContext* ctx = staticOp->getContext();
    const bool spread = device.numTraps() > 1 && numQubits > device.capacity(0);
    const IonCount reserved = spread ? 1 : 0;
    SmallVector<Type> types;
    for (TrapId trap = 0; trap < device.numTraps(); ++trap) {
      SmallVector<IonSlot> slots;
      while (std::ssize(trapOf) < numQubits && std::ssize(slots) + reserved < device.capacity(trap)) {
        slots.push_back(IonSlot{.ion = std::ssize(trapOf), .active = true});
        trapOf.push_back(trap);
      }
      types.push_back(IonChainType::get(ctx, trap, slots));
    }
    if (std::ssize(trapOf) < numQubits) {
      return staticOp.emitOpError() << "uses " << numQubits << " qubits, but the device can be loaded with at most "
                                    << trapOf.size() << " ions"
                                    << (spread ? ": one slot per trap stays free for shuttling" : "");
    }

    builder.setInsertionPointToStart(&block);
    auto init = InitOp::create(builder, staticOp.getLoc(), types);
    for (Value chain : init.getChains()) {
      chains.push_back(cast<TypedValue<IonChainType>>(chain));
    }

    for (auto [ion, qubit] : llvm::enumerate(staticOp.getQubits())) {
      ionOf[qubit] = static_cast<int64_t>(ion);
    }
    replaced.push_back(staticOp);
    return success();
  }

  //===--------------------------------------------------------------------===//
  // Conversion
  //===--------------------------------------------------------------------===//

  LogicalResult convert(Operation* op) {
    return llvm::TypeSwitch<Operation*, LogicalResult>(op)
        .Case([&](qcirc::SingleOp single) { return convertSingle(single); })
        .Case([&](qcirc::PairOp pair) { return convertPair(pair); })
        .Case([&](qcirc::MeasureOp measure) { return convertMeasure(measure); })
        .Case([&](qcirc::ResetOp reset) {
          return reset.emitOpError() << "resets a qubit, which " << passName << " does not support";
        })
        // `createChains` replaced `qcc.static` already, everything else is left for `checkLegal`.
        .Default([](Operation*) { return success(); });
  }

  /// The `qcc.static` index of the qubit that `ion` holds, for diagnostics.
  int64_t qubitIndexOf(int64_t ion) { return staticOp.getIndices()[ion]; }

  /// The ion that `op` acts on through `qubit`, or a diagnostic if it is measured already.
  FailureOr<int64_t> lookupUnmeasuredIon(Operation* op, Value qubit) {
    // The precondition ensures that every qubit comes from `qcc.static` through the ops converted so far.
    const int64_t ion = ionOf.at(qubit);
    if (measuredBy.contains(ion)) {
      return op->emitOpError() << "acts on qubit " << qubitIndexOf(ion) << " after its measurement, but " << passName
                               << " expects no gate on a qubit after its measurement";
    }
    return ion;
  }

  /// The values of the constant angles of `op`, or a diagnostic.
  FailureOr<SmallVector<double>> getConstantAngles(Operation* op, ValueRange params) {
    SmallVector<double> angles;
    for (Value param : params) {
      const std::optional<double> angle = qcirc::getConstantAngle(param);
      if (!angle) {
        return op->emitOpError() << "takes an angle that is not a compile-time constant, but " << passName
                                 << " expects constant angles";
      }
      angles.push_back(*angle);
    }
    return angles;
  }

  LogicalResult convertSingle(qcirc::SingleOp single) {
    const SingleGateKind kind = single.getGateKind();
    if (kind != SingleGateKind::UZXZ && kind != SingleGateKind::RZ) {
      return single.emitOpError() << "applies gate '" << stringifySingleGateKind(kind) << "', but " << passName
                                  << " expects only 'u_zxz' and 'rz'";
    }
    const FailureOr<int64_t> ion = lookupUnmeasuredIon(single, single.getQubitIn());
    if (failed(ion)) {
      return failure();
    }
    const FailureOr<SmallVector<double>> angles = getConstantAngles(single, single.getParams());
    if (failed(angles)) {
      return failure();
    }

    TypedValue<IonChainType>& chain = chains[trapOf[*ion]];
    const ArrayRef<int64_t> ions(*ion);
    switch (kind) {
    case SingleGateKind::UZXZ:
      chain = ZXZOp::create(builder, single.getLoc(), chain, ions, ArrayRef((*angles)[zxz::z1]),
                            ArrayRef((*angles)[zxz::x]), ArrayRef((*angles)[zxz::z2]));
      break;
    case SingleGateKind::RZ:
      chain = RZOp::create(builder, single.getLoc(), chain, ions, ArrayRef(angles->front()));
      break;
    default:
      llvm_unreachable("gate kind rejected above");
    }
    ionOf[single.getQubitOut()] = *ion;
    replaced.push_back(single);
    return success();
  }

  LogicalResult convertPair(qcirc::PairOp pair) {
    const PairGateKind kind = pair.getGateKind();
    if (kind != PairGateKind::RZZ) {
      return pair.emitOpError() << "applies gate '" << stringifyPairGateKind(kind) << "', but " << passName
                                << " expects only 'rzz'";
    }
    const FailureOr<int64_t> lhs = lookupUnmeasuredIon(pair, pair.getLhsIn());
    if (failed(lhs)) {
      return failure();
    }
    const FailureOr<int64_t> rhs = lookupUnmeasuredIon(pair, pair.getRhsIn());
    if (failed(rhs)) {
      return failure();
    }
    const FailureOr<SmallVector<double>> angles = getConstantAngles(pair, pair.getParams());
    if (failed(angles)) {
      return failure();
    }

    const Location loc = pair.getLoc();
    const double angle = angles->front();
    // The lower ion first, as `inter_trap_zz` wants its ions.
    const auto [ionA, ionB] = std::minmax(*lhs, *rhs);
    const TrapId trapA = trapOf[ionA];
    const TrapId trapB = trapOf[ionB];
    if (trapA == trapB) {
      chains[trapA] = ActiveZZOp::create(builder, loc, chains[trapA], ionA, ionB, angle);
    } else {
      TypedValue<IonChainType>& chainA = chains[trapA];
      TypedValue<IonChainType>& chainB = chains[trapB];
      auto interTrap =
          InterTrapZZOp::create(builder, loc, chainA.getType(), chainB.getType(), chainA, chainB,
                                builder.getDenseI64ArrayAttr({ionA, ionB}), builder.getF64FloatAttr(angle));
      chainA = interTrap.getAOut();
      chainB = interTrap.getBOut();
    }
    ionOf[pair.getLhsOut()] = *lhs;
    ionOf[pair.getRhsOut()] = *rhs;
    replaced.push_back(pair);
    return success();
  }

  LogicalResult convertMeasure(qcirc::MeasureOp measure) {
    if (measure.getBasis() != Basis::Z) {
      return measure.emitOpError() << "measures in basis '" << stringifyBasis(measure.getBasis()) << "', which "
                                   << passName << " does not support";
    }
    const int64_t ion = ionOf.at(measure.getQubitIn());
    if (measuredBy.contains(ion)) {
      return measure.emitOpError() << "measures qubit " << qubitIndexOf(ion) << " a second time, but " << passName
                                   << " expects no second measurement of a qubit";
    }
    const Value bit = measure.getBit();
    if (!bit.use_empty() && (!bit.hasOneUse() || !isa<aux::RecordIntOp>(*bit.user_begin()))) {
      return measure.emitOpError() << "has its result used other than by one 'aux.record_int', which " << passName
                                   << " does not support";
    }
    measuredBy[ion] = measure;
    firstMeasurementOf.try_emplace(trapOf[ion], measure.getLoc());
    ionOf[measure.getQubitOut()] = ion;
    replaced.push_back(measure);
    return success();
  }

  /// One `magic.mzd` per trap with a measured ion, behind all gates. It measures every ion of the trap, and the
  /// measured qubits take their bits from it.
  void emitMeasurements() {
    for (const auto& [trap, loc] : firstMeasurementOf) {
      const TypedValue<IonChainType> chain = chains[trap];
      const IonChainType type = chain.getType();
      auto mzd = MZDOp::create(builder, loc, SmallVector<Type>(type.getNumIons(), builder.getI1Type()), chain);
      for (auto [ion, bit] : llvm::zip_equal(type.getIons(), mzd.getBits())) {
        if (auto it = measuredBy.find(ion); it != measuredBy.end()) {
          it->second.getBit().replaceAllUsesWith(bit);
        }
      }
    }
  }

  //===--------------------------------------------------------------------===//
  // Checks
  //===--------------------------------------------------------------------===//

  /// What is left in `block` is the magic program and its records.
  LogicalResult checkLegal(Block& block) {
    for (Operation& op : block) {
      if (isa_and_present<MagicDialect>(op.getDialect()) || isa<arith::ConstantOp>(op)) {
        continue;
      }
      if (auto record = dyn_cast<aux::RecordIntOp>(op)) {
        if (!record.getValue().getDefiningOp<MZDOp>()) {
          return record.emitOpError() << "records a value that is not a measurement result, which " << passName
                                      << " does not support";
        }
        continue;
      }
      if (auto ret = dyn_cast<func::ReturnOp>(op); ret && ret.getNumOperands() == 0) {
        continue;
      }
      return op.emitOpError() << "is not supported by " << passName;
    }
    return success();
  }

  StaticOp staticOp;
  MagicDevice device;
  StringRef passName;
  /// Inserts right behind the latest emitted op.
  OpBuilder builder;

  /// The trap per ion, as placed by `createChains`.
  SmallVector<TrapId> trapOf;
  /// The current chain value per trap.
  SmallVector<TypedValue<IonChainType>> chains;
  /// The ion held by a qubit value.
  llvm::DenseMap<Value, int64_t> ionOf;
  /// The `qcirc.measure` that measures an ion.
  llvm::DenseMap<int64_t, qcirc::MeasureOp> measuredBy;
  /// The location of the first `qcirc.measure` per trap with a measured ion, by trap id.
  std::map<TrapId, Location> firstMeasurementOf;
  /// The ops to erase, in program order.
  SmallVector<Operation*> replaced;
};

struct ConvertQCircToMagic final : impl::ConvertQCircToMagicBase<ConvertQCircToMagic> {
  using ConvertQCircToMagicBase::ConvertQCircToMagicBase;

protected:
  void runOnOperation() override {
    // Functions without qubits are none of our business and need no device.
    func::FuncOp func = getOperation();
    auto statics = func.getOps<StaticOp>();
    if (statics.empty()) {
      return;
    }

    // Check the precondition: only ops from a whitelist use qubits.
    const WalkResult unsupported = func->walk<WalkOrder::PreOrder>([&](Operation* op) {
      const bool usesQubits = llvm::any_of(op->getOperandTypes(), isQubitOrQubitVector) ||
                              llvm::any_of(op->getResultTypes(), isQubitOrQubitVector);
      if (usesQubits && !isa<StaticOp>(op) && !isa_and_present<qcirc::QCircDialect>(op->getDialect())) {
        op->emitOpError() << "uses qubits, but " << getArgument()
                          << " expects only 'qcc.static' and 'qcirc' ops to use qubits";
        return WalkResult::interrupt();
      }
      return WalkResult::advance();
    });
    if (unsupported.wasInterrupted()) {
      return signalPassFailure();
    }

    const FailureOr<MagicDevice> device = MagicDevice::fromParentModule(func);
    if (failed(device) || failed(FunctionConverter(*statics.begin(), *device, getArgument()).run())) {
      return signalPassFailure();
    }
  }
};

} // namespace
} // namespace qcc
