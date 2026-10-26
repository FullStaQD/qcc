// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCC_IR_QCCTYPES_TD_
#define INCLUDE_QCC_DIALECT_QCC_IR_QCCTYPES_TD_

include "qcc/Dialect/Qcc/IR/QccDialect.td"
include "qcc/Dialect/Qcc/IR/QccInterfaces.td"

include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/BuiltinTypeInterfaces.td"
include "mlir/IR/CommonTypeConstraints.td"

//===----------------------------------------------------------------------===//
// Qcc types
//===----------------------------------------------------------------------===//

def Qcc_QubitType : TypeDef<Qcc_Dialect, "Qubit", [VectorElementTypeInterface]> {
  let mnemonic = "qubit";
  let summary = "qubit value";
  let description = [{
        A value of type `!qcc.qubit` denotes one qubit at one program point. An operation that acts on a qubit consumes
        the value and returns the qubit as a new value.

        The type is *affine*: each value may be consumed at most once on any execution path (no-cloning). A value that
        is never consumed is discarded, which traces the qubit out.

        A vector of qubits, e.g. `vector<2x!qcc.qubit>`, holds distinct qubits. Taking an element out (`vector.extract`)
        yields the qubit, not a copy. The discipline applies to each qubit in the vector, not to the vector value: each
        qubit may be consumed at most once, whether on its own after `vector.extract` or as part of the vector. An
        element that an operation overwrites, e.g. with `vector.insert`, is discarded, not consumed.

        Not every violation of these rules is diagnosed; IR that violates them has undefined behavior.

        Example:
        ```mlir
        !qcc.qubit
        vector<2x!qcc.qubit>   // qubits can be vector elements
        ```
    }];
}

def Qcc_QubitRefType : TypeDef<Qcc_Dialect, "QubitRef"> {
  let mnemonic = "qubit_ref";
  let summary = "reference to a qubit";
  let description = [{
        A value of type `!qcc.qubit_ref` names a qubit in a reference-semantics context, the way a pointer names an
        object. Two values may name the same qubit, so distinct values do not imply distinct qubits. A value is valid
        only while its qubit is allocated; using it outside that lifetime has undefined behavior. A static qubit
        (`qcc.static_ref`) is allocated for the whole program, a qubit from `qcc.alloc` until its `qcc.dealloc`, if
        any.

        An array of qubits is a 1D tensor of references. The tensor has value semantics: an array never changes which
        qubits it names, only its elements are references.

        Example:
        ```mlir
        !qcc.qubit_ref
        tensor<?x!qcc.qubit_ref>   // an array of qubits
        ```
    }];
}

def Qcc_AngleType : TypeDef<Qcc_Dialect, "Angle", [Qcc_ClassicalTypeInterface]> {
  let mnemonic = "angle";
  let summary = "angle of unspecified precision";
  let description = [{
        An angle, a fraction of 2π, whose precision the target defines. This is OpenQASM's unsized `angle` and the type
        of all gate parameters there.

        Example:
        ```mlir
        !qcc.angle
        ```
    }];
}

def Qcc_RefType : TypeDef<Qcc_Dialect, "Ref"> {
  let mnemonic = "ref";
  let summary = "mutable classical storage";
  let description = [{
        A reference to storage that holds one value of type `T`, much like `&mut T` in Rust. `qcc.ref.load` reads the
        value and `qcc.ref.store` replaces it. Operations on values of type `T` never see the storage.

        `T` must be a classical type (see `ClassicalTypeInterface`): qubits are referenced through `!qcc.qubit_ref`.

        Example:
        ```mlir
        !qcc.ref<i1>
        !qcc.ref<!oq3.bits<2>>
        ```
    }];

  let parameters = (ins "::mlir::Type":$elementType);
  let assemblyFormat = "`<` $elementType `>`";
  let builders = [
    TypeBuilderWithInferredContext<(ins "::mlir::Type":$elementType), [{
      return $_get(elementType.getContext(), elementType);
    }]>
  ];
  let genVerifyDecl = 1;
}

//===----------------------------------------------------------------------===//
// Qcc type constraints
//===----------------------------------------------------------------------===//

// What a qubit lane carries: `!qcc.qubit` or a vector of them.
def Qcc_QubitOrQubitVector : Type<CPred<"::qcc::isQubitOrQubitVector($_self)">, "qubit or vector of qubits">;

// What `qcc.alloc` returns and `qcc.dealloc` takes: one qubit or an array of them.
def Qcc_QubitRefOrArray : AnyTypeOf<[Qcc_QubitRefType, 1DTensorOf<[Qcc_QubitRefType]>],
                                    "qubit reference or 1D tensor of qubit references">;

// A gate parameter: an angle in radians.
def Qcc_GateParam : AnyTypeOf<[F64], "64-bit float angle">;

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCTYPES_TD_
