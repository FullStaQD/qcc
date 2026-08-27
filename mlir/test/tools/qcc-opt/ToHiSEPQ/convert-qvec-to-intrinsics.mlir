// RUN: qcc-opt %s -convert-qvec-to-intrinsics --split-input-file | FileCheck %s

// FIXME: Is there a shortcut to declare many statics qubits more easily? (likely not)

// FIXME: why is the file split?

// The two qubits have to occupy the two front entries of an otherwise poison
// `vector<[N]xi8>`. Poison means "we don't care".

// CHECK-LABEL: func.func @single_gates
module attributes {qvec.target = #dlti.map<"min_vlen" = 128 : ui32>} {
  func.func @single_gates() {
      %q0 = qco.static 0 : !qco.qubit
      %q1 = qco.static 1 : !qco.qubit
      %q2 = qco.static 2 : !qco.qubit
      %qs = vector.from_elements %q0, %q1, %q2 : vector<3x!qco.qubit>

      %h = qvec.single h %qs : vector<3x!qco.qubit>
      %x = qvec.single x %h : vector<3x!qco.qubit>

      func.return
  }
}

// CHECK-NOT:     qco.static
// CHECK-NOT:     vector.from_elements
// CHECK-DAG:     %[[VL:.*]] = llvm.mlir.constant(3 : i32) : i32
// CHECK-DAG:     %[[ZERO:.*]] = llvm.mlir.constant(0 : i32) : i32

// Create and insert a vector of three qubits at the front of a scalable vector `vector<[2]xi8>`
// which can hold up to 4 elements at vscale = 2 = VLEN / 64.
// Elements 3 and above contain poison values, meaning that using those in a computation is
// undefined behavior - right for us.
// CHECK-DAG:     %[[IDX:.*]] = llvm.mlir.constant(dense<[0, 1, 2]> : vector<3xi8>) : vector<3xi8>
// CHECK-DAG:     %[[POISON:.*]] = llvm.mlir.poison : vector<[2]xi8>
// CHECK:         %[[V0:.*]] = llvm.intr.vector.insert %[[IDX]], %[[POISON]][0] : vector<3xi8> into vector<[2]xi8>

// The `x` names the same three qubits as the `h`, because it consumes the vector the `h` returned.
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"(%[[V0]], %[[ZERO]], %[[ZERO]], %[[VL]])
// CHECK:         %[[V1:.*]] = llvm.intr.vector.insert %[[IDX]], %[[POISON]][0] : vector<3xi8> into vector<[2]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.x"(%[[V1]], %[[ZERO]], %[[ZERO]], %[[VL]])

// -----

// The encoding is `qv.cx vs1(tgt), vs2(ctrl)`, i.e. the other way round from how `qvec.pair`
// reads, so the lowering swaps the two operands.

// CHECK-LABEL: func.func @pair_gates
module attributes {qvec.target = #dlti.map<"min_vlen" = 128 : ui32>} {
  func.func @pair_gates() {
      %c0 = qco.static 0 : !qco.qubit
      %c1 = qco.static 1 : !qco.qubit
      %ctrls = vector.from_elements %c0, %c1 : vector<2x!qco.qubit>

      %t0 = qco.static 2 : !qco.qubit
      %t1 = qco.static 3 : !qco.qubit
      %tgts = vector.from_elements %t0, %t1 : vector<2x!qco.qubit>

      %ctrls_out, %tgts_out = qvec.pair cx %ctrls, %tgts : vector<2x!qco.qubit>

      func.return
  }
}

// CHECK-DAG:     %[[CTRL_IDX:.*]] = llvm.mlir.constant(dense<[0, 1]> : vector<2xi8>) : vector<2xi8>
// CHECK-DAG:     %[[TGT_IDX:.*]] = llvm.mlir.constant(dense<[2, 3]> : vector<2xi8>) : vector<2xi8>
// CHECK-DAG:     %[[CTRLS:.*]] = llvm.intr.vector.insert %[[CTRL_IDX]], %{{.*}}[0]
// CHECK-DAG:     %[[TGTS:.*]] = llvm.intr.vector.insert %[[TGT_IDX]], %{{.*}}[0]
// FIXME: really swapped? This must be fixed - otherwise hell on earth!
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.cx"(%[[TGTS]], %[[CTRLS]], %{{.*}}, %{{.*}})


// -----

// TODO: Currently the QISA does not provide the measurement result to us. Here we replace it by poison. Needs fixing
// upstream ASAP.

// CHECK-LABEL: func.func @measurement
module attributes {qvec.target = #dlti.map<"min_vlen" = 128 : ui32>} {
  func.func @measurement() -> vector<2xi1> {
      %q0 = qco.static 0 : !qco.qubit
      %q1 = qco.static 1 : !qco.qubit
      %qs = vector.from_elements %q0, %q1 : vector<2x!qco.qubit>

      %qs_out, %result = qvec.mz %qs : vector<2x!qco.qubit> -> vector<2xi1>

      func.return %result : vector<2xi1>
  }
}

// CHECK-NOT:     qvec.mz
// CHECK:         %[[RES:.*]] = llvm.mlir.poison : vector<2xi1>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.mz"(%{{.*}}, %{{.*}}, %{{.*}}, %{{.*}})
// CHECK:         return %[[RES]] : vector<2xi1>

// -----

// CHECK-LABEL: func.func @threaded
module attributes {qvec.target = #dlti.map<"min_vlen" = 128 : ui32>} {
  func.func @threaded() -> vector<2xi1> {
      %c0 = qco.static 0 : !qco.qubit
      %c1 = qco.static 1 : !qco.qubit
      %ctrls = vector.from_elements %c0, %c1 : vector<2x!qco.qubit>

      %t0 = qco.static 2 : !qco.qubit
      %t1 = qco.static 3 : !qco.qubit
      %tgts = vector.from_elements %t0, %t1 : vector<2x!qco.qubit>

      %h = qvec.single h %ctrls : vector<2x!qco.qubit>
      %ctrls_out, %tgts_out = qvec.pair cx %h, %tgts : vector<2x!qco.qubit>
      %mq, %bits = qvec.mz %ctrls_out : vector<2x!qco.qubit> -> vector<2xi1>
      %x = qvec.single x %mq : vector<2x!qco.qubit>

      func.return %bits : vector<2xi1>
  }
}

// CHECK-NOT:     qvec.
// CHECK-DAG:     %[[CTRL_IDX:.*]] = llvm.mlir.constant(dense<[0, 1]> : vector<2xi8>) : vector<2xi8>
// CHECK-DAG:     %[[TGT_IDX:.*]] = llvm.mlir.constant(dense<[2, 3]> : vector<2xi8>) : vector<2xi8>

// Every instruction addresses the controls, except the `cx`, which addresses both.
// CHECK:         llvm.intr.vector.insert %[[CTRL_IDX]]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"
// CHECK-DAG:     %[[CX_TGTS:.*]] = llvm.intr.vector.insert %[[TGT_IDX]]
// CHECK-DAG:     %[[CX_CTRLS:.*]] = llvm.intr.vector.insert %[[CTRL_IDX]]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.cx"(%[[CX_TGTS]], %[[CX_CTRLS]], %{{.*}}, %{{.*}})
// CHECK:         llvm.intr.vector.insert %[[CTRL_IDX]]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.mz"
// CHECK:         llvm.intr.vector.insert %[[CTRL_IDX]]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.x"

// -----

// CHECK-LABEL: func.func @sparse_qubit_indices
module attributes {qvec.target = #dlti.map<"min_vlen" = 128 : ui32>} {
  func.func @sparse_qubit_indices() {
      %q0 = qco.static 7 : !qco.qubit
      %q1 = qco.static 3 : !qco.qubit
      %q2 = qco.static 255 : !qco.qubit
      %qs = vector.from_elements %q0, %q1, %q2 : vector<3x!qco.qubit>

      %h = qvec.single h %qs : vector<3x!qco.qubit>

      func.return
  }
}

// FIXME: are we fine with 255 = -1?
// CHECK:         llvm.mlir.constant(dense<[7, 3, -1]> : vector<3xi8>) : vector<3xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"

// -----

// At VLEN 64 eight qubits are exactly what LMUL 1 (`vector<[8]xi8>`) holds.

// CHECK-LABEL: func.func @lmul1
module attributes {qvec.target = #dlti.map<"min_vlen" = 64 : ui32>} {
  func.func @lmul1() {
      %q0 = qco.static 0 : !qco.qubit
      %q1 = qco.static 1 : !qco.qubit
      %q2 = qco.static 2 : !qco.qubit
      %q3 = qco.static 3 : !qco.qubit
      %q4 = qco.static 4 : !qco.qubit
      %q5 = qco.static 5 : !qco.qubit
      %q6 = qco.static 6 : !qco.qubit
      %q7 = qco.static 7 : !qco.qubit
      %qs = vector.from_elements %q0, %q1, %q2, %q3, %q4, %q5, %q6, %q7 : vector<8x!qco.qubit>
      %h = qvec.single h %qs : vector<8x!qco.qubit>
      func.return
  }
}

// CHECK:         llvm.mlir.poison : vector<[8]xi8>
// CHECK:         llvm.intr.vector.insert %{{.*}}[0] : vector<8xi8> into vector<[8]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}, %{{.*}}, %{{.*}}, %{{.*}})

// -----

// Going from 8 to 9 qubits steps up from LMUL 1 to LMUL 2 (`vector<[16]xi8>`) -- at VLEN 64.

// CHECK-LABEL: func.func @lmul2
module attributes {qvec.target = #dlti.map<"min_vlen" = 64 : ui32>} {
  func.func @lmul2() {
      %q0 = qco.static 0 : !qco.qubit
      %q1 = qco.static 1 : !qco.qubit
      %q2 = qco.static 2 : !qco.qubit
      %q3 = qco.static 3 : !qco.qubit
      %q4 = qco.static 4 : !qco.qubit
      %q5 = qco.static 5 : !qco.qubit
      %q6 = qco.static 6 : !qco.qubit
      %q7 = qco.static 7 : !qco.qubit
      %q8 = qco.static 8 : !qco.qubit
      %qs = vector.from_elements %q0, %q1, %q2, %q3, %q4, %q5, %q6, %q7, %q8 : vector<9x!qco.qubit>
      %h = qvec.single h %qs : vector<9x!qco.qubit>
      func.return
  }
}

// CHECK-DAG:     %[[VL:.*]] = llvm.mlir.constant(9 : i32) : i32
// CHECK:         llvm.mlir.poison : vector<[16]xi8>
// CHECK:         llvm.intr.vector.insert %{{.*}}[0] : vector<9xi8> into vector<[16]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}, %{{.*}}, %{{.*}}, %[[VL]])

// -----

// CHECK-LABEL: func.func @lmul_follows_vlen
module attributes {qvec.target = #dlti.map<"min_vlen" = 128 : ui32>} {
  func.func @lmul_follows_vlen() {
      %q0 = qco.static 0 : !qco.qubit
      %q1 = qco.static 1 : !qco.qubit
      %q2 = qco.static 2 : !qco.qubit
      %q3 = qco.static 3 : !qco.qubit
      %q4 = qco.static 4 : !qco.qubit
      %q5 = qco.static 5 : !qco.qubit
      %q6 = qco.static 6 : !qco.qubit
      %q7 = qco.static 7 : !qco.qubit
      %qs = vector.from_elements %q0, %q1, %q2, %q3, %q4, %q5, %q6, %q7 : vector<8x!qco.qubit>
      %h = qvec.single h %qs : vector<8x!qco.qubit>
      func.return
  }
}

// CHECK-DAG:     %[[VL:.*]] = llvm.mlir.constant(8 : i32) : i32
// CHECK:         llvm.mlir.poison : vector<[4]xi8>
// CHECK:         llvm.intr.vector.insert %{{.*}}[0] : vector<8xi8> into vector<[4]xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}, %{{.*}}, %{{.*}}, %[[VL]])
