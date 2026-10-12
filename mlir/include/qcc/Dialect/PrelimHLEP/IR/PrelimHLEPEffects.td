// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPEFFECTS_TD_
#define INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPEFFECTS_TD_

include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// Side effect resources
//
// Ops whose results are a function of their operands (a single world) and
// that neither create nor destroy linear values are `Pure`: linearity alone
// keeps them from being duplicated or hoisted. Everything else is modeled on
// one of these resources.
//===----------------------------------------------------------------------===//
// TODO: Develop a principled theory of these side-effect resources.

// The hidden world index. A measurement reads it (its outcome is the world's
// value) and writes it (the next measurement is a fresh draw), so that two
// measurements are never merged, hoisted, or erased.
def PrelimHLEP_WorldResource : Resource<"::qcc::prelimhlep::WorldResource">;

// The quantum state that linear values are allocated in and freed from.
def PrelimHLEP_QuantumStateResource : Resource<"::qcc::prelimhlep::QuantumStateResource">;

#endif // INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPEFFECTS_TD_
