// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/QVec/Transforms/ZXZ.h"

#include "gtest/gtest.h"

#include <array>
#include <complex>
#include <numbers>

using namespace qcc::qvec;

/// Whether the unitaries `actual` and `expected` agree up to a global phase. For `actual` = e^{i phi} `expected` the
/// trace of `actual`^dagger `expected` is 2 e^{-i phi}, which gives the phase to compare the elements with.
static testing::AssertionResult equalUpToGlobalPhase(const Matrix2x2& actual, const Matrix2x2& expected) {
  Complex overlap{0.0};
  for (unsigned row = 0; row < 2; ++row) {
    for (unsigned col = 0; col < 2; ++col) {
      overlap += std::conj(actual(row, col)) * expected(row, col);
    }
  }
  const Complex phase = std::polar(1.0, std::arg(overlap));

  constexpr double tolerance = 1e-12;
  for (unsigned row = 0; row < 2; ++row) {
    for (unsigned col = 0; col < 2; ++col) {
      if (std::abs((phase * actual(row, col)) - expected(row, col)) > tolerance) {
        return testing::AssertionFailure() << "element (" << row << ", " << col << ") differs: " << actual(row, col)
                                           << " vs. " << expected(row, col) << " after removing the phase " << phase;
      }
    }
  }
  return testing::AssertionSuccess();
}

TEST(ZXZTest, DecomposeRoundTrip) {
  constexpr double pi = std::numbers::pi;
  const auto cases = std::to_array<ZXZAngles>({
      {.z1 = 0.0, .x = 0.0, .z2 = 0.0},
      {.z1 = 0.3, .x = 1.2, .z2 = -0.7},
      {.z1 = -2.5, .x = -0.4, .z2 = 2.0},
      {.z1 = 4.0, .x = 5.0, .z2 = -7.0}, // outside of (-pi, pi]
      {.z1 = 0.4, .x = 0.0, .z2 = 0.9},  // x = 0: only z1 + z2 is defined
      {.z1 = 0.4, .x = pi, .z2 = 0.9},   // x = pi: only z1 - z2 is defined
  });

  for (const ZXZAngles& angles : cases) {
    SCOPED_TRACE(testing::Message() << "z1 = " << angles.z1 << ", x = " << angles.x << ", z2 = " << angles.z2);
    const Matrix2x2 unitary = zxzMatrix(angles);
    const ZXZAngles decomposed = decomposeZXZ(unitary);

    EXPECT_TRUE(equalUpToGlobalPhase(zxzMatrix(decomposed), unitary));
    for (double angle : {decomposed.z1, decomposed.x, decomposed.z2}) {
      EXPECT_GT(angle, -pi);
      EXPECT_LE(angle, pi);
    }
  }
}
