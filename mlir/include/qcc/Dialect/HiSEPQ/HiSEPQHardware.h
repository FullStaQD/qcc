// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// The HiSEP-Q hardware parameters a lowering has to know, and the queries that
// derive vector types from them.
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"

#include "llvm/ADT/StringRef.h"

#include <array>
#include <optional>

namespace qcc::hisepq {

/// Name of the module attribute describing the machine, whose value is a `#dlti.map`.
///
/// ```mlir
/// module attributes {hisepq.target = #dlti.map<"min_vlen" = 128 : ui32>} { ... }
/// ```
///
/// The `hisepq` prefix is what hands validation to `HiSEPQDialect::verifyOperationAttribute`.
inline constexpr llvm::StringLiteral targetAttrName = "hisepq.target";

/// Key naming the guaranteed lower bound on VLEN, in bits, within `targetAttrName`'s map.
inline constexpr llvm::StringLiteral minVLenKey = "min_vlen";

/// The number of bits LLVM treats as the known part of a scalable vector on RISC-V, i.e.
/// `vscale = VLEN / rvvBitsPerBlock`. Mirrors `llvm::RISCV::RVVBitsPerBlock`, which we cannot
/// include here because only the target layer may depend on the HiSEP-Q LLVM fork.
inline constexpr unsigned rvvBitsPerBlock = 64;

/// The known minimum element counts of `SupportedQVVTypes` (`RISCVInstrFormatsXQV.td`), narrowest
/// first: the `N` of the `nxv{N}i8` types the backend selects QV instructions for. Corresponds to LMUL = N / 8.
inline constexpr std::array<unsigned, 6> supportedKnownMinElements = {2, 4, 8, 16, 32, 64};

/// The hardware parameters the HiSEP-Q lowerings depend on.
///
/// Read from the module rather than hardcoded, so that one pass serves every machine in the
/// family. Every field defaults to the weakest machine the QV extension permits, which keeps a
/// module that says nothing about its target compiling correctly -- just not optimally on a wider
/// one.
struct Hardware {
  /// Guaranteed lower bound on VLEN, in bits.
  unsigned minVLen = 128;

  /// Reads the parameters from `moduleOp`'s `hisepq.target`, defaulting whatever is absent.
  static Hardware fromModule(mlir::ModuleOp moduleOp);

  /// The runtime element count of a register group whose type is `<vscale x n x i8>`, i.e. `vscale * n`.
  [[nodiscard]] unsigned elementsFor(unsigned n) const {
    auto vscale = (minVLen / rvvBitsPerBlock);
    return vscale * n;
  }

  /// The largest qubit count the QV instructions can address, i.e. what the widest supported
  /// register group (for LMUL = LMUL_MAX) holds.
  [[nodiscard]] unsigned maxQubits() const { return elementsFor(supportedKnownMinElements.back()); }

  /// The narrowest scalable vector type that carries `numQubits` qubit indices. Or nullopt if capacity is exceeded.
  [[nodiscard]] std::optional<mlir::VectorType> qubitVectorType(mlir::MLIRContext* ctx, unsigned numQubits) const;
};

} // namespace qcc::hisepq
