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

def QVecDialect : Dialect {
    // FIXME: improve summary and description once everything is done.
    let summary = "Vector-shaped quantum instructions.";
    let description = [{
        Some quantum ISAs apply one gate across every active element of a vector register, so that
        a whole batch of independent gates costs one instruction. The `qvec` dialect is the IR
        level at which that shape becomes expressible.

        Where the `qc` dialect names one qubit per operation, a `qvec` operation carries a whole
        qubit vector, so it maps one-to-one onto a machine instruction on such a target. That makes
        it the place where a vectorizer packs independent gates together, and the last level at
        which the assignment of qubits to vector elements is still a compiler decision rather than
        an encoding detail.

        The dialect is deliberately not tied to one ISA. An operation commits only to the *shape*
        of the gate it carries -- how many qubit operands it takes, and how many classical
        parameters -- never to a particular instruction encoding. Today the only target is HiSEP-Q,
        a vendor extension of the RISC-V vector extension (RVV) whose `QV.SINGLE` and `QV.PAIR`
        instructions are exactly this shape, and the lowering to it lives in
        `Conversion/ToHiSEPQ`.

        **Where we do commit to RVV.** Two things here are RVV conventions rather than universal
        truths, and we adopted them because RVV is the vector architecture we know and the one we
        have to hit first:

        - The machine description behind `qvec.target` is parameterised by RVV's `VLEN`, and the
          legal vector lengths are derived through RVV's `LMUL` register groups. See `QVecMachine.h`.
        - Qubit indices are assumed to travel as `i8` elements, which is what fixes how many qubits
          one operation can name.

        Neither leaks into the operation semantics, so a second vector target would mean
        generalising the target description rather than reshaping the IR. We have not done that
        work, because there is no second target yet to tell us what it should abstract over.

        Like `qco`, the dialect has **value semantics**: an operation consumes the qubit vectors it
        names and returns them, so the qubits a program touches are threaded through the IR in SSA
        form. That chain is what orders the operations, and it is what a vectorizer reads to decide
        which gates may be packed into one instruction.

        The operations additionally carry a coarse read/write effect on the default resource, which
        orders every `qvec` operation against every other one. That is a conservative backstop,
        kept until qubit ownership is actually enforced; see `QVecOps.td`.

        Example:
        ```mlir
        // One instruction, a Hadamard on all four qubits in %qs.
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
