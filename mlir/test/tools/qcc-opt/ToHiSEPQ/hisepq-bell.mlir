// REQUIRES: hisepq

// RUN: qcc-opt %s -convert-qco-to-qvec -qvec-merge -convert-qvec-to-hisepq-intrinsics \
// RUN:   -convert-vector-to-llvm -convert-arith-to-llvm -convert-func-to-llvm -o %t.mlir
// RUN:   FileCheck %s < %t.mlir
// RUN: mlir-translate -mlir-to-llvmir %t.mlir | llc -mtriple=riscv32 -mattr=+experimental-xqv - -o - \
// RUN:   | FileCheck %s --check-prefix=CHECK-ASM

// FIXME: replace by a better integration test if possible.

// A pseudo-integration test for the whole HiSEP-Q path: eight Bell pairs, written out one gate at a
// time the way a frontend emits them, arriving as three QV instructions. The QIR path (see
// `convert-qir-to-hisepq-intrinsics.mlir`) would emit thirty-two.

// CHECK-LABEL: llvm.func @bell_parallel
module attributes {qvec.target = #dlti.map<"min_vlen" = 128 : ui32>} {
func.func @bell_parallel() {
    %q0 = qco.static 0 : !qco.qubit
    %q1 = qco.static 1 : !qco.qubit
    %q2 = qco.static 2 : !qco.qubit
    %q3 = qco.static 3 : !qco.qubit
    %q4 = qco.static 4 : !qco.qubit
    %q5 = qco.static 5 : !qco.qubit
    %q6 = qco.static 6 : !qco.qubit
    %q7 = qco.static 7 : !qco.qubit
    %q8 = qco.static 8 : !qco.qubit
    %q9 = qco.static 9 : !qco.qubit
    %q10 = qco.static 10 : !qco.qubit
    %q11 = qco.static 11 : !qco.qubit
    %q12 = qco.static 12 : !qco.qubit
    %q13 = qco.static 13 : !qco.qubit
    %q14 = qco.static 14 : !qco.qubit
    %q15 = qco.static 15 : !qco.qubit

    %h0 = qco.h %q0 : !qco.qubit -> !qco.qubit
    %h1 = qco.h %q1 : !qco.qubit -> !qco.qubit
    %h2 = qco.h %q2 : !qco.qubit -> !qco.qubit
    %h3 = qco.h %q3 : !qco.qubit -> !qco.qubit
    %h4 = qco.h %q4 : !qco.qubit -> !qco.qubit
    %h5 = qco.h %q5 : !qco.qubit -> !qco.qubit
    %h6 = qco.h %q6 : !qco.qubit -> !qco.qubit
    %h7 = qco.h %q7 : !qco.qubit -> !qco.qubit

    %c0, %t0 = qco.ctrl(%h0) targets(%a0 = %q8) {
      %x0 = qco.x %a0 : !qco.qubit -> !qco.qubit
      qco.yield %x0 : !qco.qubit
    } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})
    %c1, %t1 = qco.ctrl(%h1) targets(%a1 = %q9) {
      %x1 = qco.x %a1 : !qco.qubit -> !qco.qubit
      qco.yield %x1 : !qco.qubit
    } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})
    %c2, %t2 = qco.ctrl(%h2) targets(%a2 = %q10) {
      %x2 = qco.x %a2 : !qco.qubit -> !qco.qubit
      qco.yield %x2 : !qco.qubit
    } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})
    %c3, %t3 = qco.ctrl(%h3) targets(%a3 = %q11) {
      %x3 = qco.x %a3 : !qco.qubit -> !qco.qubit
      qco.yield %x3 : !qco.qubit
    } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})
    %c4, %t4 = qco.ctrl(%h4) targets(%a4 = %q12) {
      %x4 = qco.x %a4 : !qco.qubit -> !qco.qubit
      qco.yield %x4 : !qco.qubit
    } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})
    %c5, %t5 = qco.ctrl(%h5) targets(%a5 = %q13) {
      %x5 = qco.x %a5 : !qco.qubit -> !qco.qubit
      qco.yield %x5 : !qco.qubit
    } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})
    %c6, %t6 = qco.ctrl(%h6) targets(%a6 = %q14) {
      %x6 = qco.x %a6 : !qco.qubit -> !qco.qubit
      qco.yield %x6 : !qco.qubit
    } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})
    %c7, %t7 = qco.ctrl(%h7) targets(%a7 = %q15) {
      %x7 = qco.x %a7 : !qco.qubit -> !qco.qubit
      qco.yield %x7 : !qco.qubit
    } : ({!qco.qubit}, {!qco.qubit}) -> ({!qco.qubit}, {!qco.qubit})

    %mc0, %rc0 = qco.measure %c0 : !qco.qubit
    %mc1, %rc1 = qco.measure %c1 : !qco.qubit
    %mc2, %rc2 = qco.measure %c2 : !qco.qubit
    %mc3, %rc3 = qco.measure %c3 : !qco.qubit
    %mc4, %rc4 = qco.measure %c4 : !qco.qubit
    %mc5, %rc5 = qco.measure %c5 : !qco.qubit
    %mc6, %rc6 = qco.measure %c6 : !qco.qubit
    %mc7, %rc7 = qco.measure %c7 : !qco.qubit
    %mt0, %rt0 = qco.measure %t0 : !qco.qubit
    %mt1, %rt1 = qco.measure %t1 : !qco.qubit
    %mt2, %rt2 = qco.measure %t2 : !qco.qubit
    %mt3, %rt3 = qco.measure %t3 : !qco.qubit
    %mt4, %rt4 = qco.measure %t4 : !qco.qubit
    %mt5, %rt5 = qco.measure %t5 : !qco.qubit
    %mt6, %rt6 = qco.measure %t6 : !qco.qubit
    %mt7, %rt7 = qco.measure %t7 : !qco.qubit

    // FIXME: the test should go on with comparing the first group of 8 qubits with the second group of 8 qubits.
    // They should be equal (assuming no errors).

    func.return
}
}

// Nothing of the source dialects survives.
// CHECK-NOT:     qvec.
// CHECK-NOT:     qco.
// CHECK-NOT:     vector.from_elements

// CHECK-DAG:     %[[VL8:.*]] = llvm.mlir.constant(8 : i32) : i32
// CHECK-DAG:     %[[VL16:.*]] = llvm.mlir.constant(16 : i32) : i32
// CHECK-DAG:     %[[ZERO:.*]] = llvm.mlir.constant(0 : i32) : i32
// CHECK-DAG:     %[[CTRL_IDX:.*]] = llvm.mlir.constant(dense<[0, 1, 2, 3, 4, 5, 6, 7]> : vector<8xi8>)
// CHECK-DAG:     %[[TGT_IDX:.*]] = llvm.mlir.constant(dense<[8, 9, 10, 11, 12, 13, 14, 15]> : vector<8xi8>)
// CHECK-DAG:     %[[ALL_IDX:.*]] = llvm.mlir.constant(dense<[0, 1, 2, 3, 4, 5, 6, 7, 8,{{.*}}15]> : vector<16xi8>)

// One `qv.h` over all eight controls. Eight qubits fit LMUL 1/2 at VLEN 128 -- `vector<[4]xi8>`
// holds `4 * 128/64 = 8` elements.
// CHECK:         %[[H:.*]] = llvm.intr.vector.insert %[[CTRL_IDX]], %{{.*}}[0] : vector<8xi8> into vector<[4]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"(%[[H]], %[[ZERO]], %[[ZERO]], %[[VL8]])

// One `qv.cx` over all eight pairs, targets first as the encoding wants.
// CHECK-DAG:     %[[CX_CTRLS:.*]] = llvm.intr.vector.insert %[[CTRL_IDX]], %{{.*}}[0] : vector<8xi8> into vector<[4]xi8>
// CHECK-DAG:     %[[CX_TGTS:.*]] = llvm.intr.vector.insert %[[TGT_IDX]], %{{.*}}[0] : vector<8xi8> into vector<[4]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.cx"(%[[CX_TGTS]], %[[CX_CTRLS]], %[[ZERO]], %[[VL8]])

// All sixteen measurements are independent, so the packer puts them in one instruction. Sixteen
// qubits no longer fit LMUL 1/2, so this one steps up to LMUL 1 -- `vector<[8]xi8>`.
// CHECK:         %[[MZ:.*]] = llvm.intr.vector.insert %[[ALL_IDX]], %{{.*}}[0] : vector<16xi8> into vector<[8]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.mz"(%[[MZ]], %[[ZERO]], %[[ZERO]], %[[VL16]])
// CHECK-NOT:     llvm.call_intrinsic

// CHECK:         llvm.return

// And the same thing once more after instruction selection:

// CHECK-ASM-LABEL: bell_parallel:

// The control indices <0, 1, ..., 7>:
// CHECK-ASM:       vsetivli {{.*}}, 8, e8, mf2, ta, ma
// CHECK-ASM:       vid.v [[CTRLS:v[0-9]+]]

// `vl` = 8 at LMUL 1/2, matching the `vector<[4]xi8>` the pass picked for eight qubits.
// CHECK-ASM:       li [[VL8:a[0-9]+]], 8
// CHECK-ASM:       vsetvli zero, [[VL8]], e8, mf2, ta, ma

// FIXME: there are still multiple vsetvli reconfigurations although they configure all the same - why?
// CHECK-ASM:       qv.h [[CTRLS]], zero, 0
// CHECK-ASM:       vadd.vi [[TGTS:v[0-9]+]], [[CTRLS]], 8
// CHECK-ASM:       qv.cx [[TGTS]], [[CTRLS]], 0

// measurement on all 16 qubits simultaneously:
// CHECK-ASM:       vsetivli {{.*}}, 16, e8, m1, ta, ma
// CHECK-ASM:       vid.v [[ALL:v[0-9]+]]
// CHECK-ASM:       li [[VL16:a[0-9]+]], 16
// CHECK-ASM:       vsetvli zero, [[VL16]], e8, m1, ta, ma
// CHECK-ASM:       qv.mz [[ALL]], zero, 0
// CHECK-ASM:       ret
