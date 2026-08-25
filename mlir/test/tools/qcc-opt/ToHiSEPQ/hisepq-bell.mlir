// REQUIRES: hisepq

// RUN: qcc-opt %s -convert-hisepq-to-intrinsics -convert-vector-to-llvm \
// RUN:   -convert-arith-to-llvm -convert-func-to-llvm -o %t.mlir
// RUN:   FileCheck %s < %t.mlir
// RUN: mlir-translate -mlir-to-llvmir %t.mlir | llc -mtriple=riscv32 -mattr=+experimental-xqv - -o - \
// RUN:   | FileCheck %s --check-prefix=CHECK-ASM

// FIXME: replace by a better integration test if possible.

// A pseudo-integration test: eight Bell pairs prepared and measured in parallel, four QV
// instructions in total. The point is that one `hisepq` op is one instruction over eight qubits,
// where the QIR path (see `convert-qir-to-hisepq-intrinsics.mlir`) would emit sixteen.

// `min_vlen` is our reference hardware's, and also the default. Spelled out because this test
// checks generated machine code, where the LMUL it selects is visible.

// CHECK-LABEL: llvm.func @bell_parallel
module attributes {hisepq.target = #dlti.map<"min_vlen" = 128 : ui32>} {
func.func @bell_parallel() -> i1 {
    %c0 = qc.static 0 : !qc.qubit
    %c1 = qc.static 1 : !qc.qubit
    %c2 = qc.static 2 : !qc.qubit
    %c3 = qc.static 3 : !qc.qubit
    %c4 = qc.static 4 : !qc.qubit
    %c5 = qc.static 5 : !qc.qubit
    %c6 = qc.static 6 : !qc.qubit
    %c7 = qc.static 7 : !qc.qubit
    %ctrls = vector.from_elements %c0, %c1, %c2, %c3, %c4, %c5, %c6, %c7 : vector<8x!qc.qubit>

    %t0 = qc.static 8 : !qc.qubit
    %t1 = qc.static 9 : !qc.qubit
    %t2 = qc.static 10 : !qc.qubit
    %t3 = qc.static 11 : !qc.qubit
    %t4 = qc.static 12 : !qc.qubit
    %t5 = qc.static 13 : !qc.qubit
    %t6 = qc.static 14 : !qc.qubit
    %t7 = qc.static 15 : !qc.qubit
    %tgts = vector.from_elements %t0, %t1, %t2, %t3, %t4, %t5, %t6, %t7 : vector<8x!qc.qubit>

    hisepq.single h %ctrls : vector<8x!qc.qubit>
    hisepq.pair cx %ctrls, %tgts : vector<8x!qc.qubit>

    %m_ctrls = hisepq.mz %ctrls : vector<8x!qc.qubit> -> vector<8xi1>
    %m_tgts = hisepq.mz %tgts : vector<8x!qc.qubit> -> vector<8xi1>

    // FIXME: Currently measurement results cannot be fetched by HiSEP-Q so this cannot be lowered faithfully:
    %eq = arith.cmpi eq, %m_ctrls, %m_tgts : vector<8xi1>
    %all = vector.reduction <and>, %eq : vector<8xi1> into i1

    func.return %all : i1
}
}

// Nothing of the source dialects survives.
// CHECK-NOT:     hisepq.
// CHECK-NOT:     qc.static
// CHECK-NOT:     vector.from_elements
// CHECK-NOT:     arith.cmpi

// CHECK-DAG:     %[[VL:.*]] = llvm.mlir.constant(8 : i32) : i32
// CHECK-DAG:     %[[ZERO:.*]] = llvm.mlir.constant(0 : i32) : i32
// CHECK-DAG:     %[[CTRL_IDX:.*]] = llvm.mlir.constant(dense<[0, 1, 2, 3, 4, 5, 6, 7]> : vector<8xi8>)
// CHECK-DAG:     %[[TGT_IDX:.*]] = llvm.mlir.constant(dense<[8, 9, 10, 11, 12, 13, 14, 15]> : vector<8xi8>)

// One `qv.h` over all eight controls. Eight qubits fit LMUL 1/2 at VLEN 128 -- `vector<[4]xi8>`
// holds `4 * 128/64 = 8` elements.
// CHECK:         %[[H:.*]] = llvm.intr.vector.insert %[[CTRL_IDX]], %{{.*}}[0] : vector<8xi8> into vector<[4]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"(%[[H]], %[[ZERO]], %[[ZERO]], %[[VL]])

// One `qv.cx` over all eight pairs, targets first as the encoding wants.
// CHECK-DAG:     %[[CX_CTRLS:.*]] = llvm.intr.vector.insert %[[CTRL_IDX]], %{{.*}}[0]
// CHECK-DAG:     %[[CX_TGTS:.*]] = llvm.intr.vector.insert %[[TGT_IDX]], %{{.*}}[0]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.cx"(%[[CX_TGTS]], %[[CX_CTRLS]], %[[ZERO]], %[[VL]])

// One `qv.mz` per register.
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.mz"
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.mz"

// CHECK:         llvm.intr.vector.reduce.and
// CHECK:         llvm.return

// And the same thing once more after instruction selection, which is what the QV operand
// encoding is actually pinned down by.

// CHECK-ASM-LABEL: bell_parallel:

// The control indices <0, 1, ..., 7> are cheap enough that the backend recognizes them as a
// vector index sequence. Nothing materializes for the poison destination of the
// `llvm.intr.vector.insert`: only the eight live elements get defined.
// CHECK-ASM:       vsetivli {{.*}}, 8, e8, mf2, ta, ma
// CHECK-ASM:       vid.v [[CTRLS:v[0-9]+]]

// `vl` = 8 at LMUL 1/2, matching the `vector<[4]xi8>` the pass picked for eight qubits. Note that
// this is the same `mf2` the index-sequence materialization above already used: when the pass
// assumed VLEN 64 it asked for `m1` here and the backend had to toggle LMUL between the two.
// CHECK-ASM:       li [[VL:a[0-9]+]], 8
// CHECK-ASM:       vsetvli zero, [[VL]], e8, mf2, ta, ma

// One instruction per `hisepq` op, each over all eight qubits.
// CHECK-ASM:       qv.h [[CTRLS]], zero, 0

// The target indices are the control indices plus eight, so they fold into a single `vadd.vi`.
// CHECK-ASM:       vadd.vi [[TGTS:v[0-9]+]], [[CTRLS]], 8

// Targets in `vs1`, controls in `vs2` -- the reverse of how `hisepq.pair` reads.
// CHECK-ASM:       qv.cx [[TGTS]], [[CTRLS]], 0

// CHECK-ASM:       qv.mz [[CTRLS]], zero, 0
// CHECK-ASM:       qv.mz [[TGTS]], zero, 0
// CHECK-ASM:       ret
