// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// Support for the normal-form shapes of `prelimhlep.lin` (see "Normal form
// of `lin` ops" in mlir/docs/Dialects/PrelimHLEP.md): a symbolic evaluator
// for the classical bit logic inside `lin` bodies, the verifier of tagged
// shapes, and accessors that let consumers read a tagged op's parameters
// (phase angle, controlled gate, ...) without re-matching its body.
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <mlir/Dialect/SCF/IR/SCF.h>
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

/// Whether `op` is one of the `arith` ops the evaluator understands
/// (constants, zero-extension, truncation, constant shifts, and bitwise
/// or/xor/and).
bool isLinArithmeticOp(mlir::Operation* op);

/// Evaluates the classical integer values of a `prelimhlep.lin` body
/// symbolically over the flattened delinearized input bits. Only the
/// restricted bit logic accepted by `isLinArithmeticOp` is interpreted, and
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

//===----------------------------------------------------------------------===//
// Tagged shapes
//===----------------------------------------------------------------------===//

/// Verifies that `op`'s body matches its `shape` tag. Succeeds trivially
/// for untagged ops. Called from `LinOp::verify`.
mlir::LogicalResult verifyLinShape(LinOp op);

/// The `scf.if` of a `hadamard`, `phase`, or `ctrl`-shaped op.
mlir::scf::IfOp getShapeIf(LinOp op);

/// For a `phase`-shaped op: the complex scale factor as (re, im).
std::pair<double, double> getPhaseShapeFactor(LinOp op);

/// For a `ctrl`-shaped op: the controlled gate (an `x`- or `phase`-shaped
/// `lin` inside the then-branch) and the captured target value it is
/// applied to.
LinOp getCtrlShapeGate(LinOp op);
mlir::Value getCtrlShapeTarget(LinOp op);

} // namespace qcc::prelimhlep
