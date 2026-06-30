// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include <mlir/Pass/Pass.h>

namespace qcc {
#define GEN_PASS_DECL
#include "qcc/Conversion/Aux_/AuxOutputRecording.h.inc"

#define GEN_PASS_REGISTRATION
#include "qcc/Conversion/Aux_/AuxOutputRecording.h.inc"
} // namespace qcc
