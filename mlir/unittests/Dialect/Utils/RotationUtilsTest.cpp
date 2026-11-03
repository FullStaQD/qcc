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

#include <cmath>
#include <numbers>
#include <ostream>

using namespace qcc;

/// The absolute tolerance of the numerical checks.
constexpr double tolerance = 1e-12;

namespace qcc {

/// Prints `angles` in failure messages, with every digit. gtest finds this by ADL, so it keeps gtest's name.
// NOLINTNEXTLINE(readability-identifier-naming)
static void PrintTo(const ZXZAngles& angles, std::ostream* os) {
  *os << "{z1 = " << testing::PrintToString(angles.z1) << ", x = " << testing::PrintToString(angles.x)
      << ", z2 = " << testing::PrintToString(angles.z2) << "}";
}

} // namespace qcc

/// Matches ZXZ angles that are each within `maxError` of `expected`.
static testing::Matcher<ZXZAngles> zxzNear(const ZXZAngles& expected, double maxError) {
  return testing::AllOf(testing::Field("z1", &ZXZAngles::z1, testing::DoubleNear(expected.z1, maxError)),
                        testing::Field("x", &ZXZAngles::x, testing::DoubleNear(expected.x, maxError)),
                        testing::Field("z2", &ZXZAngles::z2, testing::DoubleNear(expected.z2, maxError)));
}

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
  const ZXZAngles zxz{.z1 = 0.125, .x = 0.25, .z2 = 0.375};

  // The Rz angle is added exactly: to z1 if the Rz comes first, to z2 if it comes last.
  EXPECT_THAT(fuseZXZ(0.5, zxz), zxzNear({.z1 = 0.625, .x = 0.25, .z2 = 0.375}, 0.0));
  EXPECT_THAT(fuseZXZ(zxz, 0.5), zxzNear({.z1 = 0.125, .x = 0.25, .z2 = 0.875}, 0.0));

  // The general fuseZXZ agrees up to rounding.
  EXPECT_THAT(fuseZXZ(ZXZAngles{.z1 = 0.5}, zxz), zxzNear(fuseZXZ(0.5, zxz), tolerance));
  EXPECT_THAT(fuseZXZ(zxz, ZXZAngles{.z1 = 0.5}), zxzNear(fuseZXZ(zxz, 0.5), tolerance));
}
