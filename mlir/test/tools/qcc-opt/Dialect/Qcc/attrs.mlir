// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --mlir-print-op-generic | qcc-opt | FileCheck %s

// Round trip of the device attributes. Identical traps are written once (alias) and printed once (the dialect's alias
// hook); the nested traps may be spelled as an alias, qualified or stripped.

// CHECK: #magic_trap = #qcc.magic_trap<capacity = 2, couplings = [dense<0.000000e+00> : tensor<1x1xf64>, dense<{{\[\[}}0.000000e+00, 2.974000e+02], [2.974000e+02, 0.000000e+00]]> : tensor<2x2xf64>]>
// CHECK: #magic_trap1 = #qcc.magic_trap<capacity = 1, couplings = [dense<0.000000e+00> : tensor<1x1xf64>]>
// CHECK: #magic_device = #qcc.magic_device<name = "two-trap", time_unit_ns = 1000, initial_occupancies = [2, 1], traps = [#magic_trap, #magic_trap1]>
// CHECK: #magic_device1 = #qcc.magic_device<name = "single-trap", time_unit_ns = 500, initial_occupancies = [1], traps = [#magic_trap1]>
#trap = #qcc.magic_trap<capacity = 2, couplings = [dense<0.0> : tensor<1x1xf64>, dense<[[0.0, 297.4], [297.4, 0.0]]> : tensor<2x2xf64>]>

// CHECK: module attributes {qcc.device = #magic_device}
module attributes {qcc.device = #qcc.magic_device<name = "two-trap", time_unit_ns = 1000, initial_occupancies = [2, 1], traps = [#trap, <capacity = 1, couplings = [dense<0.0> : tensor<1x1xf64>]>]>} {
  // CHECK: func.func @main() attributes {qcc.entry_point}
  func.func @main() attributes {qcc.entry_point} {
    return
  }
}

// CHECK: module attributes {qcc.device = #magic_device1}
module attributes {qcc.device = #qcc.magic_device<name = "single-trap", time_unit_ns = 500, initial_occupancies = [1], traps = [#qcc.magic_trap<capacity = 1, couplings = [dense<0.0> : tensor<1x1xf64>]>]>} {
  // The entry point marker is also fine on an `llvm.func`.
  // CHECK: llvm.func @kernel() attributes {qcc.entry_point}
  llvm.func @kernel() attributes {qcc.entry_point} {
    llvm.return
  }
}
