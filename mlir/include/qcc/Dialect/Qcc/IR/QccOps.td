// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCC_IR_QCCOPS_TD_
#define INCLUDE_QCC_DIALECT_QCC_IR_QCCOPS_TD_

include "qcc/Dialect/Qcc/IR/QccAttrs.td" // No op here uses them, but the dialect documentation lists them.
include "qcc/Dialect/Qcc/IR/QccDialect.td"
include "qcc/Dialect/Qcc/IR/QccInterfaces.td"
include "qcc/Dialect/Qcc/IR/QccTypes.td"

include "mlir/IR/CommonAttrConstraints.td"
include "mlir/IR/CommonTypeConstraints.td"
include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// Qcc operations
//===----------------------------------------------------------------------===//

// No memory effects, but deliberately not `Pure`: qubit values must never be duplicated.
def Qcc_StaticOp : Op<Qcc_Dialect, "static", [NoMemoryEffect, Qcc_NoMultiUseQubits]> {
  let summary = "the qubits of a function, by static index";
  let description = [{
        Creates the qubits a function works on, one result per index, each initialized in |0⟩. The indices are
        non-negative and strictly increasing, but need not be dense.

        The op is the only source of `!qcc.qubit` values. It sits directly in a `func.func`, and a function holds at
        most one of them.

        Example:
        ```mlir
        %q0, %q1, %q3 = qcc.static [0, 1, 3] : !qcc.qubit
        ```
    }];

  let arguments = (ins DenseI64ArrayAttr:$indices);
  let results = (outs Variadic<Qcc_QubitType>:$qubits);

  let assemblyFormat = [{
        $indices attr-dict `:` custom<StaticTypes>(type($qubits), ref($indices))
    }];

  let builders = [
    // One qubit per entry of `indices`.
    OpBuilder<(ins "::llvm::ArrayRef<int64_t>":$indices)>
  ];

  let hasVerifier = 1;
}

def Qcc_StaticRefOp : Op<Qcc_Dialect, "static_ref", [Pure]> {
  let summary = "references to qubits, by static index";
  let description = [{
        Returns a reference to each qubit in `indices`, one result per index. The indices are non-negative and
        strictly increasing, but need not be dense. A static qubit is identified by its index: two `qcc.static_ref`
        ops that list the same index name the same qubit.

        The op only names the qubits, so it may sit anywhere. It does not imply that they are in |0⟩: this guarantee
        only holds at the start of the program.

        Example:
        ```mlir
        %q0, %q1 = qcc.static_ref [0, 1] : !qcc.qubit_ref
        ```
    }];

  let arguments = (ins DenseI64ArrayAttr:$indices);
  let results = (outs Variadic<Qcc_QubitRefType>:$qubits);

  let assemblyFormat = [{
        $indices attr-dict `:` custom<StaticTypes>(type($qubits), ref($indices))
    }];

  let builders = [
    // One reference per entry of `indices`.
    OpBuilder<(ins "::llvm::ArrayRef<int64_t>":$indices)>
  ];

  let hasVerifier = 1;
}

def Qcc_AllocOp : Op<Qcc_Dialect, "alloc"> {
  let summary = "allocates fresh qubits";
  let description = [{
        Allocates a fresh qubit in |0⟩, or an array of distinct fresh qubits. An array has a static size or the size
        `dynamic_size`, and the size may be 0.

        A fresh qubit lives until a `qcc.dealloc` frees it, otherwise until the end of the program. While it lives, it
        is distinct from every other qubit that is acted on, static qubits included. Below, `%a` may be the static
        qubit 10, but not 6.

        ```mlir
        %a = qcc.alloc : !qcc.qubit_ref
        %q6 = qcc.static_ref [6] : !qcc.qubit_ref
        qref.pair cx %a, %q6 : !qcc.qubit_ref
        qcc.dealloc %a : !qcc.qubit_ref
        %q10 = qcc.static_ref [10] : !qcc.qubit_ref
        qref.single h %q10 : !qcc.qubit_ref
        ```

        Example:
        ```mlir
        %q = qcc.alloc : !qcc.qubit_ref
        %r = qcc.alloc %n : tensor<?x!qcc.qubit_ref>
        %s = qcc.alloc : tensor<3x!qcc.qubit_ref>
        ```
    }];

  let arguments = (ins Optional<Index>:$dynamic_size);
  let results = (outs Res<Qcc_QubitRefOrArray, "the fresh qubits",
                          [MemAlloc<Qcc_QubitResource, 0, FullEffect>]>:$qubits);

  let assemblyFormat = "($dynamic_size^)? attr-dict `:` type($qubits)";
  let hasVerifier = 1;
}

def Qcc_DeallocOp : Op<Qcc_Dialect, "dealloc"> {
  let summary = "frees qubits";
  let description = [{
        Ends the lifetime of the qubits that `qubits` names: one qubit, or all qubits of an array, which may also be a
        slice, a concatenation, or an element of an array. The qubits are discarded (traced out) in whatever state they
        are in.

        Each qubit must come from a `qcc.alloc` and be freed at most once. Using a qubit after it is freed has undefined
        behavior. Not every violation of these rules is diagnosed.

        Example:
        ```mlir
        qcc.dealloc %q : !qcc.qubit_ref
        qcc.dealloc %r : tensor<?x!qcc.qubit_ref>
        ```
    }];

  let arguments = (ins Arg<Qcc_QubitRefOrArray, "the qubits to free",
                           [MemFree<Qcc_QubitResource, 0, FullEffect>]>:$qubits);

  let assemblyFormat = "$qubits attr-dict `:` type($qubits)";
  let hasVerifier = 1;
}

def Qcc_RefLoadOp : Op<Qcc_Dialect, "ref.load"> {
  let summary = "reads classical storage";
  let description = [{
        Returns the value that `ref` currently holds.

        Example:
        ```mlir
        %value = qcc.ref.load %c : !qcc.ref<!oq3.bit>
        ```
    }];

  let arguments = (ins Arg<Qcc_RefType, "the storage to read", [MemRead]>:$ref);
  let results = (outs AnyType:$result);

  let assemblyFormat = "$ref attr-dict `:` custom<RefType>(type($ref), type($result))";
  let hasVerifier = 1;

  let builders = [
    // Reads the element type of `ref`.
    OpBuilder<(ins "::mlir::Value":$ref), [{
      build($_builder, $_state, ::llvm::cast<::qcc::RefType>(ref.getType()).getElementType(), ref);
    }]>
  ];
}

def Qcc_RefStoreOp : Op<Qcc_Dialect, "ref.store"> {
  let summary = "writes classical storage";
  let description = [{
        Replaces the value that `ref` holds by `value`.

        Example:
        ```mlir
        qcc.ref.store %bit, %c : !qcc.ref<!oq3.bit>
        ```
    }];

  let arguments = (ins AnyType:$value,
                       Arg<Qcc_RefType, "the storage to write", [MemWrite]>:$ref);

  let assemblyFormat = "$value `,` $ref attr-dict `:` custom<RefType>(type($ref), type($value))";
  let hasVerifier = 1;
}

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCOPS_TD_
