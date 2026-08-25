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
        `QV.SINGLE` or `QV.PAIR` instruction applies one gate across every active element of a
        vector register. The `hisepq` dialect is the IR level at which that shape becomes
        expressible.

        Where the `qc` dialect names one qubit per operation, a `hisepq` operation carries a whole
        qubit vector, so it maps one-to-one onto a machine instruction. That makes it the place
        where a vectorizer packs independent gates together, and the last level at which the
        assignment of qubits to vector elements is still a compiler decision rather than an
        encoding detail.

        Like `qco`, the dialect has **value semantics**: an operation consumes the qubit vectors it
        names and returns them, so the qubits a program touches are threaded through the IR in SSA
        form. That chain is what orders the operations, and it is what a vectorizer reads to decide
        which gates may be packed into one instruction.

        The operations additionally carry a coarse read/write effect on the default resource, which
        orders every `hisepq` operation against every other one. That is a conservative backstop,
        kept until qubit ownership is actually enforced; see `HiSEPQOps.td`.

        Example:
        ```mlir
        // One instruction, a Hadamard on all four qubits in %qs.
        %qs_out = hisepq.single h %qs : vector<4x!qco.qubit>
        ```
    }];

    let name = "hisepq";
    let cppNamespace = "::qcc::hisepq";

    // `hisepq.target` carries the machine description.
    let hasOperationAttrVerify = 1;

    // `!qco.qubit` appears in our operations' assembly.
    let dependentDialects = ["::mlir::qco::QCODialect"];

    let useDefaultTypePrinterParser = 0;      // set to 1 once we define types of our own.
    let useDefaultAttributePrinterParser = 1; // needed by the gate-kind attributes.
}

#endif // INCLUDE_QCC_DIALECT_HISEPQ_IR_HISEPQDIALECT_TD_
