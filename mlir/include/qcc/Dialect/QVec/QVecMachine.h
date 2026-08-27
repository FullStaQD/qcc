// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// The machine description behind the `qvec.target` module attribute: the parameters
// a lowering has to know about the machine it is compiling for, and the queries that
// derive vector types from them.
//
// This is the one place where the otherwise target-neutral `qvec` dialect commits to
// a concrete vector architecture. The parameters are RVV's -- `VLEN`, and the `LMUL`
// register groups that fix the legal vector lengths -- and the derivations below are
// RVV's rules for turning them into types. We picked RVV because it is the vector
// architecture we know and because HiSEP-Q, our first target, is an RVV extension.
//
// It is fine that this informs the dialect: the dialect asks it only for `maxQubits()`
// and for the type carrying N qubits, and neither question is RVV-specific. Only the
// answers are. A second vector target would mean generalising this file -- most likely
// into a target-capability interface -- and would leave the operations untouched. We
// have deliberately not done that yet: with one target, there is nothing to tell us
// what the abstraction should be.
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"

#include "llvm/ADT/StringRef.h"

#include <array>
#include <optional>

namespace qcc::qvec {

/// Name of the module attribute describing the machine, whose value is a `#dlti.map`.
///
/// ```mlir
/// module attributes {qvec.target = #dlti.map<"min_vlen" = 128 : ui32>} { ... }
/// ```
///
/// The `qvec` prefix is what hands validation to `QVecDialect::verifyOperationAttribute`.
inline constexpr llvm::StringLiteral targetAttrName = "qvec.target";

/// Key naming the guaranteed lower bound on VLEN, in bits, within `targetAttrName`'s map.
inline constexpr llvm::StringLiteral minVLenKey = "min_vlen";

/// The number of bits LLVM treats as the known part of a scalable vector on RISC-V, i.e.
/// `vscale = VLEN / rvvBitsPerBlock`. Mirrors `llvm::RISCV::RVVBitsPerBlock`, which we cannot
/// include here because only the target layer may depend on the HiSEP-Q LLVM fork.
inline constexpr unsigned rvvBitsPerBlock = 64;

/// The known minimum element counts of `SupportedQVVTypes` (`RISCVInstrFormatsXQV.td`), narrowest
/// first: the `N` of the `nxv{N}i8` types the backend selects QV instructions for. Corresponds to LMUL = N / 8.
inline constexpr std::array<unsigned, 6> supportedKnownMinElements = {2, 4, 8, 16, 32, 64};

/// The machine parameters the lowerings depend on. RVV's, for now; see the file comment.
///
/// Read from the module rather than hardcoded, so that one pass serves every machine in the
/// family. Every field defaults to the weakest machine the QV extension permits, which keeps a
/// module that says nothing about its target compiling correctly -- just not optimally on a wider
/// one.
struct Machine {
  /// Guaranteed lower bound on VLEN, in bits.
  unsigned minVLen = 128;

  /// Reads the parameters from `moduleOp`'s `qvec.target`, defaulting whatever is absent.
  static Machine fromModule(mlir::ModuleOp moduleOp);

  /// The runtime element count of a register group whose type is `<vscale x n x i8>`, i.e. `vscale * n`.
  [[nodiscard]] unsigned vectorLengthFor(unsigned n) const {
    auto vscale = (minVLen / rvvBitsPerBlock);
    return vscale * n;
  }

  /// The largest qubit count the QV instructions can address, i.e. what the widest supported
  /// register group (for LMUL = LMUL_MAX) holds.
  [[nodiscard]] unsigned maxQubits() const { return vectorLengthFor(supportedKnownMinElements.back()); }

  /// The narrowest scalable vector type that carries `numQubits` qubit indices. Or nullopt if capacity is exceeded.
  [[nodiscard]] std::optional<mlir::VectorType> qubitVectorType(mlir::MLIRContext* ctx, unsigned numQubits) const;
};

} // namespace qcc::qvec
