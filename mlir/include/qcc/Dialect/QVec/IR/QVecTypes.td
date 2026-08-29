// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QVEC_IR_QVECTYPES_TD_
#define INCLUDE_QCC_DIALECT_QVEC_IR_QVECTYPES_TD_

include "qcc/Dialect/QVec/IR/QVecDialect.td"

include "mlir/Dialect/QCO/IR/QCOTypes.td"
include "mlir/IR/CommonTypeConstraints.td"

//===----------------------------------------------------------------------===//
// QVec type constraints
//===----------------------------------------------------------------------===//

// FIXME: remark on linearity *here*.
// `QubitType` is `!qco.qubit`, the *linear* value-semantics qubit.
def QVec_AnyQubit : AnyTypeOf<[QubitType], "qubit value">;

// `vector<NxQubitT>` - non-scalable vector type, length N statically known.
def QVec_QubitVector : FixedVectorOfRankAndType<[1], [QVec_AnyQubit]>;

// `vector<Nxi1>` - non-scalable vector of classical bits, one per qubit.
def QVec_BitVector : FixedVectorOfRankAndType<[1], [I1]>;

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECTYPES_TD_
