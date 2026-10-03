// RUN: split-file %s %t
// RUN: not qcc %t/no-program.mlir --quantum-device=magic --device-description=%S/Inputs/device-2x3-500ns.mlir --compile-to=custom-magic 2>&1 | FileCheck %s --check-prefix=CHECK-NO-PROGRAM
// RUN: not qcc %t/two-programs.mlir --quantum-device=magic --device-description=%S/Inputs/device-2x3-500ns.mlir --compile-to=custom-magic 2>&1 | FileCheck %s --check-prefix=CHECK-TWO-PROGRAMS
// RUN: not qcc %t/foreign-op.mlir --quantum-device=magic --device-description=%S/Inputs/device-2x3-500ns.mlir --compile-to=custom-magic 2>&1 | FileCheck %s --check-prefix=CHECK-FOREIGN-OP

// What the exporter rejects although it is valid, verified magic IR.

//--- no-program.mlir

// CHECK-NO-PROGRAM: error: module holds no program to export: expected a function with a 'magic.init'
func.func @main() {
  return
}

//--- two-programs.mlir

!a = !magic.ion_chain<0, [0:1]>

func.func @main() {
  %a0 = magic.init : !a
  %m0 = magic.mzd %a0 : !a -> i1
  aux.record_int %m0 : i1
  return
}

func.func @other() {
  // CHECK-TWO-PROGRAMS: error: 'magic.init' op starts a second program: only a module with a single program can be exported
  // CHECK-TWO-PROGRAMS: note: the first program starts here
  %a0 = magic.init : !a
  %m0 = magic.mzd %a0 : !a -> i1
  aux.record_int %m0 : i1
  return
}

//--- foreign-op.mlir

!a = !magic.ion_chain<0, [0:1]>

func.func private @classical()

func.func @main() {
  %a0 = magic.init : !a
  // CHECK-FOREIGN-OP: error: 'func.call' op cannot be exported: the format has native magic ops and records only
  call @classical() : () -> ()
  %m0 = magic.mzd %a0 : !a -> i1
  aux.record_int %m0 : i1
  return
}
