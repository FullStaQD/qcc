// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def PrepToQIR : Pass<"prep-to-qir", "mlir::ModuleOp"> {
  let summary = "Very first pass to apply for a conversion to QIR (adaptive).";

  let description = [{
      Adds the QIR function declarations (runtime functions like `__quantum__rt__initialize` and QIS functions like
      `__quantum__qis__x__body`) as well as the llvm module flags (capabilities) to the module.

      Assumptions:
      - Input IR contains a single top-level module.

      TODO:
      - Currently we hardcode the capabilities, must be target specific in the future.
   }];

  let dependentDialects = [
    "mlir::LLVM::LLVMDialect"
  ];
}

def ConvertQRefToQIR : Pass<"convert-qref-to-qir", "mlir::func::FuncOp"> {
  let summary = "Lowers the qref dialect into QIR (adaptive) conforming LLVM dialect.";

  let description = [{
      The pass anchors to a function and guarantees the following:

      - The QIR initialization function is inserted at the start of the function.
      - Required QIR attributes (like `required_num_qubits`) are added to the function. Via `passthrough`.
      - `qref` gates, measurements and resets are translated to QIR QIS function calls. A static qubit becomes the
        pointer whose address is its index.
      - Only the llvm dialect (in the function body) is considered legal after this pass.
      - TODO: To support some kind of output recording: We lower `aux.record_bool` to the
        bool recording function. Currently no other output recording function are in use.

      The pass does not decompose gates. It supports the gates `x`, `h`, `rz`, `s`, `sdg`, `t`, `tdg` and `cx`, and
      measurements and resets in basis `z`; anything else makes it fail.

      Preconditions:
      - Every qubit is a static qubit: it comes from `qcc.static_ref`, not from `qcc.alloc`, an argument or an array.
        Only gates, measurements and resets use it.
      - Only entry points (functions marked `qcc.entry_point`) use qubits; the pass leaves other functions alone.
        TODO: Before we extend support we have to figure out how to do qubit mapping across function calls.

      TODO: We hardcode hardware capabilities for now as we have no way to query
      those. It is currently tailored towards HiSEP-Q. In particular we use
      static qubit and result management. Note that HiSEP-Q has a dedicated
      (single bit) measurement result register for each qubit. It refers to the
      last measurement done at the respective qubit. Hence we use the exact same
      index for the result of a qubit measurement.

      Assumptions:
      - All required QIR functions (e.g. `__quantum__rt__initialize`) are already declared in the
        containing module.
      - TODO: It expects a global dummy-label to be present for the record function:
        `llvm.mlir.global internal constant @".qir_dummy_label"("arbitrary_label\00") {addr_space = 0 : i32}`.

      To satisfy the assumptions you likely want to run `-prep-to-qir` before this pass. Sometime
      after this pass you probably also want to run `-finalize-to-qir`.
   }];

  let dependentDialects = [
    "mlir::LLVM::LLVMDialect"
  ];
}

def FinalizeToQIR : Pass<"finalize-to-qir", "mlir::ModuleOp"> {
  let summary = "Ensures that no non-llvm ops are left in the module.";

  let description = [{
      Essentially lowers the `func` dialect (to llvm) and does a bit of cleanup.

      It assumes that the bodies of the functions are already properly lowered
      (except `func` related ops).
   }];

  let dependentDialects = [
    "mlir::LLVM::LLVMDialect"
  ];
}
