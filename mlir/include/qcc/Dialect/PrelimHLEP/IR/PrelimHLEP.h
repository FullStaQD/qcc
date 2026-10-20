// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include <llvm/ADT/Hashing.h>
#include <llvm/ADT/bit.h>
#include <mlir/IR/BuiltinOps.h>
#include <mlir/IR/DialectImplementation.h>
#include <mlir/IR/PatternMatch.h>
#include <mlir/IR/Visitors.h>
#include <mlir/Interfaces/SideEffectInterfaces.h>

namespace qcc::prelimhlep {

/// A single-qubit Pauli operator, used as a factor of a `HamiltonianAttr`
/// term (see PrelimHLEPAttrs.td).
enum class PauliKind { X, Y, Z };

/// A Pauli operator acting on a specific qubit, e.g. `X[0]`. One of the
/// factors making up a `HamiltonianAttr` term.
struct PauliFactor {
  PauliKind kind;
  int64_t qubit;

  bool operator==(const PauliFactor& other) const { return kind == other.kind && qubit == other.qubit; }
};

inline llvm::hash_code hash_value(const PauliFactor& factor) { return llvm::hash_combine(factor.kind, factor.qubit); }

/// The coefficient and factor count of a single `HamiltonianAttr` term.
/// Paired with `hash_value`/`operator==` overloads (rather than storing a
/// bare `double`, for which LLVM's hashing utilities have no built-in
/// support) so it can be used as an `AttrDef` array parameter element.
///
/// TODO: We likely want to have fixed-point types instead of doubles
/// here anyways, so this might be deprecated. A bit of a hack now.
struct HamiltonianTermHeader {
  double coefficient;
  int64_t size;

  bool operator==(const HamiltonianTermHeader& other) const {
    return coefficient == other.coefficient && size == other.size;
  }
};

inline llvm::hash_code hash_value(const HamiltonianTermHeader& header) {
  return llvm::hash_combine(llvm::bit_cast<uint64_t>(header.coefficient), header.size);
}

/// The hidden world that the partial linearization of a program is a
/// family over. Measurements read and write it (see PrelimHLEPEffects.td).
struct WorldResource : mlir::SideEffects::Resource::Base<WorldResource> {
  [[nodiscard]] llvm::StringRef getName() const final { return "prelimhlep::World"; }
  [[nodiscard]] bool isAddressable() const override { return false; }
};

/// The quantum state that linear values are allocated in and freed from.
/// Addressable, since its effects are attached to the linear values, which
/// act as handles into it.
///
/// TODO: Understand the side-effect implications of this better.
struct QuantumStateResource : mlir::SideEffects::Resource::Base<QuantumStateResource> {
  [[nodiscard]] llvm::StringRef getName() const final { return "prelimhlep::QuantumState"; }
};

} // namespace qcc::prelimhlep

//===----------------------------------------------------------------------===//
// PrelimHLEP Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPDialect.h.inc"

//===----------------------------------------------------------------------===//
// PrelimHLEP Types
//===----------------------------------------------------------------------===//

#define GET_TYPEDEF_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPTypes.h.inc"

//===----------------------------------------------------------------------===//
// PrelimHLEP Attributes
//===----------------------------------------------------------------------===//

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPAttrs.h.inc"

//===----------------------------------------------------------------------===//
// PrelimHLEP Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPOps.h.inc"
