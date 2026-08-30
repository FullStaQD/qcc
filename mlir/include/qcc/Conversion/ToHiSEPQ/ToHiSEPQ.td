// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def ConvertQIRToHiSEPQIntrinsics : Pass<"convert-qir-to-hisepq-intrinsics", "mlir::ModuleOp"> {
  let summary = "Replaces QIR QIS call ops with HiSEP-Q intrinsics.";

  let description = [{
      Takes a module that has already been lowered to QIR (i.e., the body
      contains `llvm.call` ops targeting `__quantum__qis__*__body` functions)
      and replaces those calls with `llvm.call_intrinsic` ops targeting the
      RISC-V QV extension, aka HiSEP-Q (e.g. `llvm.riscv.qv.h`, `llvm.riscv.qv.cx`).

      Each qubit pointer argument (produced by `llvm.inttoptr` of a constant
      integer index) is re-encoded as a `vector<[8]xi8>` scalable-vector value
      carrying that index in element 0, matching the `anyvector` operand that the
      QVSingle / QVPair intrinsics expect.

      The QIR runtime calls below have no HiSEP-Q QISA counterpart yet, so they
      are dropped:
      - `__quantum__rt__initialize` calls are erased.
      - `__quantum__rt__read_result` calls are replaced with `poison : i1`,
        i.e. the measurement result is lost.
      - `__quantum__rt__bool_record_output` and `__quantum__rt__int_record_output`
        calls are erased, so program output is not recorded.
      TODO: Support these once HiSEP-Q specifies the corresponding QISA
      operations. We should be able to support all the QIR Adaptive Profile
      runtime calls.

      Leftover QIR function declarations are removed from the module.

      Assumptions:
      - The module has been fully lowered by the ToQIR pipeline
        (`prep-to-qir`, `convert-qc-to-qir`, `finalize-to-qir`) so all gate
        ops appear as `llvm.call` with a statically-known callee symbol.
      - Qubit pointers were produced by `llvm.inttoptr(llvm.mlir.constant(N : i64))`,
        i.e. the static qubit management scheme used by `convert-qc-to-qir`.
   }];

  let dependentDialects = [
    "mlir::LLVM::LLVMDialect"
  ];
}

def EmitHiSEPQStart : Pass<"emit-hisepq-start", "mlir::ModuleOp"> {
  let summary = "Emits the HiSEP-Q `_start` entry point.";

  let description = [{
      Appends a `_start` function that supersedes the module's entry point as
      the entry point of the hardware. It sets the stack pointer to
      `__stack_top`, jumps to the original entry point and loops forever when
      that returns.

      TODO: Check with HiSEP-Q Team if looping forever is the only thing we can
      do at the end.

      Both symbol names are contractual with the HiSEP-Q linker script
      (`hisepq.ld`), which declares `ENTRY(_start)`, pulls `.text._start` to
      the boot address and provides `__stack_top`.

      Assumes that *exactly* one function is tagged entry point.

      TODO: Drop this pass once HiSEP-Q ships a crt0. Then qcc can emit a plain
      `main` and leave the startup code to the runtime.
  }];

  let dependentDialects = [
    "mlir::LLVM::LLVMDialect"
  ];
}

def ConvertQVecToHiSEPQIntrinsics : Pass<"convert-qvec-to-hisepq-intrinsics", "mlir::ModuleOp"> {
  let summary = "Replaces `qvec` ops with HiSEP-Q intrinsics.";

  let description = [{
      Replaces every `qvec` operation with the `llvm.call_intrinsic` op targeting the RISC-V QV extension that encodes
      it (`llvm.riscv.qv.h`, `llvm.riscv.qv.cx`, `llvm.riscv.qv.mz`, etc).

      The qubit operands are materialized at the start of scalable vectors `vector<[N]xi{QEW}>` (N guaranteed to be a
      power of two) whose unoccupied elements are poison valued. Recall that the number of elements in a scalable
      vector `vector<[N]xi{QEW}>` is `vscale * N` where `vscale = VLEN / 64`. The set of allowed `N` follows from the
      LMUL register groups the QV instructions address, `{mf4, mf2, m1, m2, m4, m8}`.

      The machine is described by two pass options:

      - `min-vlen`, the guaranteed lower bound on VLEN, and
      - `qubit-element-width`, or QEW, how many bits one qubit index occupies (used as SEW for qubit instructions).

      Together they select the narrowest `N` that fits all qubits, or error if the vector register capacity is
      exceeded even at the highest LMUL.

      // FIXME: investigate.
      `qvec.pair` reads control-before-target while the encoding puts the target in `vs1` and the control in `vs2`, so
      the two operands are swapped here.

      Assumptions:
      - Every qubit vector traces back to a `vector.from_elements` whose elements are all `qco.static` ops, so that the
        qubit indices are known at compile time.
        TODO: Lift this once the dialect grows dynamic qubits. Then the qubit vector becomes a runtime value and the
        constant folding here turns into a type conversion.
      - Qubit indices are encoded in an unsigned `i{QEW}`, and there are no more qubits than LMUL 8 holds at the minimum
        VLEN.

      Gates without an intrinsic are rejected (error).

      `llvm.riscv.qv.mz` returns void and the QISA specifies no way to read a measurement back, so the classical result
      of `qvec.mz` is replaced with `poison`, i.e. the measurement result is lost.
      TODO: Support this once HiSEP-Q specifies the corresponding QISA operation.
  }];

  let options = [
    Option<"minVLen", "min-vlen", "unsigned", /*default=*/"64",
           "Guaranteed lower bound on VLEN in bits; a power of two, at least 64.">,
    Option<"qubitElementWidth", "qubit-element-width", "unsigned", /*default=*/"8",
           "Number of bits one qubit index occupies (QEW); either 8 or 16.">
  ];

  let dependentDialects = [
    "mlir::LLVM::LLVMDialect"
  ];
}
