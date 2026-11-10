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

// Bits are memrefs. A `bit` has a dynamic offset (`memref<i1, strided<[], offset: ?>>`) to match
// the type of a bit extracted from a register.

// CHECK-LABEL: func.func @bit_storage
// CHECK:         %[[B:.*]] = memref.alloca() : memref<i1>
// CHECK-NEXT:    %{{.*}} = memref.cast %[[B]] : memref<i1> to memref<i1, strided<[], offset: ?>>
// CHECK:         %[[C:.*]] = memref.alloca() : memref<2xi1>
// CHECK:         %[[I:.*]] = arith.constant 1 : index
// CHECK-NEXT:    %{{.*}} = memref.subview %[[C]][%[[I]]] [1] [1] : memref<2xi1> to memref<i1, strided<[], offset: ?>>
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @bit_storage() attributes {qcc.entry_point} {
    // most specific converted type *would* be memref<i1> (offset 0):
    %0 = oq3.declare "b" : !qcc.ref<!oq3.bit>
    %1 = oq3.constant #oq3.int<2> : !oq3.int
    %2 = oq3.declare "c" [%1 : !oq3.int] : !qcc.ref<!oq3.bits<2>>
    %3 = oq3.constant #oq3.int<1> : !oq3.int
    // most specific converted type *would* be memref<i1, strided<[], offset: 1>>:
    %4 = oq3.subref %2[%3] : !qcc.ref<!oq3.bits<2>>, !oq3.int -> !qcc.ref<!oq3.bit>
    // but %0 and %4 must have the same type (type converter is 1:1), hence memref<i1, strided<[], offset: ?>> for both.
    return
  }
}

// -----

// CHECK-LABEL: func.func @measure_qubit
// CHECK:         %[[Q:.*]] = qcc.alloc : !qcc.qubit_ref
// CHECK-NEXT:    %[[ALLOCA:.*]] = memref.alloca() : memref<i1>
// CHECK-NEXT:    %[[B:.*]] = memref.cast %[[ALLOCA]]
// CHECK-NEXT:    %[[M:.*]] = qref.measure z %[[Q]] : !qcc.qubit_ref -> i1
// CHECK-NEXT:    memref.store %[[M]], %[[B]][] : memref<i1, strided<[], offset: ?>>
// CHECK-NEXT:    return
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @measure_qubit() attributes {qcc.entry_point} {
    %0 = oq3.qubit_decl "q" : !qcc.qubit_ref
    %1 = oq3.declare "b" : !qcc.ref<!oq3.bit>
    %2 = oq3.measure %0 : !qcc.qubit_ref -> !oq3.bit
    qcc.ref.store %2, %1 : !qcc.ref<!oq3.bit>
    return
  }
}

// -----

// Measuring a register into storage (`c = measure q;`) is one parallel loop that writes each bit straight to `c`.

// CHECK-LABEL: func.func @measure_register
// CHECK:         %[[Q:.*]] = qcc.alloc : tensor<2x!qcc.qubit_ref>
// CHECK-NEXT:    %[[C:.*]] = memref.alloca() : memref<2xi1>
// CHECK-NEXT:    %[[LB:.*]] = arith.constant 0 : index
// CHECK-NEXT:    %[[UB:.*]] = arith.constant 2 : index
// CHECK-NEXT:    %[[STEP:.*]] = arith.constant 1 : index
// CHECK-NEXT:    scf.parallel (%[[I:.*]]) = (%[[LB]]) to (%[[UB]]) step (%[[STEP]]) {
// CHECK-NEXT:      %[[QI:.*]] = tensor.extract %[[Q]][%[[I]]] : tensor<2x!qcc.qubit_ref>
// CHECK-NEXT:      %[[M:.*]] = qref.measure z %[[QI]] : !qcc.qubit_ref -> i1
// CHECK-NEXT:      memref.store %[[M]], %[[C]][%[[I]]] : memref<2xi1>
// CHECK-NEXT:      scf.reduce
// CHECK-NEXT:    }
// CHECK-NEXT:    return
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @measure_register() attributes {qcc.entry_point} {
    %0 = oq3.constant #oq3.int<2> : !oq3.int
    %1 = oq3.qubit_decl "q" [%0 : !oq3.int] : !oq3.qreg<2>
    %2 = oq3.declare "c" [%0 : !oq3.int] : !qcc.ref<!oq3.bits<2>>
    %3 = oq3.measure %1 : !oq3.qreg<2> -> !oq3.bits<2>
    qcc.ref.store %3, %2 : !qcc.ref<!oq3.bits<2>>
    return
  }
}

// -----

// Measuring a register for anything but an immediately following store (here: an initializer, `bit[2] c = measure
// q;`) collects the bits into a tensor in an `scf.forall`.

// CHECK-LABEL: func.func @measure_register_initializer
// CHECK:         %[[Q:.*]] = qcc.alloc : tensor<2x!qcc.qubit_ref>
// CHECK-NEXT:    %[[EMPTY:.*]] = tensor.empty() : tensor<2xi1>
// CHECK-NEXT:    %[[MS:.*]] = scf.forall (%[[I:.*]]) in (2) shared_outs(%[[ACC:.*]] = %[[EMPTY]]) -> (tensor<2xi1>) {
// CHECK-NEXT:      %[[QI:.*]] = tensor.extract %[[Q]][%[[I]]] : tensor<2x!qcc.qubit_ref>
// CHECK-NEXT:      %[[M:.*]] = qref.measure z %[[QI]] : !qcc.qubit_ref -> i1
// CHECK-NEXT:      %[[SLICE:.*]] = tensor.from_elements %[[M]] : tensor<1xi1>
// CHECK-NEXT:      scf.forall.in_parallel {
// CHECK-NEXT:        tensor.parallel_insert_slice %[[SLICE]] into %[[ACC]][%[[I]]] [1] [1] : tensor<1xi1> into tensor<2xi1>
// CHECK-NEXT:      }
// CHECK-NEXT:    }
// CHECK-NEXT:    %[[C:.*]] = memref.alloca() : memref<2xi1>
// CHECK:         scf.parallel (%[[J:.*]]) =
// CHECK-NEXT:      %[[X:.*]] = tensor.extract %[[MS]][%[[J]]] : tensor<2xi1>
// CHECK-NEXT:      memref.store %[[X]], %[[C]][%[[J]]] : memref<2xi1>
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @measure_register_initializer() attributes {qcc.entry_point} {
    %0 = oq3.constant #oq3.int<2> : !oq3.int
    %1 = oq3.qubit_decl "q" [%0 : !oq3.int] : !oq3.qreg<2>
    %2 = oq3.measure %1 : !oq3.qreg<2> -> !oq3.bits<2>
    %3 = oq3.declare "c" [%0 : !oq3.int] = %2 : !oq3.bits<2> : !qcc.ref<!oq3.bits<2>>
    return
  }
}

// -----

// A bitstring initializer (`bit[2] d = "01";`) is a constant tensor, stored in parallel; bit 0 is the last character.

// CHECK-LABEL: func.func @bitstring_initializer
// CHECK:         %[[BITS:.*]] = arith.constant dense<[true, false]> : tensor<2xi1>
// CHECK-NEXT:    %[[D:.*]] = memref.alloca() : memref<2xi1>
// CHECK-NEXT:    %[[LB:.*]] = arith.constant 0 : index
// CHECK-NEXT:    %[[UB:.*]] = arith.constant 2 : index
// CHECK-NEXT:    %[[STEP:.*]] = arith.constant 1 : index
// CHECK-NEXT:    scf.parallel (%[[I:.*]]) = (%[[LB]]) to (%[[UB]]) step (%[[STEP]]) {
// CHECK-NEXT:      %[[X:.*]] = tensor.extract %[[BITS]][%[[I]]] : tensor<2xi1>
// CHECK-NEXT:      memref.store %[[X]], %[[D]][%[[I]]] : memref<2xi1>
// CHECK-NEXT:      scf.reduce
// CHECK-NEXT:    }
// CHECK-NEXT:    return
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @bitstring_initializer() attributes {qcc.entry_point} {
    %0 = oq3.constant #oq3.int<2> : !oq3.int
    %1 = oq3.constant #oq3.bitstring<"01"> : !oq3.bits<2>
    %2 = oq3.declare "d" [%0 : !oq3.int] = %1 : !oq3.bits<2> : !qcc.ref<!oq3.bits<2>>
    return
  }
}

// -----

// An `int` casts to a `bit` by comparing with 0.

// CHECK-LABEL: func.func @int_to_bit
// CHECK:         %[[ONE:.*]] = arith.constant 1 : i64
// CHECK-NEXT:    %[[ZERO:.*]] = arith.constant 0 : i64
// CHECK-NEXT:    %{{.*}} = arith.cmpi ne, %[[ONE]], %[[ZERO]] : i64
// CHECK-NEXT:    return
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @int_to_bit() attributes {qcc.entry_point} {
    %0 = oq3.constant #oq3.int<1> : !oq3.int
    %1 = oq3.cast %0 implicit : !oq3.int -> !oq3.bit
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
