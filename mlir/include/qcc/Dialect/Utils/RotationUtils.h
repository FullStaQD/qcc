// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "llvm/Support/raw_ostream.h"

#include <array>
#include <cassert>
#include <complex>

namespace qcc {

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

/// A 2x2 complex matrix.
class Matrix2x2 {
public:
  /// The elements in row-major order: `m00 m01` over `m10 m11`.
  constexpr Matrix2x2(Complex m00, Complex m01, Complex m10, Complex m11) : elements{m00, m01, m10, m11} {}

  /// Access a matrix element.
  constexpr Complex operator()(unsigned row, unsigned col) const {
    assert(row < 2 && col < 2 && "index out of bounds");
    return elements[(2 * row) + col];
  }

  /// Elementwise addition.
  Matrix2x2& operator+=(const Matrix2x2& rhs);

  /// Elementwise subtraction.
  Matrix2x2& operator-=(const Matrix2x2& rhs);

  /// Scalar multiplication.
  Matrix2x2& operator*=(Complex scalar);

  /// The conjugate transpose.
  [[nodiscard]] Matrix2x2 adjoint() const;

  /// The sum of the diagonal elements.
  [[nodiscard]] Complex trace() const;

  /// The Hilbert-Schmidt (Frobenius) norm, i.e. the l2 norm of the elements as a vector.
  [[nodiscard]] double hilbertSchmidtNorm() const;

private:
  std::array<Complex, 4> elements;
};

/// Wraps `angle` into (-pi, pi]. Note Rz(theta + 2 pi) = -Rz(theta) (likewise Rx), so this flips the global phase,
/// which becomes observable once the rotation is controlled.
double normalizeAngle(double angle);

/// Rz(theta).
Matrix2x2 rzMatrix(double theta);

/// Rx(theta).
Matrix2x2 rxMatrix(double theta);

/// Rz(z2) * Rx(x) * Rz(z1).
Matrix2x2 zxzMatrix(const ZXZAngles& angles);

/// The matrix product `lhs * rhs`, i.e. `rhs` is applied first.
Matrix2x2 operator*(const Matrix2x2& lhs, const Matrix2x2& rhs);

/// `scalar` times `matrix`.
Matrix2x2 operator*(Complex scalar, Matrix2x2 matrix);

/// The elementwise sum `lhs + rhs`.
Matrix2x2 operator+(Matrix2x2 lhs, const Matrix2x2& rhs);

/// The elementwise difference `lhs - rhs`.
Matrix2x2 operator-(Matrix2x2 lhs, const Matrix2x2& rhs);

/// Prints `matrix` as `[[m00, m01], [m10, m11]]` with elements `(re, im)`.
llvm::raw_ostream& operator<<(llvm::raw_ostream& os, const Matrix2x2& matrix);

/// The ZXZ angles of `unitary`, up to a global phase, each wrapped into (-pi, pi]. `unitary` must be unitary.
///
/// Numerically the x = 0 and x = pi cases are degenerate (only z1 + z2, respectively z1 - z2, is defined); they are
/// resolved by setting z2 = 0.
ZXZAngles decomposeZXZ(const Matrix2x2& unitary);

/// The ZXZ angles of the gate that applies `first` and then `second`. If one of the two is an Rz, use the overloads
/// below instead: they are exact.
ZXZAngles fuseZXZ(const ZXZAngles& first, const ZXZAngles& second);

/// The ZXZ angles of the gate that applies Rz(`zAngle`) and then `zxz`. Each angle is wrapped into (-pi, pi].
ZXZAngles fuseZXZ(double zAngle, const ZXZAngles& zxz);

/// The ZXZ angles of the gate that applies `zxz` and then Rz(`zAngle`). Each angle is wrapped into (-pi, pi].
ZXZAngles fuseZXZ(const ZXZAngles& zxz, double zAngle);

} // namespace qcc
