// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QRef/IR/QRef.h"
#include "qcc/Dialect/Qcc/IR/Qcc.h"

#include "mlir/IR/BuiltinTypes.h"     // IWYU pragma: keep
#include "mlir/IR/OpImplementation.h" // IWYU pragma: keep
#include "mlir/IR/Operation.h"        // IWYU pragma: keep

#include <cstdint>
#include <optional>

using namespace mlir;
using namespace qcc::qref;

#include "qcc/Dialect/QRef/IR/QRefDialect.cpp.inc"

#define GET_OP_CLASSES
#include "qcc/Dialect/QRef/IR/QRefOps.cpp.inc"

//===----------------------------------------------------------------------===//
// Verifiers
//===----------------------------------------------------------------------===//

LogicalResult SingleOp::verify() { return qcc::detail::verifyGateParams(*this, getGateKind(), getParams()); }

LogicalResult PairOp::verify() {
  if (failed(qcc::detail::verifyGateParams(*this, getGateKind(), getParams()))) {
    return failure();
  }

  // Only the obvious cases: other references may name the same qubit, which only resolving them reveals.
  if (getLhs() == getRhs()) {
    return emitOpError() << "requires distinct qubits, but lhs and rhs are the same value";
  }
  const std::optional<int64_t> lhsIndex = qcc::getStaticRefIndex(getLhs());
  if (lhsIndex && lhsIndex == qcc::getStaticRefIndex(getRhs())) {
    return emitOpError() << "requires distinct qubits, but lhs and rhs both name static qubit " << *lhsIndex;
  }
  return success();
}

//===----------------------------------------------------------------------===//
// Dialect
//===----------------------------------------------------------------------===//

void QRefDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "qcc/Dialect/QRef/IR/QRefOps.cpp.inc"
      >();
}
