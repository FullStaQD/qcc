// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/IR/Magic.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep

#include <cstdint>
#include <iterator>

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

LogicalResult qcc::magic::verifyAffineChainOperands(Operation* op) {
  for (OpOperand& operand : op->getOpOperands()) {
    Value chain = operand.get();
    if (!isa<IonChainType>(chain.getType()) || chain.hasOneUse()) {
      continue;
    }

    // Report the fork at the later user only, so that a fork yields one diagnostic. Users in other blocks count as
    // later: the first user in our block is the only legitimate one.
    const bool isFirstUser = llvm::none_of(chain.getUsers(), [&](Operation* user) {
      return user != op && (user->getBlock() != op->getBlock() || user->isBeforeInBlock(op));
    });
    if (isFirstUser) {
      continue;
    }
    return op->emitOpError() << "chain operand #" << operand.getOperandNumber()
                             << " is used more than once, but chain values are affine";
  }
  return success();
}

/// Verifies that `ions` (ids) are distinct and all contained in `chain`.
static LogicalResult verifyIonsInChain(Operation* op, ArrayRef<int64_t> ions, IonChainType chain) {
  llvm::SmallSet<int64_t, 8> seen;
  for (const int64_t ion : ions) {
    if (!chain.contains(ion)) {
      return op->emitOpError() << "ion " << ion << " is not in the chain " << chain;
    }
    if (!seen.insert(ion).second) {
      return op->emitOpError() << "ion " << ion << " is listed more than once";
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

LogicalResult ZxzOp::verify() {
  if (failed(verifyIonsInChain(*this, getIons(), getChainIn().getType()))) {
    return failure();
  }
  const size_t numIons = getIons().size();
  return success(succeeded(verifyOneAnglePerIon(*this, "z1", getZ1(), numIons)) &&
                 succeeded(verifyOneAnglePerIon(*this, "x", getX(), numIons)) &&
                 succeeded(verifyOneAnglePerIon(*this, "z2", getZ2(), numIons)));
}

LogicalResult RzOp::verify() {
  if (failed(verifyIonsInChain(*this, getIons(), getChainIn().getType()))) {
    return failure();
  }
  return verifyOneAnglePerIon(*this, "angles", getAngles(), getIons().size());
}

LogicalResult SymZxzOp::verify() {
  if (failed(verifyIonsInChain(*this, getIons(), getChainIn().getType()))) {
    return failure();
  }
  const size_t numIons = getIons().size();
  return success(succeeded(verifyOneAnglePerIon(*this, "z", getZ(), numIons)) &&
                 succeeded(verifyOneAnglePerIon(*this, "x", getX(), numIons)));
}

//===----------------------------------------------------------------------===//
// ActiveZzOp
//===----------------------------------------------------------------------===//

LogicalResult ActiveZzOp::verify() {
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
// RecodeOp
//===----------------------------------------------------------------------===//

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
  if (fromIn.isActive(moved.ion) != moved.active) {
    return emitOpError() << "ion " << moved.ion << " must keep its activation";
  }

  SmallVector<IonSlot> expected(fromIn.getSlots());
  expected.erase(std::next(expected.begin(), fromIn.getPosition(moved.ion)));
  if (fromOut.getSlots() != ArrayRef(expected)) {
    return emitOpError() << "expected the source to lose exactly ion " << moved.ion << ", got " << fromIn << " -> "
                         << fromOut;
  }
  return success();
}

//===----------------------------------------------------------------------===//
// MzdOp
//===----------------------------------------------------------------------===//

LogicalResult MzdOp::verify() {
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
// InterTrapZzOp
//===----------------------------------------------------------------------===//

LogicalResult InterTrapZzOp::verify() {
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
