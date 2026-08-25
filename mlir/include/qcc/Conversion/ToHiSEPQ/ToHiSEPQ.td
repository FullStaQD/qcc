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

def ConvertHiSEPQToIntrinsics : Pass<"convert-hisepq-to-intrinsics", "mlir::ModuleOp"> {
  let summary = "Replaces HiSEP-Q dialect ops with HiSEP-Q intrinsics.";

  // FIXME: trim this in the end.
  let description = [{
      Replaces every `hisepq` operation with the `llvm.call_intrinsic` op targeting
      the RISC-V QV extension that encodes it (`llvm.riscv.qv.h`, `llvm.riscv.qv.x`,
      `llvm.riscv.qv.cx`, `llvm.riscv.qv.mz`).

      The qubit indices are materialized as a dense `vector<Nxi8>` constant and
      inserted into a poison scalable vector, because the backend selects the QV
      instructions only for the scalable types `<vscale x {2,4,8,16,32,64} x i8>`
      (`SupportedQVVTypes`), i.e. LMUL 1/4, 1/2, 1, 2, 4 and 8. Note that
      `<vscale x 1 x i8>` (LMUL 1/8) is not among them.

      Which of the six is narrow enough depends on the hardware, so the pass reads
      the machine's guaranteed minimum VLEN from the module and picks the narrowest
      type whose runtime element count -- `knownMinElements * VLEN / 64`, since
      RISC-V scalable types are normalized against a 64-bit block -- reaches the
      qubit count. At VLEN 128 that puts the LMUL 1 to LMUL 2 step at 17 qubits;
      at VLEN 64 it sits at 9.

      ```mlir
      module attributes {hisepq.target = #dlti.map<"min_vlen" = 128 : ui32>}
      ```

      Absent that attribute the pass assumes 128, which is the floor the QV extension
      itself mandates (`FeatureVendorXQV` -> `FeatureStdExtV` ->
      `FeatureStdExtZvl128b`), so the assumption can never over-promise capacity.
      A minimum rather than an exact VLEN because that is all the RISC-V feature
      system expresses, and because nothing here could use the extra precision: the
      emitted types are scalable, so only the lower bound bounds anything.

      // FIXME: investigate.
      `hisepq.pair` reads control-before-target while the encoding puts the target
      in `vs1` and the control in `vs2`, so the two operands are swapped here.

      The dialect has value semantics, so an operation's qubit vector is usually
      the result of the operation before it. The lowering traces back past those
      to find the indices, and forwards each operation's qubit results to its
      qubit operands, which collapses the chain back onto the vector it started
      from.

      Assumptions:
      - Every qubit vector traces back to a `vector.from_elements` whose elements
        are all `qco.static` ops, so that the qubit indices are known at compile
        time.
        TODO: Lift this once the dialect grows dynamic qubits. Then the qubit
        vector becomes a runtime value and the constant folding here turns into a
        type conversion.
      - Qubit indices fit in an unsigned i8, and there are no more qubits than
        LMUL 8 holds at the minimum VLEN (64 qubits at VLEN 64, 128 at VLEN 128).
        The two are checked separately, so each diagnostic names the limit that was
        actually hit.

      Gates without an intrinsic are rejected (error).

      `llvm.riscv.qv.mz` returns void and the QISA specifies no way to read a
      measurement back, so the classical result of `hisepq.mz` is replaced with
      `poison`, i.e. the measurement result is lost.
      TODO: Support this once HiSEP-Q specifies the corresponding QISA operation.
  }];

  let dependentDialects = [
    "mlir::LLVM::LLVMDialect"
  ];
}
