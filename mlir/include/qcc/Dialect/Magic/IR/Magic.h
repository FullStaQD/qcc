// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "qcc/Dialect/Qcc/IR/Qcc.h" // the device attribute implements `qcc::DeviceAttrInterface`.

#include "mlir/Bytecode/BytecodeOpInterface.h" // IWYU pragma: keep
#include "mlir/IR/Builders.h"                  // IWYU pragma: keep
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Dialect.h"              // IWYU pragma: keep
#include "mlir/IR/ImplicitLocOpBuilder.h" // IWYU pragma: keep
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h" // IWYU pragma: keep
#include "mlir/IR/Operation.h"
#include "mlir/IR/Types.h"                        // IWYU pragma: keep
#include "mlir/Interfaces/SideEffectInterfaces.h" // IWYU pragma: keep

#include "llvm/ADT/ArrayRef.h" // IWYU pragma: keep
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/SmallVector.h" // IWYU pragma: keep
#include "llvm/Support/LogicalResult.h"

#include <cstdint>

//===----------------------------------------------------------------------===//
// Magic Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/IR/MagicDialect.h.inc"

//===----------------------------------------------------------------------===//
// Magic Attributes
//===----------------------------------------------------------------------===//

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/Magic/IR/MagicAttrs.h.inc"

//===----------------------------------------------------------------------===//
// Magic Types
//===----------------------------------------------------------------------===//

namespace qcc::magic {

/// One entry of an ion chain: an ion (by id) and whether it takes part in the ZZ coupling (MAGIC).
struct IonSlot {
  int64_t ion;
  bool active;

  bool operator==(const IonSlot& other) const = default;
};

/// Hashes one slot: the `IonChainType` storage hashes its `ArrayRef<IonSlot>` element-wise.
/// LLVM finds this by ADL, so it keeps LLVM's snake_case name (see `Hashing.h`).
// NOLINTNEXTLINE(readability-identifier-naming)
inline llvm::hash_code hash_value(const IonSlot& slot) { return llvm::hash_combine(slot.ion, slot.active); }

} // namespace qcc::magic

#define GET_TYPEDEF_CLASSES
#include "qcc/Dialect/Magic/IR/MagicTypes.h.inc"

//===----------------------------------------------------------------------===//
// Magic Traits
//===----------------------------------------------------------------------===//

namespace qcc::magic {

/// Verifies that no chain result of `op` has a second use and that its chain operands come from a magic op. See the
/// dialect description on affine chain values.
llvm::LogicalResult verifyAffineChains(mlir::Operation* op);

/// Corresponds to `Magic_AffineChains` in tablegen. An op trait mixin in the style of `mlir::OpTrait`, hence the
/// public constructor.
template <typename ConcreteType>
class AffineChains // NOLINT(bugprone-crtp-constructor-accessibility)
    : public mlir::OpTrait::TraitBase<ConcreteType, AffineChains> {
public:
  static llvm::LogicalResult verifyTrait(mlir::Operation* op) { return verifyAffineChains(op); }
};

} // namespace qcc::magic

//===----------------------------------------------------------------------===//
// Magic Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/Magic/IR/MagicOps.h.inc"
