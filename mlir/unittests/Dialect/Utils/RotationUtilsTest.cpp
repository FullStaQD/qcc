// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Utils/RotationUtils.h"

#include "gmock/gmock.h"
#include "gtest/gtest.h"

#include <array>
#include <cmath>
#include <complex>
#include <numbers>
#include <utility>

using namespace qcc;

constexpr double pi = std::numbers::pi;

/// The absolute tolerance of the numerical checks.
constexpr double tolerance = 1e-12;

/// An arbitrary global phase.
static const Complex globalPhase = std::polar(1.0, 0.7);

/// The global phase that brings `rhs` closest to `lhs` in the Frobenius norm.
static Complex bestGlobalPhase(const Matrix2x2& lhs, const Matrix2x2& rhs) {
  const Complex overlap = (rhs.adjoint() * lhs).trace();
  return overlap / std::abs(overlap);
}

/// Matches a matrix that is elementwise within `maxError` of `expected`.
MATCHER_P2(MatrixNear, expected, maxError, "") {
  const double deviation = (arg - expected).infinityNorm();
  *result_listener << "max deviation " << deviation;
  return deviation <= maxError;
}

/// Like `MatrixNear`, but up to a global phase.
MATCHER_P2(MatrixNearUpToGlobalPhase, expected, maxError, "") {
  const double deviation = (arg - (bestGlobalPhase(arg, expected) * expected)).infinityNorm();
  *result_listener << "max deviation " << deviation << " after aligning the global phase";
  return deviation <= maxError;
}

TEST(RotationUtilsTest, NormalizeAngle) {
  // The range is (-pi, pi]: values inside are unchanged, pi stays, -pi becomes pi.
  EXPECT_DOUBLE_EQ(normalizeAngle(1.0), 1.0);
  EXPECT_DOUBLE_EQ(normalizeAngle(-1.0), -1.0);
  EXPECT_DOUBLE_EQ(normalizeAngle(pi), pi);
  EXPECT_DOUBLE_EQ(normalizeAngle(-pi), pi);

  // Values outside are wrapped by multiples of 2 pi.
  EXPECT_DOUBLE_EQ(normalizeAngle(4.0), 4.0 - (2 * pi));
  EXPECT_DOUBLE_EQ(normalizeAngle(-4.0), -4.0 + (2 * pi));
  EXPECT_DOUBLE_EQ(normalizeAngle(100.0), 100.0 - (32 * pi));

  // The result is never -0.0.
  for (double angle : {0.0, -0.0, 2 * pi, -2 * pi}) {
    SCOPED_TRACE(testing::Message() << "angle = " << angle);
    EXPECT_EQ(normalizeAngle(angle), 0.0);
    EXPECT_FALSE(std::signbit(normalizeAngle(angle)));
  }
}

TEST(RotationUtilsTest, MatrixOperations) {
  // Unlike for the other matrix operations, the tests below would not notice errors in these.
  const Matrix2x2 matrix{
      Complex{1, 2}, Complex{3, 4}, //
      Complex{5, 6}, Complex{7, 8}  //
  };

  // `+` has no other user.
  const Matrix2x2 sum{
      2.0, Complex{8, -2}, //
      Complex{8, 2}, 14.0  //
  };
  EXPECT_THAT(matrix + matrix.adjoint(), MatrixNear(sum, tolerance));

  // For unitaries every diagonal element of V^dagger U carries the global phase.
  EXPECT_EQ(matrix.trace(), Complex(8, 10));

  // The tolerance checks work with any norm.
  EXPECT_DOUBLE_EQ(matrix.infinityNorm(), std::sqrt(113.0)); // |7 + 8i|
}

TEST(RotationUtilsTest, Matchers) {
  // The other tests rely on the matchers, so make sure they can fail.
  const Matrix2x2 matrix = rxMatrix(0.5);
  EXPECT_THAT(globalPhase * matrix, MatrixNearUpToGlobalPhase(matrix, tolerance));
  EXPECT_THAT(globalPhase * matrix, testing::Not(MatrixNear(matrix, tolerance)));

  // A relative phase is not a global phase.
  EXPECT_THAT(rzMatrix(0.5), testing::Not(MatrixNearUpToGlobalPhase(rzMatrix(-0.5), tolerance)));
}

TEST(RotationUtilsTest, RotationMatrices) {
  // Pins the conventions, including the global phase: Rz(theta) = diag(e^{-i theta/2}, e^{i theta/2}) and
  // Rx(theta) = cos(theta/2) I - i sin(theta/2) X.
  constexpr double s = std::numbers::sqrt2 / 2;
  const Matrix2x2 rz{
      Complex{s, -s}, 0.0, //
      0.0, Complex{s, s}   //
  };
  const Matrix2x2 rx{
      s, Complex{0.0, -s}, //
      Complex{0.0, -s}, s  //
  };
  EXPECT_THAT(rzMatrix(pi / 2), MatrixNear(rz, tolerance));
  EXPECT_THAT(rxMatrix(pi / 2), MatrixNear(rx, tolerance));
}

TEST(RotationUtilsTest, DecomposeZXZRoundTrip) {
  constexpr double s = std::numbers::sqrt2 / 2;
  const auto cases = std::to_array<std::pair<const char*, Matrix2x2>>({
      // Written by hand, so independent of `zxzMatrix`.
      {"Hadamard", Matrix2x2{s, s, s, -s}},
      // Unlike for the Hadamard z1 != z2, and the arguments of the matrix elements lie beyond +-pi/2.
      {"generic", zxzMatrix({.z1 = 2.5, .x = 2.0, .z2 = 3.0})},
      // Small but real deviations from x = 0 and x = pi must survive, i.e. the degenerate cases must not kick in early.
      {"x near 0", zxzMatrix({.z1 = 0.3, .x = 1e-9, .z2 = -2.0})},
      {"x near pi", zxzMatrix({.z1 = 0.3, .x = pi - 1e-9, .z2 = -2.0})},
  });
  for (const auto& [name, unitary] : cases) {
    SCOPED_TRACE(name);
    // The global phase makes det != 1.
    const Matrix2x2 input = globalPhase * unitary;
    EXPECT_THAT(zxzMatrix(decomposeZXZ(input)), MatrixNearUpToGlobalPhase(input, tolerance));
  }
}

TEST(RotationUtilsTest, DecomposeZXZDegenerate) {
  // x = 0 only defines z1 + z2, and x = pi only z1 - z2. Both are resolved by z2 = 0.
  const ZXZAngles diagonal = decomposeZXZ(globalPhase * zxzMatrix({.z1 = 0.5, .x = 0.0, .z2 = 0.3}));
  EXPECT_NEAR(diagonal.z1, 0.8, tolerance);
  EXPECT_NEAR(diagonal.x, 0.0, tolerance);
  EXPECT_NEAR(diagonal.z2, 0.0, tolerance);

  const ZXZAngles antiDiagonal = decomposeZXZ(globalPhase * zxzMatrix({.z1 = 0.5, .x = pi, .z2 = 0.3}));
  EXPECT_NEAR(antiDiagonal.z1, 0.2, tolerance);
  EXPECT_NEAR(antiDiagonal.x, pi, tolerance);
  EXPECT_NEAR(antiDiagonal.z2, 0.0, tolerance);
}

TEST(RotationUtilsTest, FuseZXZ) {
  // Rx(0.5) followed by Rz(0.25) is Rz(0.25) * Rx(0.5).
  const ZXZAngles fused = fuseZXZ({.x = 0.5}, {.z1 = 0.25});
  EXPECT_NEAR(fused.z1, 0.0, tolerance);
  EXPECT_NEAR(fused.x, 0.5, tolerance);
  EXPECT_NEAR(fused.z2, 0.25, tolerance);
}
