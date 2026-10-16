// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_OQ3_IR_OQ3DIALECT_TD_
#define INCLUDE_QCC_DIALECT_OQ3_IR_OQ3DIALECT_TD_

include "mlir/IR/DialectBase.td"
include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// OQ3 dialect
//===----------------------------------------------------------------------===//

def OQ3_Dialect : Dialect {
    let summary = "Faithful representation of OpenQASM 3 programs.";
    let description = [{
        The `oq3` dialect represents an OpenQASM 3.x program as closely to its source text as possible, so that a
        program can be imported, verified, and exported back to the same text up to formatting. Comments, pragmas,
        annotations, include lines, and the spelling of literals are part of the IR.

        The module is the program and carries the language version (`oq3.version`). All statements of the program form
        the body of the entry function (`qcc.entry_point`). Global definitions are symbols in the module, and markers
        (`oq3.defined`) in the entry body record where they appear in the source.

        Classical variables are storage of type `!qcc.ref<T>`, read with `qcc.ref.load` and written with
        `qcc.ref.store`. Qubits are references of type `!qcc.qubit_ref`, registers of type `!oq3.qreg<n>`.
        Expressions are pure SSA values and use `oq3` operations only. None of them folds, since folding would replace
        the source text.

        Example:
        ```mlir
        module attributes {oq3.version = #oq3.version<3, 1>} {
          func.func @main() attributes {qcc.entry_point} {
            oq3.include "stdgates.inc" id 0
            %c2 = oq3.constant #oq3.int<2> : !oq3.int
            %q = oq3.qubit_decl "q" [%c2 : !oq3.int] : !oq3.qreg<2>
            oq3.gate_call @h [%q : !oq3.qreg<2>]
            func.return
          }
        }
        ```
    }];

    let name = "oq3";
    let cppNamespace = "::qcc::oq3";

    let dependentDialects = ["::qcc::QccDialect", "::mlir::func::FuncDialect"];

    let useDefaultTypePrinterParser = 1;
    let useDefaultAttributePrinterParser = 1;

    let discardableAttrs = (ins "::mlir::Attribute":$version,
                                "::mlir::IntegerAttr":$from_include,
                                "::mlir::StringAttr":$trailing_comment,
                                "::mlir::ArrayAttr":$annotations,
                                "::mlir::UnitAttr":$arrow);
    let hasOperationAttrVerify = 1;

    let extraClassDeclaration = [{
      private:
        void registerTypes();
        void registerAttributes();
    }];
}

#endif // INCLUDE_QCC_DIALECT_OQ3_IR_OQ3DIALECT_TD_
