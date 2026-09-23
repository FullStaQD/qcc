// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --mlir-print-op-generic | qcc-opt | FileCheck %s

// Round trip of the metadata attributes. Their values belong to the dialect of the architecture, so the device
// attribute is only used here, not defined here; its own round trip is in the magic dialect's `attrs.mlir`.

// CHECK: #magic_device = #magic.device<name = "single-trap", time_unit_ns = 500, initial_occupancies = [1], traps = [#magic_trap]>

// CHECK: module attributes {qcc.device = #magic_device}
module attributes {qcc.device = #magic.device<name = "single-trap", time_unit_ns = 500, initial_occupancies = [1], traps = [#magic.trap<capacity = 1, couplings = [dense<0.0> : tensor<1x1xf64>]>]>} {
  // CHECK: func.func @main() attributes {qcc.entry_point}
  func.func @main() attributes {qcc.entry_point} {
    return
  }

  // The entry point marker is also fine on an `llvm.func`.
  // CHECK: llvm.func @kernel() attributes {qcc.entry_point}
  llvm.func @kernel() attributes {qcc.entry_point} {
    llvm.return
  }
}
