// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/Transforms/Zxz.h"

#include <cmath>
#include <complex>
#include <numbers>

using namespace qcc::qvec;

double qcc::qvec::normalizeAngle(double angle) {
  constexpr double twoPi = 2.0 * std::numbers::pi;
  double wrapped = std::remainder(angle, twoPi); // in [-pi, pi]
  if (wrapped <= -std::numbers::pi) {
    wrapped += twoPi;
  }
  return wrapped + 0.0; // turns -0.0 into 0.0
}

Matrix2x2 qcc::qvec::rzMatrix(double theta) {
  return {
      std::polar(1.0, -theta / 2),
      Complex{0.0}, //
      Complex{0.0},
      std::polar(1.0, theta / 2),
  };
}

Matrix2x2 qcc::qvec::rxMatrix(double theta) {
  const Complex diag{std::cos(theta / 2), 0.0};
  const Complex offDiag{0.0, -std::sin(theta / 2)};
  return {
      diag,
      offDiag, //
      offDiag,
      diag,
  };
}

Matrix2x2 qcc::qvec::multiply(const Matrix2x2& lhs, const Matrix2x2& rhs) {
  return {
      (lhs[0] * rhs[0]) + (lhs[1] * rhs[2]),
      (lhs[0] * rhs[1]) + (lhs[1] * rhs[3]), //
      (lhs[2] * rhs[0]) + (lhs[3] * rhs[2]),
      (lhs[2] * rhs[1]) + (lhs[3] * rhs[3]),
  };
}

Matrix2x2 qcc::qvec::zxzMatrix(const ZxzAngles& angles) {
  return multiply(rzMatrix(angles.z2), multiply(rxMatrix(angles.x), rzMatrix(angles.z1)));
}

ZxzAngles qcc::qvec::decomposeZxz(const Matrix2x2& unitary) {
  // Bring the matrix into SU(2): det(U / sqrt(det U)) = 1. Then U = [[a, b], [-conj(b), conj(a)]] with
  //   a = cos(x/2) e^{-i(z1+z2)/2}   and   b = -i sin(x/2) e^{i(z1-z2)/2}
  // for the ZXZ product, which pins down the angles from the magnitudes and arguments of a and b. The sign ambiguity
  // of the square root is a global phase.
  const Complex det = (unitary[0] * unitary[3]) - (unitary[1] * unitary[2]);
  const Complex scale = 1.0 / std::sqrt(det);
  const Complex a = unitary[0] * scale;
  const Complex b = unitary[1] * scale;

  constexpr double eps = 1e-12;
  constexpr double pi = std::numbers::pi;
  ZxzAngles angles;
  if (std::abs(b) < eps) { // x = 0: a diagonal gate, only z1 + z2 matters.
    angles.z1 = -2.0 * std::arg(a);
  } else if (std::abs(a) < eps) { // x = pi: only z1 - z2 matters.
    angles.x = pi;
    angles.z1 = (2.0 * std::arg(b)) + pi;
  } else {
    angles.x = 2.0 * std::atan2(std::abs(b), std::abs(a));
    angles.z1 = -std::arg(a) + std::arg(b) + (pi / 2);
    angles.z2 = -std::arg(a) - std::arg(b) - (pi / 2);
  }
  angles.z1 = normalizeAngle(angles.z1);
  angles.x = normalizeAngle(angles.x);
  angles.z2 = normalizeAngle(angles.z2);
  return angles;
}

ZxzAngles qcc::qvec::fuseZxz(const ZxzAngles& first, const ZxzAngles& second) {
  return decomposeZxz(multiply(zxzMatrix(second), zxzMatrix(first)));
}
