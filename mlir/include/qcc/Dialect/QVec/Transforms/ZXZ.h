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

/// The angles of `u_zxz(z1, x, z2)` = Rz(z2) * Rx(x) * Rz(z1).
struct ZXZAngles {
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
Matrix2x2 zxzMatrix(const ZXZAngles& angles);

/// The matrix product `lhs * rhs`, i.e. `rhs` is applied first.
Matrix2x2 multiply(const Matrix2x2& lhs, const Matrix2x2& rhs);

/// The ZXZ angles of `unitary`, up to a global phase, each wrapped into (-pi, pi]. `unitary` must be unitary.
///
/// Numerically the x = 0 and x = pi cases are degenerate (only z1 + z2, respectively z1 - z2, is defined); they are
/// resolved by setting z2 = 0.
ZXZAngles decomposeZXZ(const Matrix2x2& unitary);

/// The ZXZ angles of the gate that applies `first` and then `second`.
ZXZAngles fuseZXZ(const ZXZAngles& first, const ZXZAngles& second);

} // namespace qcc::qvec
