// RUN: qcc-opt %s --split-input-file --convert-qref-to-oq3 \
// RUN:   | qcc-translate --split-input-file --export-openqasm | FileCheck %s --strict-whitespace
// RUN: qcc-opt %s --split-input-file --convert-qref-to-oq3 | FileCheck %s --check-prefix=IR

// The module becomes an OpenQASM program of qcc's default version, and `stdgates.inc` is included for standard gates.

// IR-LABEL: module attributes {oq3.version = #oq3.version<3, 1>} {
// IR-NEXT:    func.func @main() attributes {qcc.entry_point} {
// IR-NEXT:      oq3.include "stdgates.inc" id 0
// IR-NEXT:      %[[Q:.*]] = oq3.qubit_decl "q0" : !qcc.qubit_ref
// IR-NEXT:      oq3.gate_call @h [%[[Q]] : !qcc.qubit_ref]
// IR-NEXT:      return

// CHECK-LABEL: OPENQASM 3.1;
// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit q0;
// CHECK-NEXT:  h q0;
// CHECK-EMPTY:
func.func @main() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  qref.single h %q : !qcc.qubit_ref
  qcc.dealloc %q : !qcc.qubit_ref
  return
}

// -----

// Arrays of qubits are registers, static qubits are physical qubits. Without standard gates, nothing is included.

// CHECK-LABEL: OPENQASM 3.1;
// CHECK-NEXT:  qubit[3] q0;
// CHECK-NEXT:  qubit[0] q1;
// CHECK-NEXT:  U(0.5, 0.25, 0.125) q0[2];
// CHECK-NEXT:  U(0.5, 0.25, 0.125) $4;
// CHECK-EMPTY:
func.func @main() attributes {qcc.entry_point} {
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

// -----

// Single-qubit gates. `sxdg` is `rx(-π/2)` up to a global phase.

// CHECK-LABEL: OPENQASM 3.1;
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
func.func @main() attributes {qcc.entry_point} {
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

// -----

// Two-qubit gates.

// CHECK-LABEL: OPENQASM 3.1;
// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit q0;
// CHECK-NEXT:  qubit q1;
// CHECK-NEXT:  cx q0, q1;
// CHECK-NEXT:  cy q1, q0;
// CHECK-NEXT:  cz q0, q1;
// CHECK-NEXT:  swap q0, q1;
// CHECK-NEXT:  cp(0.5) q0, q1;
// CHECK-EMPTY:
func.func @main() attributes {qcc.entry_point} {
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

// -----

// Measurements: an unused one is a statement, one that a store uses next is assigned directly. Others get a `bit`
// variable of their own, which every use reads. A measurement or reset in the x basis is one in the z basis between
// Hadamard gates.

// CHECK-LABEL: OPENQASM 3.1;
// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit[2] q0;
// CHECK-NEXT:  bit c1;
// CHECK-NEXT:  bit[2] c2;
// CHECK-NEXT:  measure q0[0];
// CHECK-NEXT:  c1 = measure q0[0];
// CHECK-NEXT:  c2[1] = measure q0[1];
// CHECK-NEXT:  bit m3 = measure q0[0];
// CHECK-NEXT:  x q0[1];
// CHECK-NEXT:  c2[0] = m3;
// CHECK-NEXT:  c1 = m3;
// CHECK-NEXT:  h q0[1];
// CHECK-NEXT:  bit m4 = measure q0[1];
// CHECK-NEXT:  h q0[1];
// CHECK-NEXT:  c1 = m4;
// CHECK-NEXT:  reset q0[0];
// CHECK-NEXT:  reset q0[1];
// CHECK-NEXT:  h q0[1];
// CHECK-EMPTY:
func.func @main() attributes {qcc.entry_point} {
  %r = qcc.alloc : tensor<2x!qcc.qubit_ref>
  %b = memref.alloca() : memref<i1>
  %c = memref.alloca() : memref<2xi1>
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %q0 = tensor.extract %r[%c0] : tensor<2x!qcc.qubit_ref>
  %q1 = tensor.extract %r[%c1] : tensor<2x!qcc.qubit_ref>
  %unused = qref.measure z %q0 : !qcc.qubit_ref -> i1
  %direct = qref.measure z %q0 : !qcc.qubit_ref -> i1
  memref.store %direct, %b[] : memref<i1>
  // Pure ops between a measurement and its store don't matter.
  %m1 = qref.measure z %q1 : !qcc.qubit_ref -> i1
  %index = arith.constant 1 : index
  memref.store %m1, %c[%index] : memref<2xi1>
  // Used twice, and a gate comes between.
  %twice = qref.measure z %q0 : !qcc.qubit_ref -> i1
  qref.single x %q1 : !qcc.qubit_ref
  memref.store %twice, %c[%c0] : memref<2xi1>
  memref.store %twice, %b[] : memref<i1>
  %x = qref.measure x %q1 : !qcc.qubit_ref -> i1
  memref.store %x, %b[] : memref<i1>
  qref.reset z %q0 : !qcc.qubit_ref
  qref.reset x %q1 : !qcc.qubit_ref
  return
}

// -----

// Bits: the views and casts of `--convert-oq3-to-qref`, reading a `bit`, and constants.

// CHECK-LABEL: OPENQASM 3.1;
// CHECK-NEXT:  bit c0;
// CHECK-NEXT:  bit[3] c1;
// CHECK-NEXT:  c1[2] = c0;
// CHECK-NEXT:  c1[1 + 1] = 1;
// CHECK-NEXT:  c0 = 0;
// CHECK-EMPTY:
func.func @main() attributes {qcc.entry_point} {
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

// -----

// Arithmetic on integers and floats. Negative constants are negated literals.

// CHECK-LABEL: OPENQASM 3.1;
// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit[8] q0;
// CHECK-NEXT:  rx((1.5 - 2.0E-20) * -1.5 / (3 - 1 + -4 * 2 / 2)) q0[(3 - 1 + -4 * 2 / 2) * 2];
// CHECK-EMPTY:
func.func @main() attributes {qcc.entry_point} {
  %r = qcc.alloc : tensor<8x!qcc.qubit_ref>
  %c3 = arith.constant 3 : i64
  %c1 = arith.constant 1 : i64
  %cm4 = arith.constant -4 : i64
  %c2 = arith.constant 2 : i64
  %diff = arith.subi %c3, %c1 : i64
  %prod = arith.muli %cm4, %c2 : i64
  %quot = arith.divsi %prod, %c2 : i64
  %sum = arith.addi %diff, %quot : i64
  %index = arith.index_cast %sum : i64 to index
  %c2_index = arith.constant 2 : index
  %position = arith.muli %index, %c2_index : index
  %q = tensor.extract %r[%position] : tensor<8x!qcc.qubit_ref>
  %a = arith.constant 1.5 : f64
  %b = arith.constant 2.0e-20 : f64
  %fdiff = arith.subf %a, %b : f64
  %neg = arith.negf %a : f64
  %fprod = arith.mulf %fdiff, %neg : f64
  %fsum = arith.sitofp %sum : i64 to f64
  %fquot = arith.divf %fprod, %fsum : f64
  qref.single rx(%fquot) %q : f64, !qcc.qubit_ref
  return
}

// -----

// The target's `float` has its word size (32 bits in this case), so `f32` values become `float`s.

// CHECK-LABEL: OPENQASM 3.1;
// CHECK-NEXT:  include "stdgates.inc";
// CHECK-NEXT:  qubit q0;
// CHECK-NEXT:  rx(0.1 * 2) q0;
// CHECK-EMPTY:
module attributes {dlti.dl_spec = #dlti.dl_spec<index = 32>} {
  func.func @main() attributes {qcc.entry_point} {
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
