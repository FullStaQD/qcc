// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQDIALECT_TD_
#define INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQDIALECT_TD_

include "mlir/IR/DialectBase.td"
include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// HiSEP-Q dialect
//===----------------------------------------------------------------------===//

def HiSEPQDialect : Dialect {
    // FIXME: improve summary and description once everything is done.
    let summary = "Vector-shaped quantum instructions for the HiSEP-Q ISA.";
    let description = [{
        The HiSEP-Q ISA is a vendor extension of the RISC-V vector extension (RVV): a single
        `QV.SINGLE` or `QV.PAIR` instruction applies one gate across every active lane of a vector
        register. The `hisepq` dialect is the IR level at which that shape becomes expressible.

        Where the `qc` dialect names one qubit per operation, a `hisepq` operation carries a whole
        lane vector, so it maps one-to-one onto a machine instruction. That makes it the place where
        a vectorizer packs independent gates together, and the last level at which lane assignment is
        still a compiler decision rather than an encoding detail.

        Like `qc`, the dialect has **memory semantics**: operations mutate the qubits they name in
        place. Only `hisepq.mz` produces a value, and that value is classical.

        Example:
        ```mlir
        // One instruction, a Hadamard on all four qubits in %qs.
        hisepq.single h %qs : vector<4x!qc.qubit>
        ```
    }];

    let name = "hisepq";
    let cppNamespace = "::qcc::hisepq";

    // `!qc.qubit` appears in our operations' assembly.
    let dependentDialects = ["::mlir::qc::QCDialect"];

    let useDefaultTypePrinterParser = 0;      // set to 1 once we define types of our own.
    let useDefaultAttributePrinterParser = 1; // needed by the gate-kind attributes.
}

#endif // INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQDIALECT_TD_
