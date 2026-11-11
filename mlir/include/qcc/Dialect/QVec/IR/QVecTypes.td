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
include "qcc/Dialect/Qcc/IR/QccTypes.td"

include "mlir/IR/CommonTypeConstraints.td"

//===----------------------------------------------------------------------===//
// QVec type constraints
//===----------------------------------------------------------------------===//

// `vector<Nx!qcc.qubit>` - non-scalable vector of qubits, length N statically known.
def QVec_QubitVector : FixedVectorOfRankAndType<[1], [Qcc_QubitType]>;

// `vector<Nxi1>` - non-scalable vector of classical bits, one per qubit.
def QVec_BitVector : FixedVectorOfRankAndType<[1], [I1]>;

// `vector<Nxf64>` - one angle (radians) per lane of a qubit vector.
def QVec_AngleVector : FixedVectorOfRankAndType<[1], [F64]>;

// `vector<NxNxf64>` - one angle (radians) per pair of lanes of a qubit vector.
def QVec_AngleMatrix : FixedVectorOfRankAndType<[2], [F64]>;

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECTYPES_TD_
