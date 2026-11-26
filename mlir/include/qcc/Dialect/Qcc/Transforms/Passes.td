// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCC_TRANSFORMS_PASSES_TD_
#define INCLUDE_QCC_DIALECT_QCC_TRANSFORMS_PASSES_TD_

include "mlir/Pass/PassBase.td"

def QccAttachDevice : Pass<"qcc-attach-device", "mlir::ModuleOp"> {
  let summary = "Attaches the device description from a device file to the module.";

  let description = [{
      Reads a device file and copies its `qcc.device` attribute onto the module. A device file is a minimal module
      that carries only that attribute, so attribute aliases work:

      ```mlir
      #trap = #magic.trap<capacity = 2, couplings = [dense<0.0> : tensor<1x1xf64>,
                                                     dense<[[0.0, 1.0], [1.0, 0.0]]> : tensor<2x2xf64>]>
      module attributes {qcc.device = #magic.device<name = "two-trap", time_unit_ns = 1000, traps = [#trap, #trap]>} {}
      ```

      Fails if the file cannot be read, carries no `qcc.device` attribute, or if the module already has one.
  }];

  let options = [
    Option<"file", "file", "std::string", /*default=*/"\"\"", "Path of the device file.">
  ];

  let dependentDialects = ["qcc::QccDialect", "qcc::magic::MagicDialect"];
}

def QccOneShotBufferize : Pass<"qcc-one-shot-bufferize", "mlir::ModuleOp"> {
  let summary = "One-Shot Bufferize, except for arrays of qubits.";

  let description = [{
      Runs One-Shot Bufferize like `one-shot-bufferize`, but leaves the ops on arrays of qubits
      (`tensor<?x!qcc.qubit_ref>`) alone: an array of qubits never changes, only its elements are references. So
      `qcc.alloc`, `qcc.dealloc` and `tensor` ops on arrays of qubits stay, while other tensors become memrefs.

      Precondition: only `qcc.alloc`, `qcc.dealloc` and `tensor` ops hold arrays of qubits, as operands, results or
      block arguments. In particular, no loop carries an array and no function takes or returns one. A canonicalizer
      removes an array that a loop only passes through.

      The options are those of `one-shot-bufferize` with the same names.
  }];

  let options = [
    Option<"allowReturnAllocsFromLoops", "allow-return-allocs-from-loops", "bool", /*default=*/"false",
           "Allows returning/yielding new allocations from a loop.">,
    Option<"allowUnknownOps", "allow-unknown-ops", "bool", /*default=*/"false",
           "Allows unknown (not bufferizable) ops in the input IR.">,
    Option<"bufferizeFunctionBoundaries", "bufferize-function-boundaries", "bool", /*default=*/"false",
           "Bufferize function boundaries (experimental).">
  ];

  let dependentDialects = ["mlir::bufferization::BufferizationDialect", "mlir::memref::MemRefDialect"];
}

#endif // INCLUDE_QCC_DIALECT_QCC_TRANSFORMS_PASSES_TD_
