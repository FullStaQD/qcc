// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include <array>
#include <complex>

namespace qcc::qvec {

//===----------------------------------------------------------------------===//
// Single-qubit rotations in ZXZ form
//===----------------------------------------------------------------------===//
//
// The `u_zxz` gate of the dialect and the numerics behind fusing two of them. Conventions: Rz(t) = diag(e^{-it/2},
// e^{it/2}), Rx(t) = cos(t/2) I - i sin(t/2) X, and a `ZxzAngles{z1, x, z2}` denotes Rz(z2) * Rx(x) * Rz(z1), i.e. z1
// is applied first. Equality of gates is always up to a global phase.

/// The angles of `u_zxz(z1, x, z2)` = Rz(z2) * Rx(x) * Rz(z1).
struct ZxzAngles {
  double z1 = 0.0;
  double x = 0.0;
  double z2 = 0.0;
};

using Complex = std::complex<double>;

/// A 2x2 complex matrix in row-major order.
using Matrix2x2 = std::array<Complex, 4>;

/// Wraps `angle` into (-pi, pi].
double normalizeAngle(double angle);

/// Rz(theta).
Matrix2x2 rzMatrix(double theta);

/// Rx(theta).
Matrix2x2 rxMatrix(double theta);

/// Rz(z2) * Rx(x) * Rz(z1).
Matrix2x2 zxzMatrix(const ZxzAngles& angles);

/// The matrix product `lhs * rhs`, i.e. `rhs` is applied first.
Matrix2x2 multiply(const Matrix2x2& lhs, const Matrix2x2& rhs);

/// The ZXZ angles of `unitary`, up to a global phase, each wrapped into (-pi, pi]. `unitary` must be unitary.
///
/// Numerically the x = 0 and x = pi cases are degenerate (only z1 + z2, respectively z1 - z2, is defined); they are
/// resolved by setting z2 = 0.
ZxzAngles decomposeZxz(const Matrix2x2& unitary);

/// The ZXZ angles of the gate that applies `first` and then `second`.
ZxzAngles fuseZxz(const ZxzAngles& first, const ZxzAngles& second);

} // namespace qcc::qvec
