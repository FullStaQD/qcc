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

include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/BuiltinTypeInterfaces.td"

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

        Example:
        ```mlir
        %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
        %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>
        ```
    }];
}

def Qcc_QubitRefType : TypeDef<Qcc_Dialect, "QubitRef"> {
  let mnemonic = "qubit_ref";
  let summary = "reference to a qubit";
  let description = [{
        A value of type `!qcc.qubit_ref` names a qubit in a reference-semantics context, the way a pointer names an
        object: an operation that acts on the qubit takes the reference and leaves it valid. Unlike `!qcc.qubit`, the
        type is not affine, so a reference may be used any number of times.

        Example:
        ```mlir
        %q = oq3.qubit_decl "q" : !qcc.qubit_ref
        ```
    }];
}

def Qcc_AngleType : TypeDef<Qcc_Dialect, "Angle"> {
  let mnemonic = "angle";
  let summary = "angle of unspecified precision";
  let description = [{
        An angle, a fraction of 2π, whose precision the target defines. This is OpenQASM's unsized `angle` and the type
        of all gate parameters there.

        Example:
        ```mlir
        %theta = oq3.cast %f implicit : !oq3.float -> !qcc.angle
        ```
    }];
}

def Qcc_RefType : TypeDef<Qcc_Dialect, "Ref"> {
  let mnemonic = "ref";
  let summary = "mutable classical storage";
  let description = [{
        A reference to storage that holds one value of type `T`, much like `&mut T` in Rust. `qcc.ref.load` reads the
        value and `qcc.ref.store` replaces it. Operations on values of type `T` never see the storage.

        The type is for classical storage only: qubits are referenced through `!qcc.qubit_ref`.

        Example:
        ```mlir
        %c = oq3.declare "c" : !qcc.ref<!oq3.bit>
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

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCTYPES_TD_
