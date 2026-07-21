#pragma once

#include <llvm/ADT/Hashing.h>
#include <llvm/ADT/bit.h>
#include <mlir/IR/BuiltinOps.h>
#include <mlir/IR/DialectImplementation.h>
#include <mlir/IR/PatternMatch.h>
#include <mlir/IR/Visitors.h>

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
