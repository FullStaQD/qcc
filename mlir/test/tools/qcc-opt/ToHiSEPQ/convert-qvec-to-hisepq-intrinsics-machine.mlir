// DEFINE: %{vlen} = 128
// DEFINE: %{qew} = 8
// DEFINE: %{prefix} = CHECK-VLEN128

// DEFINE: %{run} = qcc-opt %s --split-input-file \
// DEFINE:     -convert-qvec-to-hisepq-intrinsics="min-vlen=%{vlen} qubit-element-width=%{qew}" \
// DEFINE:   | FileCheck %s --check-prefix=%{prefix}

// RUN: %{run}

// REDEFINE: %{vlen} = 64
// REDEFINE: %{qew} = 8
// REDEFINE: %{prefix} = CHECK-VLEN64
// RUN: %{run}

// REDEFINE: %{vlen} = 128
// REDEFINE: %{qew} = 16
// REDEFINE: %{prefix} = CHECK-QEW16
// RUN: %{run}

// How the machine parameters pick the register group. The same body is lowered under three
// machines, so the two derivations are visible side by side:
//
//   - a wider VLEN raises `vscale`, so the same qubits fit in a narrower LMUL, and
//   - a wider QEW makes each index take more of the register, so they need a wider one.
//
// The type is `vector<[N]xi{QEW}>` with `N = LMUL * 64 / QEW`, holding `vscale * N` elements.

// CHECK-VLEN128-LABEL: func.func @eight_qubits
// CHECK-VLEN64-LABEL:  func.func @eight_qubits
// CHECK-QEW16-LABEL:   func.func @eight_qubits
func.func @eight_qubits() {
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

// CHECK-VLEN128:       llvm.mlir.poison : vector<[4]xi8>
// CHECK-VLEN128:       llvm.intr.vector.insert %{{.*}}[0] : vector<8xi8> into vector<[4]xi8>
// CHECK-VLEN128:       llvm.call_intrinsic "llvm.riscv.qv.h"

// CHECK-VLEN64:        llvm.mlir.poison : vector<[8]xi8>
// CHECK-VLEN64:        llvm.intr.vector.insert %{{.*}}[0] : vector<8xi8> into vector<[8]xi8>
// CHECK-VLEN64:        llvm.call_intrinsic "llvm.riscv.qv.h"

// The indices are i16 now, so both the fixed constant and the register group widen.
// CHECK-QEW16:         llvm.mlir.constant(dense<[0, 1, 2, 3, 4, 5, 6, 7]> : vector<8xi16>) : vector<8xi16>
// CHECK-QEW16:         llvm.mlir.poison : vector<[4]xi16>
// CHECK-QEW16:         llvm.intr.vector.insert %{{.*}}[0] : vector<8xi16> into vector<[4]xi16>
// CHECK-QEW16:         llvm.call_intrinsic "llvm.riscv.qv.h"

// -----

// CHECK-VLEN128-LABEL: func.func @nine_qubits
// CHECK-VLEN64-LABEL:  func.func @nine_qubits
// CHECK-QEW16-LABEL:   func.func @nine_qubits
func.func @nine_qubits() {
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

// CHECK-VLEN128-DAG:   %[[VL128:.*]] = llvm.mlir.constant(9 : i32) : i32
// CHECK-VLEN128:       llvm.mlir.poison : vector<[8]xi8>
// CHECK-VLEN128:       llvm.intr.vector.insert %{{.*}}[0] : vector<9xi8> into vector<[8]xi8>
// CHECK-VLEN128:       llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}, %{{.*}}, %{{.*}}, %[[VL128]])

// CHECK-VLEN64-DAG:    %[[VL64:.*]] = llvm.mlir.constant(9 : i32) : i32
// CHECK-VLEN64:        llvm.mlir.poison : vector<[16]xi8>
// CHECK-VLEN64:        llvm.intr.vector.insert %{{.*}}[0] : vector<9xi8> into vector<[16]xi8>
// CHECK-VLEN64:        llvm.call_intrinsic "llvm.riscv.qv.h"(%{{.*}}, %{{.*}}, %{{.*}}, %[[VL64]])

// CHECK-QEW16:         llvm.mlir.poison : vector<[8]xi16>
// CHECK-QEW16:         llvm.intr.vector.insert %{{.*}}[0] : vector<9xi16> into vector<[8]xi16>
// CHECK-QEW16:         llvm.call_intrinsic "llvm.riscv.qv.h"
