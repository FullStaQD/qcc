// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

include "mlir/Pass/PassBase.td"

def JaspCheckStaticQubitAllocation : Pass<"jasp-check-static-qubit-allocation"> {
  let summary = "Validate that qubit array allocations use compile-time constant sizes.";
  let description = [{
      Verifies all qubit memref allocations have static sizes and reports diagnostic
      errors for non-constant or invalid sizes.

      An example of a correct IR is the following:

      ```mlir
      %0 = "arith.constant"() <{value = dense<3> : tensor<i64>}> : () -> tensor<i64>
      %1, %2 = "jasp.create_qubits"(%0, %arg14) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
      ```

      in which the size of `jasp.create_qubit` is known at runtime.

      On the other hand, in the following snippet of code:

      ```mlir
      func.func public @main(%arg14: !jasp.QuantumState, %s: tensor<i64>) attributes { qcc.entry_point } {
        %1, %2 = "jasp.create_qubits"(%s, %arg14) : (tensor<i64>, !jasp.QuantumState) -> (!jasp.QubitArray, !jasp.QuantumState)
        ...
      }
      ```

      the compilation process will prompt an error since the number of element that `jasp.create_qubits` needs to allocate
      is unknown at compile time.

      The compiler will prompt an error message even if the size of the register we want to allocate is negative (for example, wrongly initialized constants).

      We assume constant propagation to be performed via `mlir::Canonicalization` before calling this step.
   }];
}

def JaspToQC : Pass<"jasp-to-qc"> {
  let summary = "Convert jasp dialect to QC dialect.";

  let description = [{
      This pass converts all operations from qrisp jasp dialect
      (see https://qrisp.eu/reference/Jasp/MLIR%20Interface.html)
      to their equivalent operations in the QC dialect.
  }];

  let dependentDialects = ["mlir::qc::QCDialect", "mlir::tensor::TensorDialect", "mlir::memref::MemRefDialect",
                           "mlir::scf::SCFDialect", "mlir::arith::ArithDialect"];
}

def ConvertMemrefToStaticQubits : Pass<"convert-memref-to-static-qubits"> {
  let summary = "Replace dynamic qubit array loads with static qubits.";
  let description = [{ First, substitutes `memref.alloc` with a list of `qc.static` allocation. Subsequently,
      transforms `memref.load` on qubit arrays into direct `qc.static` references.
      Requires compile-time constant indices (should be called after a `jasp-check-static-qubit-allocation` step).
      Providing as input the following IR :

      ```mlir
      %0 = "arith.constant"()<{value = dense<3>: tensor<i64>}> : () -> tensor<i64>
      %1, %2 = "jasp.create_qubits"(%0, %arg14) : (tensor<i64>, !jasp.QuantumState) ->(!jasp.QubitArray, !jasp.QuantumState)
      ```

      the pass will translate it into:

      ```mlir
      %0 = qc.static 0 : !qc.qubit
      %1 = qc.static 1 : !qc.qubit
      %2 = qc.static 2 : !qc.qubit
      ```

      in which the allocation of three qubits has been turned into 3 separate static allocations.
  }];
  let dependentDialects = ["mlir::qc::QCDialect"];
}

def AddEntrypointToMain : Pass<"add-entrypoint-to-main", "mlir::ModuleOp"> {
  let summary = "Adds the `qcc.entry_point` attribute to any function called `@main`.";
  let description = [{
      The QIR conversion pipeline relies on the `qcc.entry_point` attribute to
      identify the function from which a quantum program starts. Frontends such
      as qrisp follow the convention of naming the entry-point function `@main`
      in the generated MLIR but do not attach the attribute themselves.

      This pass looks up the function whose name matches the configured
      entry-point name (`main` by default) and attaches the `qcc.entry_point`
      unit attribute to it. If the function already carries the attribute, the
      pass is a no-op. If no function with the configured name can be found,
      the pass emits an error and fails.

      Note that the pass does not inspect other functions in the module: any
      pre-existing `qcc.entry_point` annotation on a different function is left
      untouched.

      TODO: This convention will likely have to evolve once the program input
      becomes more complex (multiple kernels, a separate classical entry-point,
      etc.).
  }];

  let options = [
    Option<"entryPointName", "entry-point-name", "std::string", /*default=*/"\"main\"",
           "Name of the function to be marked as the entry-point.">
  ];

  let dependentDialects = ["mlir::func::FuncDialect"];
}
