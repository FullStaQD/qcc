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

TEST(RotationUtilsTest, FuseZXZWithRZ) {
  const ZXZAngles zxz{.z1 = 0.1, .x = 0.2, .z2 = 0.3};
  const ZXZAngles before = fuseZXZ(0.1, zxz);
  const ZXZAngles after = fuseZXZ(zxz, 0.1);

  // The Rz angle is added exactly: to z1 if the Rz comes first, to z2 if it comes last.
  EXPECT_EQ(before.z1, 0.2);
  EXPECT_EQ(before.x, 0.2);
  EXPECT_EQ(before.z2, 0.3);
  EXPECT_EQ(after.z1, 0.1);
  EXPECT_EQ(after.x, 0.2);
  EXPECT_EQ(after.z2, 0.4);

  // The general fuseZXZ agrees up to rounding.
  auto expectNear = [](const ZXZAngles& actual, const ZXZAngles& expected) {
    EXPECT_NEAR(actual.z1, expected.z1, 1e-12);
    EXPECT_NEAR(actual.x, expected.x, 1e-12);
    EXPECT_NEAR(actual.z2, expected.z2, 1e-12);
  };
  expectNear(before, fuseZXZ(ZXZAngles{.z1 = 0.1}, zxz));
  expectNear(after, fuseZXZ(zxz, ZXZAngles{.z1 = 0.1}));
}
