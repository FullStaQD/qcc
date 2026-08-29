// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QVEC_IR_QVECDIALECT_TD_
#define INCLUDE_QCC_DIALECT_QVEC_IR_QVECDIALECT_TD_

include "mlir/IR/DialectBase.td"
include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// QVec dialect
//===----------------------------------------------------------------------===//

// FIXME: refactor docstring again.
def QVecDialect : Dialect {
    let summary = "Vector-shaped quantum instructions.";
    let description = [{
        Some quantum ISAs apply one gate across every active element of a vector register, so that a whole batch of
        independent gates costs one instruction. `qvec` is our abstraction to express such operations in an ISA-agnostic
        way. This parallels the upstream `vector` dialect, and in fact we use the builtin `vector` type.

        The dialect has **value semantics** to allow for powerful optimization passes.

        As a minor deviation from ISA agnosticism we follow RISC-V Vector Extension (RVV) terminology when we encode the
        minimum VLEN into `qvec.target`

        ```mlir
        module attributes {qvec.target = #dlti.map<"min_vlen" = 128 : ui32>}
        ```

        and derive the legal vector lengths from LMUL register groups. We picked RVV because it is the vector
        architecture we know and because our first target, HiSEP-Q, is an RVV extension.

        Example:
        ```mlir
        // A Hadamard gate on all four qubits in %qs.
        %qs_out = qvec.single h %qs : vector<4x!qco.qubit>
        ```
    }];

    let name = "qvec";
    let cppNamespace = "::qcc::qvec";

    // `qvec.target` carries the machine description.
    let hasOperationAttrVerify = 1;

    // `!qco.qubit` appears in our operations' assembly.
    let dependentDialects = ["::mlir::qco::QCODialect"];

    let useDefaultTypePrinterParser = 0;      // set to 1 once we define types of our own.
    let useDefaultAttributePrinterParser = 1; // needed by the gate-kind attributes.
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECDIALECT_TD_
