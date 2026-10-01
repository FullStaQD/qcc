// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/IR/Magic.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Value.h"

#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Sequence.h"
#include "llvm/ADT/SmallSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <numbers>

using namespace mlir;
using namespace qcc::magic;

//===----------------------------------------------------------------------===//
// Custom directives
//===----------------------------------------------------------------------===//

/// Parses `ions [0, 2]` into a dense i64 array.
static ParseResult parseIonList(OpAsmParser& parser, DenseI64ArrayAttr& ions) {
  SmallVector<int64_t> ids;
  auto parseId = [&]() -> ParseResult {
    int64_t id = 0;
    if (parser.parseInteger(id)) {
      return failure();
    }
    ids.push_back(id);
    return success();
  };
  if (parser.parseKeyword("ions") || parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, parseId)) {
    return failure();
  }
  ions = parser.getBuilder().getDenseI64ArrayAttr(ids);
  return success();
}

/// Prints `ions [0, 2]`.
static void printIonList(OpAsmPrinter& printer, Operation* /*op*/, DenseI64ArrayAttr ions) {
  printer << "ions [";
  llvm::interleaveComma(ions.asArrayRef(), printer);
  printer << "]";
}

//===----------------------------------------------------------------------===//
// Shared verification
//===----------------------------------------------------------------------===//

LogicalResult qcc::magic::verifyAffineChains(Operation* op) {
  // A program is one function, and its ops sit directly in the function body.
  if (!isa_and_present<func::FuncOp>(op->getParentOp())) {
    return op->emitOpError() << "must be directly inside a 'func.func': a program is one function";
  }

  // The dialect has no control flow: a program is one straight line of sync points, which is what the timing model
  // and the type-level chain tracking assume. It also makes possible to check affine typing via usage counting.
  if (!op->getParentRegion()->hasOneBlock()) {
    return op->emitOpError() << "must be in a single-block region: the dialect has no control flow";
  }

  for (OpResult result : op->getResults()) {
    if (!isa<IonChainType>(result.getType()) || result.use_empty() || result.hasOneUse()) {
      continue;
    }
    return op->emitOpError() << "chain result #" << result.getResultNumber() << " has " << result.getNumUses()
                             << " uses, but chain values are affine";
  }

  // `magic.init` is the sole source of chain values. We do not allow function or block arguments to be chains.
  for (OpOperand& operand : op->getOpOperands()) {
    Value chain = operand.get();
    if (isa<IonChainType>(chain.getType()) && chain.getDefiningOp() == nullptr) {
      return op->emitOpError() << "chain operand #" << operand.getOperandNumber()
                               << " must be produced by a magic op, not a block argument";
    }
  }
  return success();
}

/// Verifies that `ions` (ids) are all contained in `chain` and listed in strictly increasing order.
static LogicalResult verifyIonsInChain(Operation* op, ArrayRef<int64_t> ions, IonChainType chain) {
  for (auto [index, ion] : llvm::enumerate(ions)) {
    if (!chain.contains(ion)) {
      return op->emitOpError() << "ion " << ion << " is not in the chain " << chain;
    }
    if (index == 0) {
      continue;
    }
    const int64_t previous = ions[index - 1];
    if (ion == previous) {
      return op->emitOpError() << "ion " << ion << " is listed more than once";
    }
    if (ion < previous) {
      return op->emitOpError() << "ions must be listed in increasing order, got ion " << ion << " after ion "
                               << previous;
    }
  }
  return success();
}

/// Verifies that the angle array `angles` (named `name`) has one entry per ion.
static LogicalResult verifyOneAnglePerIon(Operation* op, StringRef name, ArrayAttr angles, size_t numIons) {
  if (angles.size() != numIons) {
    return op->emitOpError() << "expected one '" << name << "' angle per ion, got " << angles.size() << " for "
                             << numIons << " ions";
  }
  return success();
}

//===----------------------------------------------------------------------===//
// InitOp
//===----------------------------------------------------------------------===//

LogicalResult InitOp::verify() {
  if (getChains().empty()) {
    return emitOpError() << "expected at least one chain";
  }

  llvm::SmallSet<int64_t, 4> traps;
  llvm::SmallSet<int64_t, 16> ions;
  for (Value chainValue : getChains()) {
    auto chain = cast<IonChainType>(chainValue.getType());
    if (!traps.insert(chain.getTrap()).second) {
      return emitOpError() << "trap " << chain.getTrap() << " is initialized more than once";
    }
    for (const IonSlot& slot : chain.getSlots()) {
      if (!slot.active) {
        return emitOpError() << "ion " << slot.ion << " must be active initially";
      }
      if (!ions.insert(slot.ion).second) {
        return emitOpError() << "ion " << slot.ion << " is placed in more than one trap";
      }
    }
  }
  return success();
}

//===----------------------------------------------------------------------===//
// Single-ion gates
//===----------------------------------------------------------------------===//

/// The order that lists `ions` by increasing id: entry `k` is the index of the ion that comes `k`-th.
static SmallVector<size_t> getOrderById(ArrayRef<int64_t> ions) {
  SmallVector<size_t> order = llvm::to_vector(llvm::seq<size_t>(0, ions.size()));
  llvm::sort(order, [&](size_t a, size_t b) { return ions[a] < ions[b]; });
  return order;
}

/// `values` rearranged by `order`, see `getOrderById`.
template <typename T> static SmallVector<T> permute(ArrayRef<T> values, ArrayRef<size_t> order) {
  assert(values.size() == order.size() && "expected one value per ion");
  return llvm::map_to_vector(order, [&](size_t index) { return values[index]; });
}

void ZXZOp::build(OpBuilder& builder, OperationState& state, Value chain, ArrayRef<int64_t> ions, ArrayRef<double> z1,
                  ArrayRef<double> x, ArrayRef<double> z2) {
  const SmallVector<size_t> order = getOrderById(ions);
  build(builder, state, chain.getType(), chain, permute(ions, order), builder.getF64ArrayAttr(permute(z1, order)),
        builder.getF64ArrayAttr(permute(x, order)), builder.getF64ArrayAttr(permute(z2, order)));
}

void RZOp::build(OpBuilder& builder, OperationState& state, Value chain, ArrayRef<int64_t> ions,
                 ArrayRef<double> angles) {
  const SmallVector<size_t> order = getOrderById(ions);
  build(builder, state, chain.getType(), chain, permute(ions, order), builder.getF64ArrayAttr(permute(angles, order)));
}

void SymZXZOp::build(OpBuilder& builder, OperationState& state, Value chain, ArrayRef<int64_t> ions, ArrayRef<double> z,
                     ArrayRef<double> x) {
  const SmallVector<size_t> order = getOrderById(ions);
  build(builder, state, chain.getType(), chain, permute(ions, order), builder.getF64ArrayAttr(permute(z, order)),
        builder.getF64ArrayAttr(permute(x, order)));
}

LogicalResult ZXZOp::verify() {
  if (failed(verifyIonsInChain(*this, getIons(), getChainIn().getType()))) {
    return failure();
  }
  const size_t numIons = getIons().size();
  return success(succeeded(verifyOneAnglePerIon(*this, "z1", getZ1(), numIons)) &&
                 succeeded(verifyOneAnglePerIon(*this, "x", getX(), numIons)) &&
                 succeeded(verifyOneAnglePerIon(*this, "z2", getZ2(), numIons)));
}

LogicalResult RZOp::verify() {
  if (failed(verifyIonsInChain(*this, getIons(), getChainIn().getType()))) {
    return failure();
  }
  return verifyOneAnglePerIon(*this, "angles", getAngles(), getIons().size());
}

LogicalResult SymZXZOp::verify() {
  if (failed(verifyIonsInChain(*this, getIons(), getChainIn().getType()))) {
    return failure();
  }
  const size_t numIons = getIons().size();
  return success(succeeded(verifyOneAnglePerIon(*this, "z", getZ(), numIons)) &&
                 succeeded(verifyOneAnglePerIon(*this, "x", getX(), numIons)));
}

/// Wraps `angle` into (-pi, pi]. Shifting by 2 pi only changes the global phase of a rotation.
static double normalizeAngle(double angle) {
  const double wrapped = std::remainder(angle, 2.0 * std::numbers::pi);
  return wrapped <= -std::numbers::pi ? wrapped + (2.0 * std::numbers::pi) : wrapped;
}

LogicalResult RZOp::canonicalize(RZOp op, PatternRewriter& rewriter) {
  // Per ion the sum of the angles of this op and, if it directly follows one, the preceding `rz`. Chain values are
  // affine, so the preceding op has no other user.
  llvm::MapVector<int64_t, double> angles;
  auto previous = op.getChainIn().getDefiningOp<RZOp>();
  for (RZOp rz : {previous, op}) {
    if (!rz) {
      continue;
    }
    for (auto [ion, angle] : llvm::zip_equal(rz.getIons(), rz.getAngles().getAsValueRange<FloatAttr>())) {
      angles[ion] += angle.convertToDouble();
    }
  }

  SmallVector<int64_t> ions;
  SmallVector<double> sums;
  for (auto [ion, angle] : angles) {
    const double normalized = normalizeAngle(angle);
    if (normalized != 0.0) {
      ions.push_back(ion);
      sums.push_back(normalized);
    }
  }

  Value chainIn = previous ? previous.getChainIn() : op.getChainIn();
  if (ions.empty()) {
    rewriter.replaceOp(op, chainIn);
  } else if (previous || ions.size() != op.getIons().size()) {
    rewriter.replaceOpWithNewOp<RZOp>(op, chainIn, ions, sums);
  } else {
    return failure();
  }
  if (previous) {
    rewriter.eraseOp(previous);
  }
  return success();
}

//===----------------------------------------------------------------------===//
// ActiveZZOp
//===----------------------------------------------------------------------===//

void ActiveZZOp::build(OpBuilder& builder, OperationState& state, Value chain, int64_t ionA, int64_t ionB,
                       double angle) {
  auto type = cast<IonChainType>(chain.getType());
  const SmallVector<int64_t> active = type.getActiveIons();
  const auto size = static_cast<int64_t>(active.size());
  const auto* itA = llvm::find(active, ionA);
  const auto* itB = llvm::find(active, ionB);
  assert(itA != active.end() && itB != active.end() && ionA != ionB && "expected two distinct active ions");
  const int64_t a = itA - active.begin();
  const int64_t b = itB - active.begin();

  SmallVector<double> matrix(static_cast<size_t>(size * size), 0.0);
  matrix[(a * size) + b] = angle;
  matrix[(b * size) + a] = angle;
  auto matrixType = RankedTensorType::get({size, size}, Float64Type::get(builder.getContext()));
  build(builder, state, type, chain, DenseElementsAttr::get(matrixType, ArrayRef(matrix)));
}

LogicalResult ActiveZZOp::verify() {
  const int64_t numActive = getChainIn().getType().getNumActiveIons();
  const ShapedType type = getAngles().getType();
  if (type.getRank() != 2 || type.getDimSize(0) != numActive || type.getDimSize(1) != numActive) {
    return emitOpError() << "expected angles of type tensor<" << numActive << "x" << numActive << "xf64> for "
                         << numActive << " active ions, got " << type;
  }

  const SmallVector<double> values(getAngles().getValues<double>());
  for (int64_t i = 0; i < numActive; ++i) {
    if (values[(i * numActive) + i] != 0.0) {
      return emitOpError() << "angles must have a zero diagonal";
    }
    for (int64_t j = i + 1; j < numActive; ++j) {
      if (values[(i * numActive) + j] != values[(j * numActive) + i]) {
        return emitOpError() << "angles must be symmetric";
      }
    }
  }
  return success();
}

//===----------------------------------------------------------------------===//
// DelayOp
//===----------------------------------------------------------------------===//

OpFoldResult DelayOp::fold(FoldAdaptor /*adaptor*/) {
  if (getTicks() == 0) {
    return getChainIn();
  }
  return {};
}

//===----------------------------------------------------------------------===//
// RecodeOp
//===----------------------------------------------------------------------===//

void RecodeOp::build(OpBuilder& builder, OperationState& state, Value chain, ArrayRef<int64_t> ions) {
  build(builder, state, cast<IonChainType>(chain.getType()).withToggled(ions), chain);
}

LogicalResult RecodeOp::canonicalize(RecodeOp op, PatternRewriter& rewriter) {
  // Chain values are affine, so the preceding recode has no other user.
  auto previous = op.getChainIn().getDefiningOp<RecodeOp>();
  if (!previous) {
    return failure();
  }
  Value chainIn = previous.getChainIn();
  if (chainIn.getType() == op.getType()) {
    rewriter.replaceOp(op, chainIn);
  } else {
    rewriter.replaceOpWithNewOp<RecodeOp>(op, op.getType(), chainIn);
  }
  rewriter.eraseOp(previous);
  return success();
}

LogicalResult RecodeOp::verify() {
  const IonChainType in = getChainIn().getType();
  const IonChainType out = getChainOut().getType();

  if (in.getTrap() != out.getTrap()) {
    return emitOpError() << "operand and result must belong to the same trap";
  }
  if (in.getIons() != out.getIons()) {
    return emitOpError() << "operand and result must hold the same ions in the same order";
  }
  if (in == out) {
    return emitOpError() << "expected at least one activation to change";
  }
  return success();
}

//===----------------------------------------------------------------------===//
// ShuttleOp
//===----------------------------------------------------------------------===//

void ShuttleOp::build(OpBuilder& builder, OperationState& state, Value from, Value to) {
  auto fromType = cast<IonChainType>(from.getType());
  auto toType = cast<IonChainType>(to.getType());
  const IonSlot front = fromType.getSlots().front();
  build(builder, state, fromType.withoutFront(), toType.withFront(front.ion, front.active), from, to);
}

LogicalResult ShuttleOp::verify() {
  const IonChainType fromIn = getFromIn().getType();
  const IonChainType toIn = getToIn().getType();
  const IonChainType fromOut = getFromOut().getType();
  const IonChainType toOut = getToOut().getType();

  if (fromIn.getTrap() == toIn.getTrap()) {
    return emitOpError() << "cannot shuttle within trap " << fromIn.getTrap();
  }
  if (fromIn.getTrap() != fromOut.getTrap() || toIn.getTrap() != toOut.getTrap()) {
    return emitOpError() << "results must belong to the traps of the respective operands";
  }
  if (fromIn.getNumIons() == 0) {
    return emitOpError() << "cannot shuttle out of the empty chain " << fromIn;
  }
  if (toOut.getNumIons() != toIn.getNumIons() + 1 || toOut.getSlots().drop_front() != toIn.getSlots()) {
    return emitOpError() << "expected the destination to receive exactly one ion at its front, got " << toIn << " -> "
                         << toOut;
  }

  const IonSlot moved = toOut.getSlots().front();
  if (!fromIn.contains(moved.ion)) {
    return emitOpError() << "ion " << moved.ion << " is not in the source chain " << fromIn;
  }
  if (moved.ion != fromIn.getSlots().front().ion) {
    return emitOpError() << "can only shuttle the front ion of the source chain, got ion " << moved.ion
                         << " at position " << fromIn.getPosition(moved.ion) << " of " << fromIn;
  }
  if (fromIn.isActive(moved.ion) != moved.active) {
    return emitOpError() << "ion " << moved.ion << " must keep its activation";
  }
  if (fromOut != fromIn.withoutFront()) {
    return emitOpError() << "expected the source to lose exactly ion " << moved.ion << ", got " << fromIn << " -> "
                         << fromOut;
  }
  return success();
}

//===----------------------------------------------------------------------===//
// MZDOp
//===----------------------------------------------------------------------===//

LogicalResult MZDOp::verify() {
  const unsigned numIons = getChain().getType().getNumIons();
  if (numIons == 0) {
    return emitOpError() << "cannot measure the empty chain";
  }
  if (getBits().size() != numIons) {
    return emitOpError() << "expected one result per ion, got " << getBits().size() << " for " << numIons << " ions";
  }
  return success();
}

//===----------------------------------------------------------------------===//
// InterTrapZZOp
//===----------------------------------------------------------------------===//

LogicalResult InterTrapZZOp::verify() {
  const IonChainType a = getAIn().getType();
  const IonChainType b = getBIn().getType();

  if (a.getTrap() == b.getTrap()) {
    return emitOpError() << "chains must belong to different traps, both are trap " << a.getTrap();
  }
  if (getIons().size() != 2) {
    return emitOpError() << "expected exactly two ions, got " << getIons().size();
  }
  if (!a.contains(getIons()[0])) {
    return emitOpError() << "ion " << getIons()[0] << " is not in the first chain " << a;
  }
  if (!b.contains(getIons()[1])) {
    return emitOpError() << "ion " << getIons()[1] << " is not in the second chain " << b;
  }
  return success();
}

//===----------------------------------------------------------------------===//
// SwapOp
//===----------------------------------------------------------------------===//

void SwapOp::build(OpBuilder& builder, OperationState& state, Value chain, int64_t ionA, int64_t ionB) {
  const auto [low, high] = std::minmax(ionA, ionB);
  build(builder, state, chain.getType(), chain, ArrayRef<int64_t>{low, high});
}

LogicalResult SwapOp::verify() {
  if (getIons().size() != 2) {
    return emitOpError() << "expected exactly two ions, got " << getIons().size();
  }
  return verifyIonsInChain(*this, getIons(), getChainIn().getType());
}

//===----------------------------------------------------------------------===//
// TableGen'd op definitions
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/Magic/IR/MagicOps.cpp.inc"
