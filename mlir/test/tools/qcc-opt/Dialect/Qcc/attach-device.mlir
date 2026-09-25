// RUN: qcc-opt %s --qcc-attach-device=file=%S/Inputs/device-2x3.mlir | FileCheck %s
// RUN: not qcc-opt %s --qcc-attach-device=file=%S/Inputs/does-not-exist.mlir 2>&1 | FileCheck %s --check-prefix=CHECK-MISSING-FILE
// RUN: not qcc-opt %s --qcc-attach-device=file=%S/Inputs/no-device.mlir 2>&1 | FileCheck %s --check-prefix=CHECK-NO-DEVICE
// RUN: not qcc-opt %s --qcc-attach-device=file=%S/Inputs/device-2x3.mlir --qcc-attach-device=file=%S/Inputs/device-2x3.mlir 2>&1 | FileCheck %s --check-prefix=CHECK-PRESENT
// RUN: not qcc-opt %s --qcc-attach-device 2>&1 | FileCheck %s --check-prefix=CHECK-NO-FILE

// CHECK: #magic_trap = #magic.trap<capacity = 3, couplings = [dense<0.000000e+00> : tensor<1x1xf64>, dense<{{.*}}> : tensor<2x2xf64>, dense<{{.*}}> : tensor<3x3xf64>]>
// CHECK: #magic_device = #magic.device<name = "two-trap-2x3", time_unit_ns = 1000, initial_occupancies = [2, 2], traps = [#magic_trap, #magic_trap]>
// CHECK: module attributes {qcc.device = #magic_device}
// CHECK:   func.func @main() attributes {qcc.entry_point}

// CHECK-MISSING-FILE: error: cannot read device file '{{.*}}does-not-exist.mlir'
// CHECK-NO-DEVICE: no-device.mlir:2:1: error: device file '{{.*}}no-device.mlir' carries no 'qcc.device' attribute
// CHECK-PRESENT: error: module already carries a 'qcc.device' attribute
// CHECK-NO-FILE: error: option 'file' is required

module {
  func.func @main() attributes {qcc.entry_point} {
    return
  }
}
