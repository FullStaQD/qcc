// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// A symbolic evaluator for the classical bit logic inside `prelimhlep.lin`
// bodies, used by `--prelim-hlep-lin-to-gates` to recognize the gates it
// peels out of a body.
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <mlir/IR/Value.h>
#include <mlir/Support/LLVM.h>
#include <optional>
#include <string>

namespace qcc::prelimhlep {

//===----------------------------------------------------------------------===//
// Symbolic bit evaluation
//===----------------------------------------------------------------------===//

/// Symbolic value of a single classical bit inside a `lin` body: either a
/// known constant, or a (possibly negated) input bit of the enclosing
/// `prelimhlep.lin`, indexed into the flattened list of delinearized input
/// bits (operands in order, least-significant bit first).
struct BitValue {
  enum class Kind { Constant, Input };
  Kind kind;
  /// For Constant: the bit. For Input: whether the bit is negated.
  bool flag;
  /// For Input: the flattened input bit index.
  unsigned input = 0;

  static BitValue makeConstant(bool value) { return {Kind::Constant, value, 0}; }
  static BitValue makeInput(unsigned index, bool negated) { return {Kind::Input, negated, index}; }

  bool isConstant() const { return kind == Kind::Constant; }
  bool isInput() const { return kind == Kind::Input; }

  bool operator==(const BitValue& other) const {
    return kind == other.kind && flag == other.flag && input == other.input;
  }
  bool operator!=(const BitValue& other) const { return !(*this == other); }
};

using Bits = llvm::SmallVector<BitValue>;

/// Evaluates the classical integer values of a `prelimhlep.lin` body
/// symbolically over the flattened delinearized input bits. Only the
/// restricted bit logic (constants, including `prelimhlep.constant` of
/// X-/Y-basis type, zero-extension, truncation, constant shifts, bitwise
/// or/xor/and, and selects between constants) is interpreted, and
/// only as long as no bit combines two input bits (that would be general
/// reversible synthesis). Results are memoized per value.
class LinBitEvaluator {
public:
  /// Seeds the evaluator with `op`'s body block arguments. Fails if a
  /// block argument is not an integer.
  explicit LinBitEvaluator(LinOp op);

  /// Whether every block argument was seeded successfully.
  bool isValid() const { return valid; }

  /// Total number of flattened input bits.
  unsigned getNumInputBits() const { return numInputBits; }
  /// Delinearized operand index and bit position of flattened input bit `k`.
  std::pair<unsigned, unsigned> getInputBitOrigin(unsigned k) const { return origins[k]; }

  /// Pre-defines the symbolic bits of `value` (e.g. an `scf.if` result the
  /// caller has interpreted structurally).
  void define(mlir::Value value, const Bits& bits) { cache[value] = bits; }

  /// Evaluates `value`. On failure, `getFailureOp()`/`getFailureMessage()`
  /// describe the first op that could not be interpreted.
  std::optional<Bits> evaluate(mlir::Value value);

  mlir::Operation* getFailureOp() const { return failureOp; }
  const std::string& getFailureMessage() const { return failureMessage; }

private:
  std::optional<Bits> fail(mlir::Operation* op, const llvm::Twine& message);

  LinOp op;
  bool valid = true;
  unsigned numInputBits = 0;
  llvm::SmallVector<std::pair<unsigned, unsigned>> origins;
  llvm::DenseMap<mlir::Value, Bits> cache;
  mlir::Operation* failureOp = nullptr;
  std::string failureMessage;
};

} // namespace qcc::prelimhlep
