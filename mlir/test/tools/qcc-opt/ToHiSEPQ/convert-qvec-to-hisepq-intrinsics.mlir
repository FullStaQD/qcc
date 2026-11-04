// RUN: qcc-opt %s -convert-qvec-to-hisepq-intrinsics="min-vlen=128 num-qubit-control-lines=256" --split-input-file \
// RUN:   | FileCheck %s

// The three qubits have to occupy the three front entries of an otherwise poison
// `vector<[N]xi8>`. Poison means "we don't care".

// CHECK-LABEL: func.func @single_gates
func.func @single_gates() {
    %q0, %q1, %q2 = qcc.static [0, 1, 2] : !qcc.qubit
    %qs = vector.from_elements %q0, %q1, %q2 : vector<3x!qcc.qubit>

    %h = qvec.single h %qs : vector<3x!qcc.qubit>
    %x = qvec.single x %h : vector<3x!qcc.qubit>

    func.return
}

// CHECK-NOT:     qcc.static
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

// The encoding is `qv.cx vs1(ctrl), vs2(tgt)`, the same order `qvec.pair` reads, so the two
// operands pass through unswapped.

// CHECK-LABEL: func.func @pair_gates
func.func @pair_gates() {
    %c0, %c1, %t0, %t1 = qcc.static [0, 1, 2, 3] : !qcc.qubit
    %ctrls = vector.from_elements %c0, %c1 : vector<2x!qcc.qubit>

    %tgts = vector.from_elements %t0, %t1 : vector<2x!qcc.qubit>

    %ctrls_out, %tgts_out = qvec.pair cx %ctrls, %tgts : vector<2x!qcc.qubit>

    func.return
}

// CHECK-DAG:     %[[CTRL_IDX:.*]] = llvm.mlir.constant(dense<[0, 1]> : vector<2xi8>) : vector<2xi8>
// CHECK-DAG:     %[[TGT_IDX:.*]] = llvm.mlir.constant(dense<[2, 3]> : vector<2xi8>) : vector<2xi8>
// CHECK-DAG:     %[[CTRLS:.*]] = llvm.intr.vector.insert %[[CTRL_IDX]], %{{.*}}[0]
// CHECK-DAG:     %[[TGTS:.*]] = llvm.intr.vector.insert %[[TGT_IDX]], %{{.*}}[0]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.cx"(%[[CTRLS]], %[[TGTS]], %{{.*}}, %{{.*}})


// -----

// TODO: Currently the QISA does not provide the measurement result to us. Here we replace it by poison. Needs fixing
// upstream ASAP.

// CHECK-LABEL: func.func @measurement
func.func @measurement() -> vector<2xi1> {
    %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
    %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>

    %qs_out, %result = qvec.measure z %qs : vector<2x!qcc.qubit> -> vector<2xi1>

    func.return %result : vector<2xi1>
}

// CHECK-NOT:     qvec.measure
// CHECK:         %[[RES:.*]] = llvm.mlir.poison : vector<2xi1>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.mz"(%{{.*}}, %{{.*}}, %{{.*}}, %{{.*}})
// CHECK:         return %[[RES]] : vector<2xi1>

// -----

// There is no reset instruction: the qubits are measured, and each one is flipped on its own if it measured |1⟩.
// The flips branch on poison as long as the measurement results are lost.

// CHECK-LABEL: func.func @reset
func.func @reset() {
    %q0, %q1 = qcc.static [0, 1] : !qcc.qubit
    %qs = vector.from_elements %q0, %q1 : vector<2x!qcc.qubit>

    %r = qvec.reset z %qs : vector<2x!qcc.qubit>
    %h = qvec.single h %r : vector<2x!qcc.qubit>

    func.return
}

// CHECK-NOT:     qvec.
// CHECK-DAG:     %[[IDX:.*]] = llvm.mlir.constant(dense<[0, 1]> : vector<2xi8>) : vector<2xi8>
// CHECK-DAG:     %[[IDX0:.*]] = llvm.mlir.constant(dense<0> : vector<1xi8>) : vector<1xi8>
// CHECK-DAG:     %[[IDX1:.*]] = llvm.mlir.constant(dense<1> : vector<1xi8>) : vector<1xi8>
// CHECK-DAG:     %[[BITS:.*]] = llvm.mlir.poison : vector<2xi1>
// CHECK:         %[[V:.*]] = llvm.intr.vector.insert %[[IDX]]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.mz"(%[[V]], %{{.*}}, %{{.*}}, %{{.*}})
// CHECK:         %[[BIT0:.*]] = vector.extract %[[BITS]][0] : i1 from vector<2xi1>
// CHECK:         scf.if %[[BIT0]] {
// CHECK:           %[[V0:.*]] = llvm.intr.vector.insert %[[IDX0]]
// CHECK:           llvm.call_intrinsic "llvm.riscv.qv.x"(%[[V0]], %{{.*}}, %{{.*}}, %{{.*}})
// CHECK:         }
// CHECK:         %[[BIT1:.*]] = vector.extract %[[BITS]][1] : i1 from vector<2xi1>
// CHECK:         scf.if %[[BIT1]] {
// CHECK:           %[[V1:.*]] = llvm.intr.vector.insert %[[IDX1]]
// CHECK:           llvm.call_intrinsic "llvm.riscv.qv.x"(%[[V1]], %{{.*}}, %{{.*}}, %{{.*}})
// CHECK:         }
// The qubits after the reset are the ones before.
// CHECK:         %[[W:.*]] = llvm.intr.vector.insert %[[IDX]]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"(%[[W]], %{{.*}}, %{{.*}}, %{{.*}})

// -----

// CHECK-LABEL: func.func @threaded
func.func @threaded() -> vector<2xi1> {
    %c0, %c1, %t0, %t1 = qcc.static [0, 1, 2, 3] : !qcc.qubit
    %ctrls = vector.from_elements %c0, %c1 : vector<2x!qcc.qubit>

    %tgts = vector.from_elements %t0, %t1 : vector<2x!qcc.qubit>

    %h = qvec.single h %ctrls : vector<2x!qcc.qubit>
    %ctrls_out, %tgts_out = qvec.pair cx %h, %tgts : vector<2x!qcc.qubit>
    %mq, %bits = qvec.measure z %ctrls_out : vector<2x!qcc.qubit> -> vector<2xi1>
    %x = qvec.single x %mq : vector<2x!qcc.qubit>

    func.return %bits : vector<2xi1>
}

// CHECK-NOT:     qvec.
// CHECK-DAG:     %[[CTRL_IDX:.*]] = llvm.mlir.constant(dense<[0, 1]> : vector<2xi8>) : vector<2xi8>
// CHECK-DAG:     %[[TGT_IDX:.*]] = llvm.mlir.constant(dense<[2, 3]> : vector<2xi8>) : vector<2xi8>

// Every instruction addresses the controls, except the `cx`, which addresses both.
// CHECK:         llvm.intr.vector.insert %[[CTRL_IDX]]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"
// CHECK-DAG:     %[[CX_TGTS:.*]] = llvm.intr.vector.insert %[[TGT_IDX]]
// CHECK-DAG:     %[[CX_CTRLS:.*]] = llvm.intr.vector.insert %[[CTRL_IDX]]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.cx"(%[[CX_CTRLS]], %[[CX_TGTS]], %{{.*}}, %{{.*}})
// CHECK:         llvm.intr.vector.insert %[[CTRL_IDX]]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.mz"
// CHECK:         llvm.intr.vector.insert %[[CTRL_IDX]]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.x"

// -----

// CHECK-LABEL: func.func @sparse_qubit_indices
func.func @sparse_qubit_indices() {
    %q1, %q0, %q2 = qcc.static [3, 7, 255] : !qcc.qubit
    %qs = vector.from_elements %q0, %q1, %q2 : vector<3x!qcc.qubit>

    %h = qvec.single h %qs : vector<3x!qcc.qubit>

    func.return
}

// NOTE: 255 == -1; just a printing quirk.
// CHECK:         llvm.mlir.constant(dense<[7, 3, -1]> : vector<3xi8>) : vector<3xi8>
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"

// -----

// Output recording has no QISA counterpart, so it goes and the program reports nothing back.

// CHECK-LABEL: func.func @output_recording
func.func @output_recording(%value: i64, %buffer: memref<4xi1>) {
    %q0 = qcc.static [0] : !qcc.qubit
    %qs = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %mz, %bits = qvec.measure z %qs : vector<1x!qcc.qubit> -> vector<1xi1>

    aux.record_int %value : i64
    aux.record_memref %buffer : memref<4xi1>

    func.return
}

// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.mz"
// CHECK-NOT:     aux.record

// -----

// Qubits yielded by `scf.if` resolve to their static index.

// CHECK-LABEL: func.func @qubit_through_if
func.func @qubit_through_if(%cond: i1) {
    %q0 = qcc.static [5] : !qcc.qubit
    %v0 = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %x0 = scf.if %cond -> (vector<1x!qcc.qubit>) {
      %x = qvec.single x %v0 : vector<1x!qcc.qubit>
      scf.yield %x : vector<1x!qcc.qubit>
    } else {
      scf.yield %v0 : vector<1x!qcc.qubit>
    }
    %h = qvec.single h %x0 : vector<1x!qcc.qubit>
    func.return
}

// CHECK:         %[[IDX:.*]] = llvm.mlir.constant(dense<5> : vector<1xi8>)
// CHECK:         scf.if
// CHECK:           llvm.call_intrinsic "llvm.riscv.qv.x"
// CHECK:         }
// CHECK:         %[[Q:.*]] = llvm.intr.vector.insert %[[IDX]]
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"(%[[Q]]

// -----

// The instructions act on the qubits in place, so the qubits an `scf.if` yields are dropped. The `qcc.static` goes with
// them: it hands out each qubit only once and must not outlive the pass, as `convert-scf-to-cf` splits its function into
// blocks. Classical results stay.

// CHECK-LABEL: func.func @if_yields_qubits
func.func @if_yields_qubits(%cond: i1) -> i64 {
    %q0 = qcc.static [0] : !qcc.qubit
    %qs = vector.from_elements %q0 : vector<1x!qcc.qubit>
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %pick, %out = scf.if %cond -> (i64, vector<1x!qcc.qubit>) {
      %x = qvec.single x %qs : vector<1x!qcc.qubit>
      scf.yield %c1, %x : i64, vector<1x!qcc.qubit>
    } else {
      scf.yield %c2, %qs : i64, vector<1x!qcc.qubit>
    }
    %h = qvec.single h %out : vector<1x!qcc.qubit>
    func.return %pick : i64
}

// CHECK-NOT:     qcc.static
// CHECK-NOT:     vector.from_elements
// CHECK:         %[[PICK:.*]] = scf.if %{{.*}} -> (i64) {
// CHECK:           llvm.call_intrinsic "llvm.riscv.qv.x"
// CHECK:           scf.yield %{{.*}} : i64
// CHECK:         } else {
// CHECK:           scf.yield %{{.*}} : i64
// CHECK:         }
// CHECK:         llvm.call_intrinsic "llvm.riscv.qv.h"
// CHECK:         return %[[PICK]] : i64
