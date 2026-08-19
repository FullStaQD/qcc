// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def ConvertQIRToIntrinsics : Pass<"convert-qir-to-intrinsics", "mlir::ModuleOp"> { // FIXME: ...to-hisepq-intrinsics ?
  let summary = "Replaces QIR QIS call ops with HiSEP-Q intrinsics.";

  let description = [{
      Takes a module that has already been lowered to QIR (i.e., the body
      contains `llvm.call` ops targeting `__quantum__qis__*__body` functions)
      and replaces those calls with `llvm.call_intrinsic` ops targeting the
      RISC-V QV extension, aka HiSEP-Q (e.g. `llvm.riscv.qv.h`, `llvm.riscv.qv.cx`).

      Each qubit pointer argument (produced by `llvm.inttoptr` of a constant
      integer index) is re-encoded as a `vector<[8]xi8>` scalable-vector value
      carrying that index in lane 0, matching the `anyvector` operand that the
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
