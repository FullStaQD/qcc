// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPDIALECT_TD_
#define INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPDIALECT_TD_

include "mlir/IR/DialectBase.td"
include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// PrelimHLEP dialect
//===----------------------------------------------------------------------===//

def PrelimHLEPDialect : Dialect {
    let summary = "PRELIMINARY High-level entry point dialect.";
    let description = [{
        Hybrid quantum-classical IR meant to serve as an
        entry point to the compilation pipeline.

        Ops of this dialect are legal in `func.func`s marked with the `prelimhlep.halo` attribute.
        Quantum types are synthesized from classical types:
        If `T` is a classical type, then `!prelimhlep.lin<T>` is the linear type with distinguished basis
        given by the values of `T`. For instance, the qubit type is `!prelimhlep.lin<i1>`.

        Linear values are subject to linearity: They must be used exactly once on every control flow path.
        This is ensured by verifiers using control flow analysis.

        The distinguishing feature is the *partial linearization* op `prelimhlep.lin`,
        which transforms a body of with mixed linear and non-linear values into a an operation
        of the same signature, but with *some* of the values linearized.
        This enables classical reasoning about hybrid programs.
        Partial linearization can be used to implement classical and quantum control flow, state preparation, and measurement.

        For quantum operations that cannot be expressed in terms of partial linearization,
        the dialect provides exponentiation of Pauli polynomials, an `add_phase` primitive, and
        a calculus of base changes (relevant for the Hadmard gate).
    }];

    let name = "prelimhlep";
    let cppNamespace = "::qcc::prelimhlep";
    let useDefaultTypePrinterParser = 1;
    let useDefaultAttributePrinterParser = 1;
    let hasConstantMaterializer = 1;

    let extraClassDeclaration = [{
        /// Verifies dialect attributes (e.g. `prelimhlep.halo`) attached to
        /// arbitrary operations, such as `func.func`. See PrelimHLEPDialect.cpp.
        ::mlir::LogicalResult
        verifyOperationAttribute(::mlir::Operation *op,
                                  ::mlir::NamedAttribute attribute) override;
    }];
}


#endif // INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPDIALECT_TD_
