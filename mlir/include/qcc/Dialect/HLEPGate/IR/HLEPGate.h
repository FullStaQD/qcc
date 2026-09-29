// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <cstdint>
#include <mlir/Bytecode/BytecodeOpInterface.h>
#include <mlir/IR/BuiltinTypes.h>
#include <mlir/Interfaces/InferTypeOpInterface.h>
#include <mlir/Interfaces/SideEffectInterfaces.h>
#include <optional>

//===----------------------------------------------------------------------===//
// HLEPGate type predicates
//===----------------------------------------------------------------------===//

namespace qcc::hlepgate {

/// `!prelimhlep.lin<i1>`, the type of a single qubit.
inline mlir::Type getQubitType(mlir::MLIRContext* context) {
  return prelimhlep::LinType::get(context, mlir::IntegerType::get(context, 1));
}

/// The number of qubits of a `!prelimhlep.lin<i<n>>` register, or
/// `std::nullopt` for any other type.
inline std::optional<unsigned> getRegisterWidth(mlir::Type type) {
  auto linType = mlir::dyn_cast<prelimhlep::LinType>(type);
  if (!linType) {
    return std::nullopt;
  }
  auto intType = mlir::dyn_cast<mlir::IntegerType>(linType.getElementType());
  if (!intType || !intType.isSignless()) {
    return std::nullopt;
  }
  return intType.getWidth();
}

/// Whether `type` is `!prelimhlep.lin<i1>`.
inline bool isQubitType(mlir::Type type) { return getRegisterWidth(type) == 1U; }

} // namespace qcc::hlepgate

//===----------------------------------------------------------------------===//
// HLEPGate Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/HLEPGate/IR/HLEPGateDialect.h.inc"

//===----------------------------------------------------------------------===//
// HLEPGate Attributes
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/HLEPGate/IR/HLEPGateEnums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/HLEPGate/IR/HLEPGateAttrs.h.inc"

//===----------------------------------------------------------------------===//
// HLEPGate Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/HLEPGate/IR/HLEPGateOps.h.inc"
