// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//
//
// The HiSEP-Q machine description: the parameters a lowering has to know about the
// machine it is compiling for, and the queries that derive vector types from them.
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"

#include <array>
#include <cstdint>
#include <optional>

namespace qcc::hisepq {

/// Machine parameters for a concrete HiSEP-Q control system.
///
/// Constructor args:
/// - `minVLen`: Known lower bound on VLEN (see RVV spec).
/// - `qubitElementWidth` (aka QEW): How many bits to encode a qubit. Corresponds to SEW (see RVV spec).
///
/// Both parameters are assumed to be validated by caller. See the constructor's asserts for precise requirements.
class HiSEPQMachine {
public:
  HiSEPQMachine(unsigned minVLen, unsigned qubitElementWidth);

  /// Guaranteed lower bound on VLEN (number of bits).
  [[nodiscard]] unsigned getMinVLen() const { return minVLen; }

  /// QEW (number of bits).
  [[nodiscard]] unsigned getQubitElementWidth() const { return qubitElementWidth; }

  /// The largest qubit count the QV instructions can address, i.e. what the widest supported register group holds:
  /// `maxLMUL * minVLen / QEW`.
  [[nodiscard]] unsigned maxQubits() const;

  /// The highest qubit index QEW can represent, i.e. `2^QEW - 1`.
  [[nodiscard]] uint64_t maxQubitIndex() const;

  /// The narrowest scalable vector type that carries `numQubits` qubit indices. Or nullopt if capacity is exceeded.
  [[nodiscard]] std::optional<mlir::VectorType> qubitVectorType(mlir::MLIRContext* ctx, unsigned numQubits) const;

private:
  /// How many `rvvBitsPerBlock`-sized blocks one vector register holds.
  ///
  /// NOTE: That is LLVM terminology. By definition the number of elements in a `vector<[N]xi{QEW}>` is `vscale*N`.
  [[nodiscard]] unsigned vscale() const { return minVLen / rvvBitsPerBlock; }

  /// Returns `N=LMUL*64/QEW` where `lmul8` is 8 times LMUL.
  ///
  /// NOTE: This implies that the type `vector<[N]xi{QEW}>` corresponds to the given LMUL.
  [[nodiscard]] unsigned knownMinElementsFor(unsigned lmul8) const;

  /// The number of bits LLVM treats as the known part of a scalable vector on RISC-V. Mirrors
  /// `llvm::RISCV::RVVBitsPerBlock`, which we cannot include here because only the target layer
  /// may depend on the HiSEP-Q LLVM fork.
  static constexpr unsigned rvvBitsPerBlock = 64;

  /// The LMUL register groups the QV instructions address, narrowest first, stored as eighth times
  /// LMUL to keep the fractional ones integral: {mf4, mf2, m1, m2, m4, m8}.
  ///
  /// NOTE: Could become a pass option in the future.
  static constexpr std::array<unsigned, 6> supportedLMul8 = {2, 4, 8, 16, 32, 64};

  unsigned minVLen;
  unsigned qubitElementWidth; // aka QEW
};

} // namespace qcc::hisepq
