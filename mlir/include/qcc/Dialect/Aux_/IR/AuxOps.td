// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_AUX_IR_AUXOPS_TD_
#define INCLUDE_QCC_DIALECT_AUX_IR_AUXOPS_TD_

include "mlir/IR/OpBase.td"
include "mlir/IR/BuiltinTypes.td"
include "AuxDialect.td"

//===----------------------------------------------------------------------===//
// Aux operations
//===----------------------------------------------------------------------===//

class AuxOp<string mnemonic, list<Trait> traits = []> : Op<AuxDialect, mnemonic, traits>;

def RecordIntOp : AuxOp<"record_int"> {
  let summary = "Records an integer.";

  let description = [{
        This corresponds to the following QIR runtime function:

        ```llvm
        llvm.func @__quantum__rt__int_record_output(i64, !llvm.ptr)
        ```

        Our principal dialects have nothing in it which can be translated to it. Hence we use this as a workaround.
        It is used like this:

        ```mlir
        func.func @main() attributes { qcc.entry_point } {
          ...
          aux.record_int %m7
          return
        }
        ```

        To actually translate it to the above QIR runtime function we use a dummy label for the second argument of
        the QIR function.
    }];

    let arguments = (ins AnyTypeOf<[Builtin_Integer]>:$value);
    let results = (outs);

    let assemblyFormat = "$value attr-dict `:` type($value)";
}

def RecordMemRefOp : AuxOp<"record_memref"> {
  let summary = "Records a memory reference.";

  let description = [{
        Helper to later lower to to the following QIR runtime function:

        ```llvm
        llvm.func @__quantum__rt__array_record_output(i64, !llvm.ptr)
        ...
        llvm.func @__quantum__rt__int_record_output(i64, !llvm.ptr)
        ...
        llvm.func @__quantum__rt__int_record_output(i64, !llvm.ptr)
        ...
        ```

        Our principal dialects have nothing in it which can be translated to it. Hence we use this as a workaround.
        It is used like this:

        ```mlir
        func.func @main() attributes { qcc.entry_point } {
          ...
          aux.record_memref %m7
          ...
          return
        }
        ```

        To actually translate it to the above QIR runtime function we use a dummy label for the second argument of
        the QIR function.
    }];

  let arguments = (ins MemRefOf<[AnyInteger]>:$value);
  let results = (outs);

  let assemblyFormat = "$value attr-dict `:` type($value)";
  let hasVerifier = 1;
}

#endif // INCLUDE_QCC_DIALECT_AUX_IR_AUXOPS_TD_
