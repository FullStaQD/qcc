// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Utils/RotationUtils.h"

#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstddef>
#include <numbers>

using namespace qcc;

Matrix2x2& Matrix2x2::operator+=(const Matrix2x2& rhs) {
  for (std::size_t i = 0; i < elements.size(); ++i) {
    elements[i] += rhs.elements[i];
  }
  return *this;
}

Matrix2x2& Matrix2x2::operator-=(const Matrix2x2& rhs) {
  for (std::size_t i = 0; i < elements.size(); ++i) {
    elements[i] -= rhs.elements[i];
  }
  return *this;
}

Matrix2x2 Matrix2x2::adjoint() const {
  const Matrix2x2& m = *this;
  return {
      std::conj(m(0, 0)), std::conj(m(1, 0)), //
      std::conj(m(0, 1)), std::conj(m(1, 1))  //
  };
}

Complex Matrix2x2::trace() const { return (*this)(0, 0) + (*this)(1, 1); }

double Matrix2x2::infinityNorm() const {
  double norm = 0.0;
  for (const Complex& element : elements) {
    norm = std::max(norm, std::abs(element));
  }
  return norm;
}

double qcc::normalizeAngle(double angle) {
  constexpr double twoPi = 2.0 * std::numbers::pi;
  double wrapped = std::remainder(angle, twoPi); // in [-pi, pi]
  if (wrapped <= -std::numbers::pi) {
    wrapped += twoPi;
  }
  return wrapped + 0.0; // turns -0.0 into 0.0
}

Matrix2x2 qcc::rzMatrix(double theta) {
  return {
      std::polar(1.0, -theta / 2), Complex{0.0}, //
      Complex{0.0}, std::polar(1.0, theta / 2)   //
  };
}

Matrix2x2 qcc::rxMatrix(double theta) {
  const Complex diag{std::cos(theta / 2), 0.0};
  const Complex offDiag{0.0, -std::sin(theta / 2)};
  return {
      diag, offDiag, //
      offDiag, diag  //
  };
}

Matrix2x2 qcc::operator*(const Matrix2x2& lhs, const Matrix2x2& rhs) {
  return {
      (lhs(0, 0) * rhs(0, 0)) + (lhs(0, 1) * rhs(1, 0)), //
      (lhs(0, 0) * rhs(0, 1)) + (lhs(0, 1) * rhs(1, 1)), //
      (lhs(1, 0) * rhs(0, 0)) + (lhs(1, 1) * rhs(1, 0)), //
      (lhs(1, 0) * rhs(0, 1)) + (lhs(1, 1) * rhs(1, 1))  //
  };
}

Matrix2x2 qcc::operator*(Complex scalar, const Matrix2x2& matrix) {
  return {
      scalar * matrix(0, 0), scalar * matrix(0, 1), //
      scalar * matrix(1, 0), scalar * matrix(1, 1)  //
  };
}

Matrix2x2 qcc::operator+(Matrix2x2 lhs, const Matrix2x2& rhs) {
  lhs += rhs;
  return lhs;
}

Matrix2x2 qcc::operator-(Matrix2x2 lhs, const Matrix2x2& rhs) {
  lhs -= rhs;
  return lhs;
}

llvm::raw_ostream& qcc::operator<<(llvm::raw_ostream& os, const Matrix2x2& matrix) {
  const auto element = [&](unsigned row, unsigned col) {
    return llvm::format("(%g, %g)", matrix(row, col).real(), matrix(row, col).imag());
  };
  return os << "[[" << element(0, 0) << ", " << element(0, 1) << "], [" << element(1, 0) << ", " << element(1, 1)
            << "]]";
}

Matrix2x2 qcc::zxzMatrix(const ZXZAngles& angles) {
  return rzMatrix(angles.z2) * rxMatrix(angles.x) * rzMatrix(angles.z1);
}

ZXZAngles qcc::decomposeZXZ(const Matrix2x2& unitary) {
  // Bring the matrix into SU(2): det(U / sqrt(det U)) = 1. Then U = [[a, b], [-conj(b), conj(a)]] with
  //   a = cos(x/2) e^{-i(z1+z2)/2}   and   b = -i sin(x/2) e^{i(z1-z2)/2}
  // for the ZXZ product, which pins down the angles from the magnitudes and arguments of a and b. The sign ambiguity
  // of the square root is a global phase.
  const Complex det = (unitary(0, 0) * unitary(1, 1)) - (unitary(0, 1) * unitary(1, 0));
  const Complex scale = 1.0 / std::sqrt(det);
  const Complex a = unitary(0, 0) * scale;
  const Complex b = unitary(0, 1) * scale;

  constexpr double eps = 1e-12;
  constexpr double pi = std::numbers::pi;
  ZXZAngles angles;
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

ZXZAngles qcc::fuseZXZ(const ZXZAngles& first, const ZXZAngles& second) {
  return decomposeZXZ(zxzMatrix(second) * zxzMatrix(first));
}
