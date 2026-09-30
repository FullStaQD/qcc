// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// `convert-qvec-to-magic` walks each function once, in order. Qubit values are traced forward to the ions they hold
// (identity placement), gates are emitted on the current chain value of each trap, and the replaced operations are
// erased at the end.
//
//===----------------------------------------------------------------------===//

#include "qcc/Conversion/QVecToMagic/QVecToMagic.h" // IWYU pragma: keep
#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/Magic/Device/MagicDevice.h"
#include "qcc/Dialect/Magic/IR/Magic.h"
#include "qcc/Dialect/QVec/IR/QVec.h"
#include "qcc/Dialect/QVec/Transforms/Angles.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/QCO/IR/QCOOps.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h" // IWYU pragma: keep
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <utility>

namespace qcc {

#define GEN_PASS_DEF_CONVERTQVECTOMAGIC
#include "qcc/Conversion/QVecToMagic/QVecToMagic.h.inc"

using namespace mlir;
using namespace qcc::magic;

namespace {

/// The kind of the last gate layer, to check that layers alternate.
enum class Layer : uint8_t { None, ZXZ, ZZ, RZ };

class FunctionConverter {
public:
  FunctionConverter(func::FuncOp func, MagicDevice device) : func(func), device(std::move(device)) {}

  LogicalResult run() {
    if (!func.getBody().hasOneBlock()) {
      return func.emitOpError() << "convert-qvec-to-magic expects a single-block function";
    }
    Block& block = func.getBody().front();
    createChains(block);

    for (Operation& op : llvm::make_early_inc_range(block)) {
      if (failed(convert(&op))) {
        return failure();
      }
    }
    if (failed(checkMeasurements())) {
      return failure();
    }

    for (Operation* op : llvm::reverse(replaced)) {
      op->dropAllUses();
      op->erase();
    }
    // Angle constants and the like that only fed the replaced ops.
    for (Operation& op : llvm::make_early_inc_range(llvm::reverse(block))) {
      if (isa_and_present<arith::ArithDialect, vector::VectorDialect>(op.getDialect()) && isOpTriviallyDead(&op)) {
        op.erase();
      }
    }
    return checkLegal(block);
  }

private:
  //===--------------------------------------------------------------------===//
  // Placement
  //===--------------------------------------------------------------------===//

  /// The trap of `ion` under the identity placement.
  [[nodiscard]] int64_t getTrap(int64_t ion) const {
    int64_t end = 0;
    for (TrapId trap = 0;; ++trap) {
      end += device.initialOccupancy(trap);
      if (ion < end) {
        return trap;
      }
    }
  }

  /// One `magic.init` at the start of `block` with the chains of all traps, filled trap by trap.
  void createChains(Block& block) {
    MLIRContext* ctx = func.getContext();
    SmallVector<Type> types;
    int64_t ion = 0;
    for (TrapId trap = 0; trap < device.numTraps(); ++trap) {
      SmallVector<IonSlot> slots;
      for (IonCount k = 0; k < device.initialOccupancy(trap); ++k) {
        slots.push_back(IonSlot{.ion = ion++, .active = true});
      }
      types.push_back(IonChainType::get(ctx, trap, slots));
    }
    auto builder = OpBuilder::atBlockBegin(&block);
    auto init = InitOp::create(builder, func.getLoc(), types);
    chains.assign(init.getChains().begin(), init.getChains().end());
  }

  //===--------------------------------------------------------------------===//
  // Conversion
  //===--------------------------------------------------------------------===//

  LogicalResult convert(Operation* op) {
    return llvm::TypeSwitch<Operation*, LogicalResult>(op)
        .Case([&](mlir::qco::StaticOp staticOp) { return convertStatic(staticOp); })
        .Case([&](mlir::qco::AllocOp alloc) {
          return alloc.emitOpError() << "is not supported: ions are placed statically, use `qco.static`";
        })
        .Case([&](vector::FromElementsOp fromElements) { return convertFromElements(fromElements); })
        .Case([&](vector::ExtractOp extract) { return convertExtract(extract); })
        .Case([&](qvec::SingleOp single) { return convertSingle(single); })
        .Case([&](qvec::GlobalOp global) { return convertGlobal(global); })
        .Case([&](qvec::MZOp mz) { return convertMZ(mz); })
        .Case([&](mlir::qco::SinkOp sink) {
          replaced.push_back(sink);
          return success();
        })
        // Everything else is left for `checkLegal`.
        .Default([](Operation*) { return success(); });
  }

  LogicalResult convertStatic(mlir::qco::StaticOp staticOp) {
    const auto index = static_cast<int64_t>(staticOp.getIndex());
    if (std::cmp_greater_equal(index, device.numIons())) {
      return staticOp.emitOpError() << "uses qubit " << index << ", but the device holds only " << device.numIons()
                                    << " ions";
    }
    if (!usedQubits.insert(index).second) {
      return staticOp.emitOpError() << "refers to qubit " << index << " a second time";
    }
    ionOf[staticOp.getQubit()] = index;
    replaced.push_back(staticOp);
    return success();
  }

  /// The ion held by the scalar qubit `qubit`, or a diagnostic at `user`.
  FailureOr<int64_t> lookupIon(Operation* user, Value qubit) {
    auto it = ionOf.find(qubit);
    if (it == ionOf.end()) {
      return user->emitOpError() << "uses a qubit that cannot be traced back to a `qco.static`";
    }
    return it->second;
  }

  LogicalResult convertFromElements(vector::FromElementsOp fromElements) {
    if (!qvec::isQubitVector(fromElements.getType())) {
      return success();
    }
    SmallVector<int64_t>& ions = lanes[fromElements.getResult()];
    for (Value element : fromElements.getElements()) {
      const FailureOr<int64_t> ion = lookupIon(fromElements, element);
      if (failed(ion)) {
        return failure();
      }
      ions.push_back(*ion);
    }
    replaced.push_back(fromElements);
    return success();
  }

  LogicalResult convertExtract(vector::ExtractOp extract) {
    auto it = lanes.find(extract.getSource());
    if (it == lanes.end()) {
      return success(); // not a qubit or bit vector
    }
    if (extract.hasDynamicPosition() || extract.getStaticPosition().size() != 1) {
      return extract.emitOpError() << "must extract a single lane at a constant position";
    }
    const int64_t ion = it->second[extract.getStaticPosition().front()];
    if (qvec::isQubitVector(extract.getSource().getType())) {
      ionOf[extract.getResult()] = ion;
    } else {
      // A measured bit: the chains are measured already.
      extract.getResult().replaceAllUsesWith(bitOf.lookup(ion));
    }
    replaced.push_back(extract);
    return success();
  }

  /// The lanes of `qubits` or a diagnostic at `op`.
  FailureOr<ArrayRef<int64_t>> lookupLanes(Operation* op, Value qubits) {
    auto it = lanes.find(qubits);
    if (it == lanes.end()) {
      return op->emitOpError() << "acts on qubits that cannot be traced back to `qco.static`";
    }
    return ArrayRef<int64_t>(it->second);
  }

  /// Checks that a layer of kind `layer` may follow the previous one and nothing was measured yet.
  LogicalResult checkLayer(Operation* op, Layer layer) {
    if (measured) {
      return op->emitOpError() << "acts after the measurement: measurements end a program";
    }
    if (last == Layer::RZ || (layer == last && layer != Layer::None)) {
      return op->emitOpError() << "breaks the layer order expected from `qvec-layer`: `single u_zxz` layers and "
                                  "`global zz` blocks alternate, followed by at most one `single rz` layer";
    }
    last = layer;
    return success();
  }

  LogicalResult convertSingle(qvec::SingleOp single) {
    const qvec::SingleGateKind kind = single.getGateKind();
    if (kind != qvec::SingleGateKind::UZXZ && kind != qvec::SingleGateKind::RZ) {
      return single.emitOpError() << "gate '" << qvec::stringifySingleGateKind(kind)
                                  << "' is not supported, run `qvec-to-u-zxz` and `qvec-layer` first";
    }
    if (failed(checkLayer(single, kind == qvec::SingleGateKind::UZXZ ? Layer::ZXZ : Layer::RZ))) {
      return failure();
    }
    const FailureOr<ArrayRef<int64_t>> ions = lookupLanes(single, single.getQubitsIn());
    if (failed(ions)) {
      return failure();
    }
    SmallVector<SmallVector<double>> params;
    for (Value param : single.getParams()) {
      std::optional<SmallVector<double>> values = qvec::getConstantAngles(param);
      if (!values) {
        return single.emitOpError() << "angles must be compile-time constants";
      }
      params.push_back(std::move(*values));
    }

    OpBuilder builder(single);
    for (auto [trap, chain] : llvm::enumerate(chains)) {
      SmallVector<int64_t> trapIons;
      SmallVector<SmallVector<Attribute>> trapParams(params.size());
      for (auto [lane, ion] : llvm::enumerate(*ions)) {
        if (getTrap(ion) != static_cast<int64_t>(trap)) {
          continue;
        }
        trapIons.push_back(ion);
        for (auto [values, attrs] : llvm::zip_equal(params, trapParams)) {
          attrs.push_back(builder.getF64FloatAttr(values[lane]));
        }
      }
      if (trapIons.empty()) {
        continue;
      }
      if (kind == qvec::SingleGateKind::UZXZ) {
        chain = ZXZOp::create(
            builder, single.getLoc(), chain.getType(), chain, trapIons, builder.getArrayAttr(trapParams[qvec::zxz::z1]),
            builder.getArrayAttr(trapParams[qvec::zxz::x]), builder.getArrayAttr(trapParams[qvec::zxz::z2]));
      } else {
        chain = RZOp::create(builder, single.getLoc(), chain.getType(), chain, trapIons,
                             builder.getArrayAttr(trapParams.front()));
      }
    }
    lanes[single.getQubitsOut()] = SmallVector<int64_t>(*ions);
    replaced.push_back(single);
    return success();
  }

  LogicalResult convertGlobal(qvec::GlobalOp global) {
    if (failed(checkLayer(global, Layer::ZZ))) {
      return failure();
    }
    const FailureOr<ArrayRef<int64_t>> ions = lookupLanes(global, global.getQubitsIn());
    if (failed(ions)) {
      return failure();
    }
    const std::optional<SmallVector<double>> matrix = qvec::getConstantAngles(global.getAngles());
    if (!matrix) {
      return global.emitOpError() << "angles must be compile-time constants";
    }
    const size_t size = ions->size();
    auto entry = [&](size_t i, size_t j) { return (*matrix)[(i * size) + j]; };
    for (size_t i = 0; i < size; ++i) {
      if (entry(i, i) != 0.0) {
        return global.emitOpError() << "angles must have a zero diagonal";
      }
      for (size_t j = i + 1; j < size; ++j) {
        if (entry(i, j) != entry(j, i)) {
          return global.emitOpError() << "angles must be symmetric";
        }
      }
    }

    // A = A_00 ⊕ A_11 + A_01: the diagonal blocks act within a trap, the rest couples ions of different traps.
    OpBuilder builder(global);
    const Location loc = global.getLoc();
    llvm::DenseMap<int64_t, size_t> laneOf;
    for (auto [lane, ion] : llvm::enumerate(*ions)) {
      laneOf[ion] = lane;
    }
    for (Value& chain : chains) {
      // The matrix over the active ions of the chain in position order; ions outside the layer do not couple.
      const SmallVector<int64_t> active = cast<IonChainType>(chain.getType()).getActiveIons();
      const size_t numActive = active.size();
      SmallVector<double> block(numActive * numActive, 0.0);
      bool nonzero = false;
      for (size_t a = 0; a < numActive; ++a) {
        for (size_t b = 0; b < numActive; ++b) {
          auto laneA = laneOf.find(active[a]);
          auto laneB = laneOf.find(active[b]);
          if (laneA != laneOf.end() && laneB != laneOf.end()) {
            block[(a * numActive) + b] = entry(laneA->second, laneB->second);
            nonzero |= block[(a * numActive) + b] != 0.0;
          }
        }
      }
      if (nonzero) {
        auto type = RankedTensorType::get({static_cast<int64_t>(numActive), static_cast<int64_t>(numActive)},
                                          Float64Type::get(builder.getContext()));
        chain = ActiveZZOp::create(builder, loc, chain.getType(), chain, DenseElementsAttr::get(type, ArrayRef(block)));
      }
    }
    for (size_t i = 0; i < size; ++i) {
      for (size_t j = i + 1; j < size; ++j) {
        const int64_t ionA = (*ions)[i];
        const int64_t ionB = (*ions)[j];
        const int64_t trapA = getTrap(ionA);
        const int64_t trapB = getTrap(ionB);
        if (trapA == trapB || entry(i, j) == 0.0) {
          continue;
        }
        // The lower trap first, so the output does not depend on the lane order.
        const bool ordered = trapA < trapB;
        Value& first = chains[ordered ? trapA : trapB];
        Value& second = chains[ordered ? trapB : trapA];
        auto interTrap = InterTrapZZOp::create(
            builder, loc, first.getType(), second.getType(), first, second,
            builder.getDenseI64ArrayAttr(ordered ? ArrayRef<int64_t>{ionA, ionB} : ArrayRef<int64_t>{ionB, ionA}),
            builder.getF64FloatAttr(entry(i, j)));
        first = interTrap.getAOut();
        second = interTrap.getBOut();
      }
    }
    lanes[global.getQubitsOut()] = SmallVector<int64_t>(*ions);
    replaced.push_back(global);
    return success();
  }

  LogicalResult convertMZ(qvec::MZOp mz) {
    const FailureOr<ArrayRef<int64_t>> ions = lookupLanes(mz, mz.getQubitsIn());
    if (failed(ions)) {
      return failure();
    }
    if (!measured) {
      // The first measurement ends the program: every chain is measured as a whole.
      OpBuilder builder(mz);
      for (Value chain : chains) {
        auto type = cast<IonChainType>(chain.getType());
        if (type.getNumIons() == 0) {
          continue;
        }
        auto mzd =
            MZDOp::create(builder, mz.getLoc(), SmallVector<Type>(type.getNumIons(), builder.getI1Type()), chain);
        for (auto [ion, bit] : llvm::zip_equal(type.getIons(), mzd.getBits())) {
          bitOf[ion] = bit;
        }
      }
      measured = true;
    }
    for (const int64_t ion : *ions) {
      if (!measuredBy.try_emplace(ion, mz).second) {
        return mz.emitOpError() << "measures qubit " << ion << " a second time";
      }
    }
    lanes[mz.getQubitsOut()] = SmallVector<int64_t>(*ions);
    lanes[mz.getBits()] = SmallVector<int64_t>(*ions);
    replaced.push_back(mz);
    return success();
  }

  //===--------------------------------------------------------------------===//
  // Checks
  //===--------------------------------------------------------------------===//

  /// Every ion is measured once and every result is recorded once.
  LogicalResult checkMeasurements() {
    for (int64_t ion = 0; std::cmp_less(ion, device.numIons()); ++ion) {
      auto it = measuredBy.find(ion);
      if (it == measuredBy.end()) {
        return func.emitOpError() << "does not measure qubit " << ion << ": every ion of the device ("
                                  << device.numIons() << ") is measured exactly once";
      }
      Value bit = bitOf.lookup(ion);
      if (!bit.hasOneUse() || !isa<aux::RecordIntOp>(*bit.user_begin())) {
        return it->second->emitOpError() << "must have the result of qubit " << ion
                                         << " recorded by exactly one `aux.record_int` and used nowhere else";
      }
    }
    return success();
  }

  /// What is left in `block` is the magic program and its records.
  static LogicalResult checkLegal(Block& block) {
    for (Operation& op : block) {
      if (isa_and_present<MagicDialect>(op.getDialect()) || isa<arith::ConstantOp>(op)) {
        continue;
      }
      if (auto record = dyn_cast<aux::RecordIntOp>(op)) {
        if (!record.getValue().getDefiningOp<MZDOp>()) {
          return record.emitOpError() << "records a value that is not a measurement result";
        }
        continue;
      }
      if (auto ret = dyn_cast<func::ReturnOp>(op); ret && ret.getNumOperands() == 0) {
        continue;
      }
      return op.emitOpError() << "is not supported by convert-qvec-to-magic";
    }
    return success();
  }

  func::FuncOp func;
  MagicDevice device;

  /// The current chain value per trap.
  SmallVector<Value> chains;
  /// The ion held by a scalar qubit value.
  llvm::DenseMap<Value, int64_t> ionOf;
  /// The ion per lane of a qubit vector, or of the bit vector of a `qvec.mz`.
  llvm::DenseMap<Value, SmallVector<int64_t>> lanes;
  /// The `magic.mzd` result per ion, once measured.
  llvm::DenseMap<int64_t, Value> bitOf;
  /// The `qvec.mz` that measures an ion.
  llvm::DenseMap<int64_t, Operation*> measuredBy;
  llvm::DenseSet<int64_t> usedQubits;
  /// The ops to erase, in program order.
  SmallVector<Operation*> replaced;
  Layer last = Layer::None;
  bool measured = false;
};

struct ConvertQVecToMagic final : impl::ConvertQVecToMagicBase<ConvertQVecToMagic> {
  using ConvertQVecToMagicBase::ConvertQVecToMagicBase;

protected:
  void runOnOperation() override {
    SmallVector<func::FuncOp> funcs;
    getOperation().walk([&](func::FuncOp func) {
      const WalkResult result = func.walk([](Operation* op) {
        return isa_and_present<qvec::QVecDialect>(op->getDialect()) ? WalkResult::interrupt() : WalkResult::advance();
      });
      if (result.wasInterrupted()) {
        funcs.push_back(func);
      }
    });
    if (funcs.empty()) {
      return;
    }

    const FailureOr<MagicDevice> device = MagicDevice::fromModule(getOperation());
    if (failed(device)) {
      return signalPassFailure();
    }
    for (func::FuncOp func : funcs) {
      if (failed(FunctionConverter(func, *device).run())) {
        return signalPassFailure();
      }
    }
  }
};

} // namespace
} // namespace qcc
