// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Utils/RotationUtils.h"

#include "gtest/gtest.h"

#include <cmath>
#include <numbers>

using namespace qcc;

TEST(RotationUtilsTest, NormalizeAngle) {
  constexpr double pi = std::numbers::pi;

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
