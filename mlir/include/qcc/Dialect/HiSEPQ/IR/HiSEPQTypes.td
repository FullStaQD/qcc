// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQTYPES_TD_
#define INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQTYPES_TD_

include "qcc/Dialect/HiSEPQ/IR/HiSEPQDialect.td"

include "mlir/Dialect/QC/IR/QCTypes.td"
include "mlir/IR/CommonTypeConstraints.td"

//===----------------------------------------------------------------------===//
// HiSEP-Q type constraints
//===----------------------------------------------------------------------===//

def HiSEPQ_AnyQubit : AnyTypeOf<[QubitType], "qubit reference">;

// `vector<NxQubitT>` - non-scalable vector type, length N statically known.
def HiSEPQ_QubitVector : FixedVectorOfRankAndType<[1], [HiSEPQ_AnyQubit]>;

// `vectot<Nxi1>` - non-scalable mask.
def HiSEPQ_MaskVector : FixedVectorOfRankAndType<[1], [I1]>;

#endif // INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQTYPES_TD_
