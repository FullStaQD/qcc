// RUN: qcc --target=hisepq -mattr=+zvl128b --compile-to=mlir %s | FileCheck %s
// RUN: qcc --target=hisepq -mattr=+zvl128b --compile-to=native %s | FileCheck %s --check-prefix=CHECK-ASM

// An end-to-end test for what routing HiSEP-Q through `qvec` buys: eight Bell pairs, written out one gate at a time
// the way a frontend emits them, arrive as three QV instructions.

func.func @main() -> i1 attributes { qcc.entry_point } {
    %q0 = qc.static 0 : !qc.qubit
    %q1 = qc.static 1 : !qc.qubit
    %q2 = qc.static 2 : !qc.qubit
    %q3 = qc.static 3 : !qc.qubit
    %q4 = qc.static 4 : !qc.qubit
    %q5 = qc.static 5 : !qc.qubit
    %q6 = qc.static 6 : !qc.qubit
    %q7 = qc.static 7 : !qc.qubit
    %q8 = qc.static 8 : !qc.qubit
    %q9 = qc.static 9 : !qc.qubit
    %q10 = qc.static 10 : !qc.qubit
    %q11 = qc.static 11 : !qc.qubit
    %q12 = qc.static 12 : !qc.qubit
    %q13 = qc.static 13 : !qc.qubit
    %q14 = qc.static 14 : !qc.qubit
    %q15 = qc.static 15 : !qc.qubit

    qc.h %q0 : !qc.qubit
    qc.h %q1 : !qc.qubit
    qc.h %q2 : !qc.qubit
    qc.h %q3 : !qc.qubit
    qc.h %q4 : !qc.qubit
    qc.h %q5 : !qc.qubit
    qc.h %q6 : !qc.qubit
    qc.h %q7 : !qc.qubit

    qc.ctrl(%q0) targets(%t0 = %q8) { qc.x %t0 : !qc.qubit
                                     qc.yield } : {!qc.qubit}, {!qc.qubit}
    qc.ctrl(%q1) targets(%t1 = %q9) { qc.x %t1 : !qc.qubit
                                     qc.yield } : {!qc.qubit}, {!qc.qubit}
    qc.ctrl(%q2) targets(%t2 = %q10) { qc.x %t2 : !qc.qubit
                                     qc.yield } : {!qc.qubit}, {!qc.qubit}
    qc.ctrl(%q3) targets(%t3 = %q11) { qc.x %t3 : !qc.qubit
                                     qc.yield } : {!qc.qubit}, {!qc.qubit}
    qc.ctrl(%q4) targets(%t4 = %q12) { qc.x %t4 : !qc.qubit
                                     qc.yield } : {!qc.qubit}, {!qc.qubit}
    qc.ctrl(%q5) targets(%t5 = %q13) { qc.x %t5 : !qc.qubit
                                     qc.yield } : {!qc.qubit}, {!qc.qubit}
    qc.ctrl(%q6) targets(%t6 = %q14) { qc.x %t6 : !qc.qubit
                                     qc.yield } : {!qc.qubit}, {!qc.qubit}
    qc.ctrl(%q7) targets(%t7 = %q15) { qc.x %t7 : !qc.qubit
                                     qc.yield } : {!qc.qubit}, {!qc.qubit}

    %r0 = qc.measure %q0 : !qc.qubit -> i1
    %r1 = qc.measure %q1 : !qc.qubit -> i1
    %r2 = qc.measure %q2 : !qc.qubit -> i1
    %r3 = qc.measure %q3 : !qc.qubit -> i1
    %r4 = qc.measure %q4 : !qc.qubit -> i1
    %r5 = qc.measure %q5 : !qc.qubit -> i1
    %r6 = qc.measure %q6 : !qc.qubit -> i1
    %r7 = qc.measure %q7 : !qc.qubit -> i1
    %r8 = qc.measure %q8 : !qc.qubit -> i1
    %r9 = qc.measure %q9 : !qc.qubit -> i1
    %r10 = qc.measure %q10 : !qc.qubit -> i1
    %r11 = qc.measure %q11 : !qc.qubit -> i1
    %r12 = qc.measure %q12 : !qc.qubit -> i1
    %r13 = qc.measure %q13 : !qc.qubit -> i1
    %r14 = qc.measure %q14 : !qc.qubit -> i1
    %r15 = qc.measure %q15 : !qc.qubit -> i1
    // Both halves of a Bell pair collapse to the same value, so -- errors aside -- the eight control bits and the
    // eight target bits have to agree. One comparison and one reduction say exactly that. Returning the verdict is
    // what keeps the whole chain alive: dead, `qvec-merge` folds it away.
    %ctrl_bits = vector.from_elements %r0, %r1, %r2, %r3, %r4, %r5, %r6, %r7 : vector<8xi1>
    %tgt_bits = vector.from_elements %r8, %r9, %r10, %r11, %r12, %r13, %r14, %r15 : vector<8xi1>
    %agree = arith.cmpi eq, %ctrl_bits, %tgt_bits : vector<8xi1>
    %ok = vector.reduction <and>, %agree : vector<8xi1> into i1

    func.return %ok : i1
}

// Nothing of the source dialects survives.
// CHECK-NOT:     qvec.
// CHECK-NOT:     qc.
// CHECK-NOT:     qco.

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

// One `qv.cx` over all eight pairs, controls first as the encoding wants.
// CHECK:         %[[CX_TGTS:.*]] = llvm.intr.vector.insert %[[TGT_IDX]], %{{.*}}[0] : vector<8xi8> into vector<[4]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.cx"(%[[H]], %[[CX_TGTS]], %[[ZERO]], %[[VL8]])

// All sixteen measurements are independent, so the packer puts them in one instruction. Sixteen
// qubits no longer fit LMUL 1/2, so this one steps up to LMUL 1 -- `vector<[8]xi8>`.
// CHECK:         %[[MZ:.*]] = llvm.intr.vector.insert %[[ALL_IDX]], %{{.*}}[0] : vector<16xi8> into vector<[8]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.mz"(%[[MZ]], %[[ZERO]], %[[ZERO]], %[[VL16]])
// CHECK-NOT:     llvm.call_intrinsic

// And the same thing once more after instruction selection:

// TODO: we have a few useless reconfigures in here. Will be fixed soon by a patch of our fork.
// CHECK-ASM-LABEL: main:

// The control indices <0, 1, ..., 7>, plus the target indices <8, 9, ..., 15>:
// CHECK-ASM:       vsetivli {{.*}}, 8, e8, mf2, ta, ma
// CHECK-ASM:       vid.v [[CTRLS:v[0-9]+]]
// CHECK-ASM:       vadd.vi [[TGTS:v[0-9]+]], [[CTRLS]], 8

// measurement indices <0, 1, ..., 15>:
// CHECK-ASM:       vsetivli {{.*}}, 16, e8, m1, ta, ma
// CHECK-ASM:       vid.v [[ALL:v[0-9]+]]

// Back to `vl` = 8 at LMUL 1/2 for the gates:
// CHECK-ASM:       vsetivli zero, 8, e8, mf2, ta, ma
// CHECK-ASM:       qv.h [[CTRLS]], zero, 0
// CHECK-ASM:       qv.cx [[CTRLS]], [[TGTS]], 0

// measurement on all 16 qubits simultaneously:
// CHECK-ASM:       vsetivli zero, 16, e8, m1, ta, ma
// CHECK-ASM:       qv.mz [[ALL]], zero, 0
// CHECK-ASM:       ret
