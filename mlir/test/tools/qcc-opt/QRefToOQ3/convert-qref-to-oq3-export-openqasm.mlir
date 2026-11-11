// RUN: qcc-opt %s --split-input-file --convert-qref-to-oq3 \
// RUN:   | qcc-translate --split-input-file --export-openqasm | FileCheck %s --strict-whitespace

// Tests of `--convert-qref-to-oq3` with checks against the exported OpenQASM.

// The module becomes an OpenQASM program of qcc's default version, and `stdgates.inc` is included for standard gates.

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_single_gate() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  qcc.dealloc %q : !qcc.qubit_ref
  return
}

// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit q0;
// CHECK-NEXT:  h q0;
// CHECK-EMPTY:

// -----

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_array_qubits() attributes {qcc.entry_point} {
  %r = qcc.alloc : tensor<3x!qcc.qubit_ref>
  %empty = qcc.alloc : tensor<0x!qcc.qubit_ref>
  %c2 = arith.constant 2 : index
  %q = tensor.extract %r[%c2] : tensor<3x!qcc.qubit_ref>
  %z1 = arith.constant 0.125 : f64
  %y = arith.constant 0.5 : f64
  %z2 = arith.constant 0.25 : f64
  qref.single u_zyz(%z1, %y, %z2) %q : f64, !qcc.qubit_ref
  %p = qcc.static_ref [4] : !qcc.qubit_ref
  qref.single u_zyz(%z1, %y, %z2) %p : f64, !qcc.qubit_ref
  return
}

// CHECK-NEXT:  qubit[3] q0;
// CHECK-NEXT:  qubit[0] q1;
// CHECK-NEXT:  U(0.5, 0.25, 0.125) q0[2];
// CHECK-NEXT:  U(0.5, 0.25, 0.125) $4;
// CHECK-EMPTY:

// -----

// Without standard gates, `stdgates.inc` isn't included.

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_no_stdgates_include() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  %z1 = arith.constant 0.125 : f64
  %y = arith.constant 0.5 : f64
  %z2 = arith.constant 0.25 : f64
  qref.single u_zyz(%z1, %y, %z2) %q : f64, !qcc.qubit_ref
  return
}

// CHECK-NOT:   include
// CHECK:       qubit q0;
// CHECK-NEXT:  U(0.5, 0.25, 0.125) q0;
// CHECK-EMPTY:

// -----

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_single_qubit_gates() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  %a = arith.constant 1.5 : f64
  qref.single x %q : !qcc.qubit_ref
  qref.single y %q : !qcc.qubit_ref
  qref.single z %q : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  qref.single s %q : !qcc.qubit_ref
  qref.single sdg %q : !qcc.qubit_ref
  qref.single t %q : !qcc.qubit_ref
  qref.single tdg %q : !qcc.qubit_ref
  qref.single sx %q : !qcc.qubit_ref
  qref.single sxdg %q : !qcc.qubit_ref
  qref.single rx(%a) %q : f64, !qcc.qubit_ref
  qref.single ry(%a) %q : f64, !qcc.qubit_ref
  qref.single rz(%a) %q : f64, !qcc.qubit_ref
  return
}

// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit q0;
// CHECK-NEXT:  x q0;
// CHECK-NEXT:  y q0;
// CHECK-NEXT:  z q0;
// CHECK-NEXT:  h q0;
// CHECK-NEXT:  s q0;
// CHECK-NEXT:  sdg q0;
// CHECK-NEXT:  t q0;
// CHECK-NEXT:  tdg q0;
// CHECK-NEXT:  sx q0;
// CHECK-NEXT:  rx(-(pi / 2)) q0;
// CHECK-NEXT:  rx(1.5) q0;
// CHECK-NEXT:  ry(1.5) q0;
// CHECK-NEXT:  rz(1.5) q0;
// CHECK-EMPTY:

// -----

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_two_qubit_gates() attributes {qcc.entry_point} {
  %a = qcc.alloc : !qcc.qubit_ref
  %b = qcc.alloc : !qcc.qubit_ref
  %theta = arith.constant 0.5 : f64
  qref.pair cx %a, %b : !qcc.qubit_ref
  qref.pair cy %b, %a : !qcc.qubit_ref
  qref.pair cz %a, %b : !qcc.qubit_ref
  qref.pair swap %a, %b : !qcc.qubit_ref
  qref.pair cp(%theta) %a, %b : f64, !qcc.qubit_ref
  return
}

// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit q0;
// CHECK-NEXT:  qubit q1;
// CHECK-NEXT:  cx q0, q1;
// CHECK-NEXT:  cy q1, q0;
// CHECK-NEXT:  cz q0, q1;
// CHECK-NEXT:  swap q0, q1;
// CHECK-NEXT:  cp(0.5) q0, q1;
// CHECK-EMPTY:

// -----

// An unused measurement is a statement.

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_unused_measurement() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  %m = qref.measure z %q : !qcc.qubit_ref -> i1
  return
}

// CHECK-NEXT:  qubit q0;
// CHECK-NEXT:  measure q0;
// CHECK-EMPTY:

// -----

// A measurement that a store uses next is assigned directly. Pure ops between a measurement and its store don't matter.

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_stored_measurement() attributes {qcc.entry_point} {
  %r = qcc.alloc : tensor<2x!qcc.qubit_ref>
  %b = memref.alloca() : memref<i1>
  %c = memref.alloca() : memref<2xi1>
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %q0 = tensor.extract %r[%c0] : tensor<2x!qcc.qubit_ref>
  %q1 = tensor.extract %r[%c1] : tensor<2x!qcc.qubit_ref>
  %m0 = qref.measure z %q0 : !qcc.qubit_ref -> i1
  memref.store %m0, %b[] : memref<i1>
  %m1 = qref.measure z %q1 : !qcc.qubit_ref -> i1
  %index = arith.constant 1 : index
  memref.store %m1, %c[%index] : memref<2xi1>
  return
}

// CHECK-NEXT:  qubit[2] q0;
// CHECK-NEXT:  bit c1;
// CHECK-NEXT:  bit[2] c2;
// CHECK-NEXT:  c1 = measure q0[0];
// CHECK-NEXT:  c2[1] = measure q0[1];
// CHECK-EMPTY:

// -----

// A measurement with several uses gets a `bit` variable of its own, which every use reads.

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_measurement_used_twice() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  %b = memref.alloca() : memref<i1>
  %c = memref.alloca() : memref<2xi1>
  %c0 = arith.constant 0 : index
  %m = qref.measure z %q : !qcc.qubit_ref -> i1
  memref.store %m, %c[%c0] : memref<2xi1>
  memref.store %m, %b[] : memref<i1>
  return
}

// CHECK-NEXT:  qubit q0;
// CHECK-NEXT:  bit c1;
// CHECK-NEXT:  bit[2] c2;
// CHECK-NEXT:  bit m3 = measure q0;
// CHECK-NEXT:  c2[0] = m3;
// CHECK-NEXT:  c1 = m3;
// CHECK-EMPTY:

// -----

// A measurement whose store doesn't come next gets a `bit` variable too.

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_measurement_gate_before_store() attributes {qcc.entry_point} {
  %q0 = qcc.alloc : !qcc.qubit_ref
  %q1 = qcc.alloc : !qcc.qubit_ref
  %b = memref.alloca() : memref<i1>
  %m = qref.measure z %q0 : !qcc.qubit_ref -> i1
  qref.single x %q1 : !qcc.qubit_ref
  memref.store %m, %b[] : memref<i1>
  return
}

// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit q0;
// CHECK-NEXT:  qubit q1;
// CHECK-NEXT:  bit c2;
// CHECK-NEXT:  bit m3 = measure q0;
// CHECK-NEXT:  x q1;
// CHECK-NEXT:  c2 = m3;
// CHECK-EMPTY:

// -----

// A measurement in the x basis is one in the z basis between Hadamard gates.

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_x_basis_measurement() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  %b = memref.alloca() : memref<i1>
  %m = qref.measure x %q : !qcc.qubit_ref -> i1
  memref.store %m, %b[] : memref<i1>
  return
}

// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit q0;
// CHECK-NEXT:  bit c1;
// CHECK-NEXT:  h q0;
// CHECK-NEXT:  bit m2 = measure q0;
// CHECK-NEXT:  h q0;
// CHECK-NEXT:  c1 = m2;
// CHECK-EMPTY:

// -----

// A reset in the x basis is one in the z basis followed by a Hadamard gate.

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_resets() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  qref.reset z %q : !qcc.qubit_ref
  qref.reset x %q : !qcc.qubit_ref
  return
}

// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit q0;
// CHECK-NEXT:  reset q0;
// CHECK-NEXT:  reset q0;
// CHECK-NEXT:  h q0;
// CHECK-EMPTY:

// -----

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_bits() attributes {qcc.entry_point} {
  %alloca = memref.alloca() : memref<i1>
  %b = memref.cast %alloca : memref<i1> to memref<i1, strided<[], offset: ?>>
  %c = memref.alloca() : memref<3xi1>
  %bit2 = memref.subview %c[2] [1] [1] : memref<3xi1> to memref<i1, strided<[], offset: 2>>
  %value = memref.load %b[] : memref<i1, strided<[], offset: ?>>
  memref.store %value, %bit2[] : memref<i1, strided<[], offset: 2>>
  %one = arith.constant 1 : index
  %two = arith.addi %one, %one : index
  %bit_two = memref.subview %c[%two] [1] [1] : memref<3xi1> to memref<i1, strided<[], offset: ?>>
  %true = arith.constant true
  memref.store %true, %bit_two[] : memref<i1, strided<[], offset: ?>>
  %false = arith.constant false
  memref.store %false, %b[] : memref<i1, strided<[], offset: ?>>
  return
}

// CHECK-NEXT:  bit c0;
// CHECK-NEXT:  bit[3] c1;
// CHECK-NEXT:  c1[2] = c0;
// CHECK-NEXT:  c1[1 + 1] = 1;
// CHECK-NEXT:  c0 = 0;
// CHECK-EMPTY:

// -----

// Arithmetic on integers and floats. Negative constants are negated literals.

// CHECK-LABEL: OPENQASM 3.1;
func.func @check_arithmetic() attributes {qcc.entry_point} {
  %r = qcc.alloc : tensor<8x!qcc.qubit_ref>
  %c3 = arith.constant 3 : i64
  %c1 = arith.constant 1 : i64
  %cm4 = arith.constant -4 : i64
  %c2 = arith.constant 2 : i64
  %diff = arith.subi %c3, %c1 : i64  // 3 - 1
  %prod = arith.muli %cm4, %c2 : i64  // -4 * 2
  %quot = arith.divsi %prod, %c2 : i64  // (-4 * 2) / 2
  %sum = arith.addi %diff, %quot : i64  // (3 - 1) + ((-4 * 2) / 2)
  %index = arith.index_cast %sum : i64 to index
  %c2_index = arith.constant 2 : index
  %position = arith.muli %index, %c2_index : index  // INDEX: ((3 - 1) + ((-4 * 2) / 2)) * 2
  %q = tensor.extract %r[%position] : tensor<8x!qcc.qubit_ref>
  %a = arith.constant 1.5 : f64
  %b = arith.constant 2.0e-20 : f64
  %fdiff = arith.subf %a, %b : f64  // 1.5 - 2.0e-20
  %neg = arith.negf %a : f64  // -1.5
  %fprod = arith.mulf %fdiff, %neg : f64  // (1.5 - 2.0e-20) * -1.5
  %fsum = arith.sitofp %sum : i64 to f64
  %fquot = arith.divf %fprod, %fsum : f64  // ANGLE: ((1.5 - 2.0e-20) * -1.5) / (3 - 1 + -4 * 2 / 2)
  qref.single rx(%fquot) %q : f64, !qcc.qubit_ref
  return
}

// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit[8] q0;
// CHECK-NEXT:  rx((1.5 - 2.0E-20) * -1.5 / (3 - 1 + -4 * 2 / 2)) q0[(3 - 1 + -4 * 2 / 2) * 2];
// CHECK-EMPTY:

// -----

// The target's `float` has its word size (32 bits in this case), so `f32` values become `float`s.

// CHECK-LABEL: OPENQASM 3.1;
module attributes {dlti.dl_spec = #dlti.dl_spec<index = 32>} {
  func.func @check_float_conversion() attributes {qcc.entry_point} {
    %q = qcc.alloc : !qcc.qubit_ref
    %a = arith.constant 0.1 : f32
    %c2 = arith.constant 2 : i32
    %b = arith.sitofp %c2 : i32 to f32
    %prod = arith.mulf %a, %b : f32
    %theta = arith.extf %prod : f32 to f64
    qref.single rx(%theta) %q : f64, !qcc.qubit_ref
    return
  }
}

// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit q0;
// CHECK-NEXT:  rx(0.1 * 2) q0;
// CHECK-EMPTY:
