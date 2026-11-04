// RUN: qcc-opt --split-input-file --convert-oq3-to-qref %s | FileCheck %s

// CHECK-LABEL: func.func @main() attributes {qcc.entry_point} {
// CHECK-NEXT:      %[[Q:.*]] = qcc.alloc : !qcc.qubit_ref
// CHECK-NEXT:      qref.single h %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:      return
// CHECK-NEXT:    }
// CHECK-NEXT:  }
// CHECK-NOT:   oq3.version
module attributes {oq3.version = #oq3.version<3, 0>} {
  func.func @main() attributes {qcc.entry_point} {
    oq3.include "stdgates.inc" id 0
    oq3.pragma "qcc.something"
    %0 = oq3.qubit_decl "q" : !qcc.qubit_ref
    oq3.gate_call @h [%0 : !qcc.qubit_ref] {oq3.annotations = [#oq3.annotation<"qcc.annotation", "">]}
    return
  }
}

// -----

// Allocation and static references. Indices count from the end if negative.

// CHECK-LABEL: func.func @main
// CHECK:         %[[Q:.*]] = qcc.alloc : tensor<3x!qcc.qubit_ref>
// CHECK:         %[[C0:.*]] = arith.constant 0 : index
// CHECK:         %[[Q0:.*]] = tensor.extract %[[Q]][%[[C0]]] : tensor<3x!qcc.qubit_ref>
// CHECK-NEXT:    qref.single x %[[Q0]] : !qcc.qubit_ref
// CHECK:         %[[C2:.*]] = arith.constant 2 : index
// CHECK-NEXT:    %[[Q2:.*]] = tensor.extract %[[Q]][%[[C2]]] : tensor<3x!qcc.qubit_ref>
// CHECK-NEXT:    qref.single y %[[Q2]] : !qcc.qubit_ref
// CHECK-NEXT:    %[[P:.*]] = qcc.static_ref [5] : !qcc.qubit_ref
// CHECK-NEXT:    qref.single z %[[P]] : !qcc.qubit_ref
// CHECK:         %[[EMPTY:.*]] = qcc.alloc : tensor<0x!qcc.qubit_ref>
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    oq3.include "stdgates.inc" id 0
    %0 = oq3.constant #oq3.int<3> : !oq3.int
    %1 = oq3.qubit_decl "q" [%0 : !oq3.int] : !oq3.qreg<3>
    %2 = oq3.constant #oq3.int<0> : !oq3.int
    %3 = oq3.qubit_index %1[%2] : !oq3.qreg<3>, !oq3.int
    oq3.gate_call @x [%3 : !qcc.qubit_ref]
    %4 = oq3.constant #oq3.int<1> : !oq3.int
    %5 = oq3.unary neg %4 : !oq3.int
    %6 = oq3.qubit_index %1[%5] : !oq3.qreg<3>, !oq3.int
    oq3.gate_call @y [%6 : !qcc.qubit_ref]
    %7 = oq3.physical_qubit 5 : !qcc.qubit_ref
    oq3.gate_call @z [%7 : !qcc.qubit_ref]
    %8 = oq3.constant #oq3.int<0> : !oq3.int
    %9 = oq3.qubit_decl "empty" [%8 : !oq3.int] : !oq3.qreg<0>
    return
  }
}

// -----

// Broadcast is realized as `scf.parallel`.

// CHECK-LABEL: func.func @main
// CHECK:         %[[R:.*]] = qcc.alloc : tensor<2x!qcc.qubit_ref>
// CHECK-NEXT:    %[[A:.*]] = qcc.alloc : !qcc.qubit_ref
// CHECK-NEXT:    %[[LB:.*]] = arith.constant 0 : index
// CHECK-NEXT:    %[[UB:.*]] = arith.constant 2 : index
// CHECK-NEXT:    %[[STEP:.*]] = arith.constant 1 : index
// CHECK-NEXT:    scf.parallel (%[[I:.*]]) = (%[[LB]]) to (%[[UB]]) step (%[[STEP]]) {
// CHECK-NEXT:      %[[RI:.*]] = tensor.extract %[[R]][%[[I]]] : tensor<2x!qcc.qubit_ref>
// CHECK-NEXT:      qref.pair cx %[[A]], %[[RI]] : !qcc.qubit_ref
// CHECK-NEXT:      scf.reduce
// CHECK-NEXT:    }
// CHECK:         scf.parallel (%[[J:.*]]) = (%{{.*}}) to (%{{.*}}) step (%{{.*}}) {
// CHECK-NEXT:      %[[RJ:.*]] = tensor.extract %[[R]][%[[J]]]
// CHECK-NEXT:      qref.reset z %[[RJ]] : !qcc.qubit_ref
// CHECK-NEXT:      scf.reduce
// CHECK-NEXT:    }
// CHECK-NEXT:    return
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    oq3.include "stdgates.inc" id 0
    %0 = oq3.constant #oq3.int<2> : !oq3.int
    %1 = oq3.qubit_decl "r" [%0 : !oq3.int] : !oq3.qreg<2>
    %2 = oq3.qubit_decl "a" : !qcc.qubit_ref
    oq3.gate_call @cx [%2, %1 : !qcc.qubit_ref, !oq3.qreg<2>]
    oq3.reset %1 : !oq3.qreg<2>
    oq3.barrier [%1, %2 : !oq3.qreg<2>, !qcc.qubit_ref]
    return
  }
}

// -----

// Bits are memrefs. A `bit` has a dynamic offset, so that a bit of a register has the same type.

// CHECK-LABEL: func.func @main
// CHECK:         %[[Q:.*]] = qcc.alloc : tensor<2x!qcc.qubit_ref>
// CHECK-NEXT:    %[[ALLOCA:.*]] = memref.alloca() : memref<i1>
// CHECK-NEXT:    %[[B:.*]] = memref.cast %[[ALLOCA]] : memref<i1> to memref<i1, strided<[], offset: ?>>
// CHECK:         %[[C:.*]] = memref.alloca() : memref<2xi1>
// CHECK:         %[[Q0:.*]] = tensor.extract %[[Q]]
// CHECK-NEXT:    %[[M0:.*]] = qref.measure z %[[Q0]] : !qcc.qubit_ref -> i1
// CHECK-NEXT:    memref.store %[[M0]], %[[B]][] : memref<i1, strided<[], offset: ?>>
// The register measurement is unrolled, and the store, too.
// CHECK-NEXT:    %[[I0:.*]] = arith.constant 0 : index
// CHECK-NEXT:    %[[E0:.*]] = tensor.extract %[[Q]][%[[I0]]]
// CHECK-NEXT:    %[[N0:.*]] = qref.measure z %[[E0]]
// CHECK-NEXT:    %[[I1:.*]] = arith.constant 1 : index
// CHECK-NEXT:    %[[E1:.*]] = tensor.extract %[[Q]][%[[I1]]]
// CHECK-NEXT:    %[[N1:.*]] = qref.measure z %[[E1]]
// CHECK-NEXT:    %[[MS:.*]] = tensor.from_elements %[[N0]], %[[N1]] : tensor<2xi1>
// CHECK-NEXT:    %[[J0:.*]] = arith.constant 0 : index
// CHECK-NEXT:    %[[X0:.*]] = tensor.extract %[[MS]][%[[J0]]] : tensor<2xi1>
// CHECK-NEXT:    memref.store %[[X0]], %[[C]][%[[J0]]] : memref<2xi1>
// CHECK-NEXT:    %[[J1:.*]] = arith.constant 1 : index
// CHECK-NEXT:    %[[X1:.*]] = tensor.extract %[[MS]][%[[J1]]] : tensor<2xi1>
// CHECK-NEXT:    memref.store %[[X1]], %[[C]][%[[J1]]] : memref<2xi1>
// A bit of a register is a subview.
// CHECK:         %[[I:.*]] = arith.constant 1 : index
// CHECK-NEXT:    %[[BIT:.*]] = memref.subview %[[C]][%[[I]]] [1] [1] : memref<2xi1> to memref<i1, strided<[], offset: ?>>
// CHECK:         %[[M1:.*]] = qref.measure z
// CHECK-NEXT:    memref.store %[[M1]], %[[BIT]][] : memref<i1, strided<[], offset: ?>>
// A bitstring is a constant tensor; bit 0 is the last character.
// CHECK:         %[[BITS:.*]] = arith.constant dense<[true, false]> : tensor<2xi1>
// CHECK-NEXT:    %[[D:.*]] = memref.alloca() : memref<2xi1>
// CHECK:         memref.store %{{.*}}, %[[D]][%{{.*}}] : memref<2xi1>
// CHECK:         memref.store %{{.*}}, %[[D]][%{{.*}}] : memref<2xi1>
// The literals 0 and 1 are bits.
// CHECK:         %[[ONE:.*]] = arith.constant 1 : i64
// CHECK-NEXT:    %[[ZERO:.*]] = arith.constant 0 : i64
// CHECK-NEXT:    %[[SET:.*]] = arith.cmpi ne, %[[ONE]], %[[ZERO]] : i64
// CHECK-NEXT:    memref.store %[[SET]], %[[B]][] : memref<i1, strided<[], offset: ?>>
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %0 = oq3.constant #oq3.int<2> : !oq3.int
    %1 = oq3.qubit_decl "q" [%0 : !oq3.int] : !oq3.qreg<2>
    %2 = oq3.declare "b" : !qcc.ref<!oq3.bit>
    %3 = oq3.constant #oq3.int<2> : !oq3.int
    %4 = oq3.declare "c" [%3 : !oq3.int] : !qcc.ref<!oq3.bits<2>>
    %5 = oq3.constant #oq3.int<0> : !oq3.int
    %6 = oq3.qubit_index %1[%5] : !oq3.qreg<2>, !oq3.int
    %7 = oq3.measure %6 : !qcc.qubit_ref -> !oq3.bit
    qcc.ref.store %7, %2 : !qcc.ref<!oq3.bit>
    %8 = oq3.measure %1 : !oq3.qreg<2> -> !oq3.bits<2>
    qcc.ref.store %8, %4 : !qcc.ref<!oq3.bits<2>>
    %9 = oq3.constant #oq3.int<1> : !oq3.int
    %10 = oq3.unary neg %9 : !oq3.int
    %11 = oq3.subref %4[%10] : !qcc.ref<!oq3.bits<2>>, !oq3.int -> !qcc.ref<!oq3.bit>
    %12 = oq3.constant #oq3.int<1> : !oq3.int
    %13 = oq3.qubit_index %1[%12] : !oq3.qreg<2>, !oq3.int
    %14 = oq3.measure %13 : !qcc.qubit_ref -> !oq3.bit
    qcc.ref.store %14, %11 : !qcc.ref<!oq3.bit>
    %15 = oq3.constant #oq3.int<2> : !oq3.int
    %16 = oq3.constant #oq3.bitstring<"01"> : !oq3.bits<2>
    %17 = oq3.declare "d" [%15 : !oq3.int] = %16 : !oq3.bits<2> : !qcc.ref<!oq3.bits<2>>
    %18 = oq3.constant #oq3.int<1> : !oq3.int
    %19 = oq3.cast %18 implicit : !oq3.int -> !oq3.bit
    qcc.ref.store %19, %2 : !qcc.ref<!oq3.bit>
    return
  }
}

// -----

// Integers are `i64`, floats `f64`, if no `dlti.dl_spec` is present.

// CHECK-LABEL: func.func @main
// CHECK:         %[[TWO:.*]] = arith.constant 2 : i64
// CHECK-NEXT:    %[[THREE:.*]] = arith.constant 3 : i64
// CHECK-NEXT:    %[[PROD:.*]] = arith.muli %[[TWO]], %[[THREE]] : i64
// CHECK-NEXT:    %[[ONE:.*]] = arith.constant 1 : i64
// CHECK-NEXT:    %[[QUOT:.*]] = arith.divsi %[[PROD]], %[[ONE]] : i64
// CHECK-NEXT:    %[[ZERO:.*]] = arith.constant 0 : i64
// CHECK-NEXT:    %[[NEG:.*]] = arith.subi %[[ZERO]], %[[QUOT]] : i64
// CHECK-NEXT:    %[[LIT:.*]] = arith.constant 1.500000e+03 : f64
// CHECK-NEXT:    %[[FLOAT:.*]] = arith.sitofp %[[NEG]] : i64 to f64
// CHECK-NEXT:    %[[SUM:.*]] = arith.addf %[[FLOAT]], %[[LIT]] : f64
// CHECK-NEXT:    %[[E:.*]] = arith.constant 2.7182818284590451 : f64
// CHECK-NEXT:    %[[DIFF:.*]] = arith.subf %[[SUM]], %[[E]] : f64
// CHECK-NEXT:    %[[NEGF:.*]] = arith.negf %[[DIFF]] : f64
// CHECK-NEXT:    %[[TAU:.*]] = arith.constant 6.2831853071795862 : f64
// CHECK-NEXT:    %[[DIV:.*]] = arith.divf %[[NEGF]], %[[TAU]] : f64
// An angle is reduced to [0, 2π).
// CHECK-NEXT:    %[[TWO_PI:.*]] = arith.constant 6.2831853071795862 : f64
// CHECK-NEXT:    %[[REM:.*]] = arith.remf %[[DIV]], %[[TWO_PI]] : f64
// CHECK-NEXT:    %[[F0:.*]] = arith.constant 0.000000e+00 : f64
// CHECK-NEXT:    %[[IS_NEG:.*]] = arith.cmpf olt, %[[REM]], %[[F0]] : f64
// CHECK-NEXT:    %[[SHIFTED:.*]] = arith.addf %[[REM]], %[[TWO_PI]] : f64
// CHECK-NEXT:    %[[ANGLE:.*]] = arith.select %[[IS_NEG]], %[[SHIFTED]], %[[REM]] : f64
// CHECK-NEXT:    qref.single rx(%[[ANGLE]]) %{{.*}} : f64, !qcc.qubit_ref
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    oq3.include "stdgates.inc" id 0
    %0 = oq3.qubit_decl "q" : !qcc.qubit_ref
    %1 = oq3.constant #oq3.int<2> : !oq3.int
    %2 = oq3.constant #oq3.int<3> : !oq3.int
    %3 = oq3.binary mul %1, %2 : !oq3.int
    %4 = oq3.constant #oq3.int<1> : !oq3.int
    %5 = oq3.binary div %3, %4 : !oq3.int
    %6 = oq3.unary neg %5 : !oq3.int
    %7 = oq3.constant #oq3.float<"1.5e3"> : !oq3.float
    %8 = oq3.cast %6 implicit : !oq3.int -> !oq3.float
    %9 = oq3.binary add %8, %7 : !oq3.float
    %10 = oq3.math_constant euler : !oq3.float
    %11 = oq3.binary sub %9, %10 : !oq3.float
    %12 = oq3.unary neg %11 : !oq3.float
    %13 = oq3.math_constant tau : !oq3.float
    %14 = oq3.binary div %12, %13 : !oq3.float
    %15 = oq3.cast %14 implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @rx(%15 : !qcc.angle) [%0 : !qcc.qubit_ref]
    return
  }
}

// -----

// The unsized `int` and `float` have the target's word size, the width of `index` in the data layout. An angle stays
// `f64`, the type of gate parameters.

// CHECK-LABEL: func.func @main
// CHECK:         %[[TWO:.*]] = arith.constant 2 : i32
// CHECK-NEXT:    %[[FLOAT:.*]] = arith.sitofp %[[TWO]] : i32 to f32
// CHECK-NEXT:    %[[PI:.*]] = arith.constant 3.14159274 : f32
// CHECK-NEXT:    %[[QUOT:.*]] = arith.divf %[[PI]], %[[FLOAT]] : f32
// CHECK-NEXT:    %[[EXT:.*]] = arith.extf %[[QUOT]] : f32 to f64
// CHECK-NEXT:    %[[TWO_PI:.*]] = arith.constant 6.2831853071795862 : f64
// CHECK-NEXT:    %[[REM:.*]] = arith.remf %[[EXT]], %[[TWO_PI]] : f64
// CHECK:         %[[ANGLE:.*]] = arith.select %{{.*}} : f64
// CHECK-NEXT:    qref.single rx(%[[ANGLE]]) %{{.*}} : f64, !qcc.qubit_ref
module attributes {dlti.dl_spec = #dlti.dl_spec<index = 32>} {
  func.func @main() attributes {qcc.entry_point} {
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    %two = oq3.constant #oq3.int<2> : !oq3.int
    %float = oq3.cast %two implicit : !oq3.int -> !oq3.float
    %pi = oq3.math_constant pi : !oq3.float
    %quot = oq3.binary div %pi, %float : !oq3.float
    %angle = oq3.cast %quot implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @rx(%angle : !qcc.angle) [%q : !qcc.qubit_ref]
    return
  }
}
