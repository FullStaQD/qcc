// RUN: split-file --leading-lines %s %t
// RUN: not qcc %t/no-init.mlir --quantum-device=magic --device-description=%S/Inputs/device-2x3-500ns.mlir --compile-to=custom-magic 2>&1 | FileCheck %t/no-init.mlir
// RUN: not qcc %t/two-entry-points.mlir --quantum-device=magic --device-description=%S/Inputs/device-2x3-500ns.mlir --compile-to=custom-magic 2>&1 | FileCheck %t/two-entry-points.mlir
// RUN: not qcc %t/foreign-op.mlir --quantum-device=magic --device-description=%S/Inputs/device-2x3-500ns.mlir --compile-to=custom-magic 2>&1 | FileCheck %t/foreign-op.mlir

// What the exporter rejects although it is valid, verified magic IR.

//--- no-init.mlir

// CHECK: error: 'func.func' op cannot be exported: the entry point holds no 'magic.init'
func.func @main() {
  return
}

// -----
//--- two-entry-points.mlir

!a = !magic.ion_chain<0, [0:1]>

func.func @main() {
  %a0 = magic.init : !a
  %m0 = magic.mzd %a0 : !a -> i1
  aux.record_int %m0 : i1
  return
}

// CHECK: error: 'func.func' op is a second entry point: only a module with a single entry point can be exported
// CHECK: note: the first entry point is here
func.func @other() attributes {qcc.entry_point} {
  %a0 = magic.init : !a
  %m0 = magic.mzd %a0 : !a -> i1
  aux.record_int %m0 : i1
  return
}

// -----
//--- foreign-op.mlir

!a = !magic.ion_chain<0, [0:1]>

func.func private @classical()

func.func @main() {
  %a0 = magic.init : !a
  // CHECK: error: 'func.call' op cannot be exported: the format has native magic ops and records only
  call @classical() : () -> ()
  %m0 = magic.mzd %a0 : !a -> i1
  aux.record_int %m0 : i1
  return
}
