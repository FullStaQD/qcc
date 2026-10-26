// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCF_IR_QCFOPS_TD_
#define INCLUDE_QCC_DIALECT_QCF_IR_QCFOPS_TD_

include "qcc/Dialect/QCF/IR/QCFDialect.td"
include "qcc/Dialect/Qcc/IR/QccInterfaces.td"
include "qcc/Dialect/Qcc/IR/QccTypes.td"

include "mlir/IR/OpBase.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// QCF operations
//===----------------------------------------------------------------------===//

class QCF_Op<string mnemonic, list<Trait> traits = []>
    : Op<QCF_Dialect, mnemonic, !listconcat(traits, [Qcc_NoMultiUseQubits])>;

def QCF_IfOp : QCF_Op<"if", [
    DeclareOpInterfaceMethods<RegionBranchOpInterface, ["getEntrySuccessorOperands", "getSuccessorInputs"]>,
    RecursiveMemoryEffects, Qcc_QubitScope, Qcc_QubitLaneOpInterface]> {
  let summary = "classically conditioned circuit";
  let description = [{
        Runs the `then` region if `condition` is true, otherwise the `else` region.

        The qubits the regions act on are bound in the binding list: `(%a = %a_in)` binds the qubit `%a_in` (or a vector
        of qubits) to the argument `%a` of the `then` region. The `else` region binds the qubits in the same order.

        `qcf.if` adheres to the `QubitLaneOpInterface`: The regions must not capture qubits; classical values may be
        captured. The qubit bound to argument `i` is yielded at position `i` by each region and leaves the op as result
        `i`. Classical results follow the qubits, both in the results and in the yields.

        The `else` region may be omitted if it would only yield the bound qubits unchanged. This requires that there
        are no classical results.

        Not every violation of these rules is diagnosed; IR that violates them has undefined behavior.

        Example:
        ```mlir
        // `%a_in`, `%a`, `%a1`, and `%a_out` are the same qubit.
        %a_out, %b_out, %m = qcf.if %bit (%a = %a_in, %b = %b_in) -> (!qcc.qubit, !qcc.qubit, i1) {
          %a1, %b1 = qcirc.pair cx %a, %b : !qcc.qubit
          %b2, %m1 = qcirc.measure z %b1 : !qcc.qubit -> i1
          qcf.yield %a1, %b2, %m1 : !qcc.qubit, !qcc.qubit, i1
        } else (%a, %b) {
          %false = arith.constant false
          qcf.yield %a, %b, %false : !qcc.qubit, !qcc.qubit, i1
        }
        ```
    }];

  let arguments = (ins Variadic<Qcc_QubitOrQubitVector>:$qubits_in,
                       I1:$condition);
  let results = (outs Variadic<AnyType>:$results);
  let regions = (region SizedRegion<1>:$thenRegion,
                        MaxSizedRegion<1>:$elseRegion);

  // The default builders take the qubit result types apart from the bound qubits.
  let skipDefaultBuilders = 1;
  let builders = [
    // The results are the bound qubits, then `classicalTypes`. A region requested by `addThenBlock` or
    // `addElseBlock` gets its block with one argument per bound qubit, but no terminator. A region not requested
    // stays empty, e.g. to move an existing region in.
    OpBuilder<(ins "::mlir::Value":$condition, "::mlir::ValueRange":$qubitsIn,
                   "::mlir::TypeRange":$classicalTypes, "bool":$addThenBlock, "bool":$addElseBlock)>
  ];

  let extraClassDeclaration = [{
    /// The results behind the qubits.
    ::mlir::ResultRange getClassicalResults() { return getResults().drop_front(getQubitsIn().size()); }

    ::mlir::Block* getThenBlock() { return &getThenRegion().front(); }
    /// Returns null if the else region is omitted.
    ::mlir::Block* getElseBlock() { return getElseRegion().empty() ? nullptr : &getElseRegion().front(); }
  }];

  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let hasFolder = 1;
  let hasCanonicalizer = 1;
}

// No memory effects, but deliberately not `Pure`: qubit values must never be duplicated.
def QCF_YieldOp : QCF_Op<"yield", [NoMemoryEffect, ReturnLike, Terminator, HasParent<"IfOp">]> {
  let summary = "returns the qubits and classical values of a region";
  let description = [{
        Terminates a region of a `qcf` op and passes its operands to the parent op: the bound qubits in the order of
        the bindings, then the classical values.

        Example:
        ```mlir
        qcf.yield %a, %b, %m : !qcc.qubit, !qcc.qubit, i1
        ```
    }];

  let arguments = (ins Variadic<AnyType>:$results);

  let assemblyFormat = [{
        attr-dict ($results^ `:` type($results))?
  }];
}

#endif // INCLUDE_QCC_DIALECT_QCF_IR_QCFOPS_TD_
