// RUN: qcc-opt --split-input-file --convert-oq3-to-qref %s | FileCheck %s

// CHECK-LABEL: func.func @basic_std_gate() attributes {qcc.entry_point} {
module attributes {oq3.version = #oq3.version<3, 0>} {
  func.func @basic_std_gate() attributes {qcc.entry_point} {
    oq3.include "stdgates.inc" id 0
    oq3.pragma "qcc.something"
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    oq3.gate_call @h [%q : !qcc.qubit_ref] {oq3.annotations = [#oq3.annotation<"qcc.annotation", "">]}
    return
  }
}

// CHECK-NEXT:      %[[Q:.*]] = qcc.alloc : !qcc.qubit_ref
// CHECK-NEXT:      qref.single h %[[Q]] : !qcc.qubit_ref
// CHECK-NEXT:      return
// CHECK-NEXT:    }
// CHECK-NEXT:  }
// CHECK-NOT:   oq3.version

// -----

// Allocation and static references. Indices count from the end if negative.

// CHECK-LABEL: func.func @allocation_and_static
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @allocation_and_static() attributes {qcc.entry_point} {
    oq3.include "stdgates.inc" id 0
    %size = oq3.constant #oq3.int<3> : !oq3.int
    %q = oq3.qubit_decl "q" [%size : !oq3.int] : !oq3.qreg<3>
    %zero = oq3.constant #oq3.int<0> : !oq3.int
    %q0 = oq3.qubit_index %q[%zero] : !oq3.qreg<3>, !oq3.int
    oq3.gate_call @x [%q0 : !qcc.qubit_ref]
    %one = oq3.constant #oq3.int<1> : !oq3.int
    %minus_one = oq3.unary neg %one : !oq3.int
    %q_last = oq3.qubit_index %q[%minus_one] : !oq3.qreg<3>, !oq3.int
    oq3.gate_call @y [%q_last : !qcc.qubit_ref]
    %phys = oq3.physical_qubit 5 : !qcc.qubit_ref
    oq3.gate_call @z [%phys : !qcc.qubit_ref]
    %empty_size = oq3.constant #oq3.int<0> : !oq3.int
    %empty = oq3.qubit_decl "empty" [%empty_size : !oq3.int] : !oq3.qreg<0>
    return
  }
}

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

// -----

// CHECK-LABEL: func.func @broadcast_to_parallel
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @broadcast_to_parallel() attributes {qcc.entry_point} {
    oq3.include "stdgates.inc" id 0
    %size = oq3.constant #oq3.int<2> : !oq3.int
    %r = oq3.qubit_decl "r" [%size : !oq3.int] : !oq3.qreg<2>
    %a = oq3.qubit_decl "a" : !qcc.qubit_ref
    oq3.gate_call @cx [%a, %r : !qcc.qubit_ref, !oq3.qreg<2>]
    oq3.reset %r : !oq3.qreg<2>
    oq3.barrier [%r, %a : !oq3.qreg<2>, !qcc.qubit_ref]
    return
  }
}

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

// -----

// Bits are memrefs. A `bit` has a dynamic offset (`memref<i1, strided<[], offset: ?>>`) to match
// the type of a bit extracted from a register.

// CHECK-LABEL: func.func @bit_storage
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @bit_storage() attributes {qcc.entry_point} {
    // most specific converted type *would* be memref<i1> (offset 0):
    %b = oq3.declare "b" : !qcc.ref<!oq3.bit>
    %size = oq3.constant #oq3.int<2> : !oq3.int
    %c = oq3.declare "c" [%size : !oq3.int] : !qcc.ref<!oq3.bits<2>>
    %one = oq3.constant #oq3.int<1> : !oq3.int
    // most specific converted type *would* be memref<i1, strided<[], offset: 1>>:
    %c1 = oq3.subref %c[%one] : !qcc.ref<!oq3.bits<2>>, !oq3.int -> !qcc.ref<!oq3.bit>
    // but %b and %c1 must have the same type (type converter is 1:1), hence memref<i1, strided<[], offset: ?>> for both.
    return
  }
}

// CHECK:         %[[B:.*]] = memref.alloca() : memref<i1>
// CHECK-NEXT:    %{{.*}} = memref.cast %[[B]] : memref<i1> to memref<i1, strided<[], offset: ?>>
// CHECK:         %[[C:.*]] = memref.alloca() : memref<2xi1>
// CHECK:         %[[I:.*]] = arith.constant 1 : index
// CHECK-NEXT:    %{{.*}} = memref.subview %[[C]][%[[I]]] [1] [1] : memref<2xi1> to memref<i1, strided<[], offset: ?>>

// -----

// CHECK-LABEL: func.func @measure_qubit
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @measure_qubit() attributes {qcc.entry_point} {
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    %b = oq3.declare "b" : !qcc.ref<!oq3.bit>
    %m = oq3.measure %q : !qcc.qubit_ref -> !oq3.bit
    qcc.ref.store %m, %b : !qcc.ref<!oq3.bit>
    return
  }
}

// CHECK:         %[[Q:.*]] = qcc.alloc : !qcc.qubit_ref
// CHECK-NEXT:    %[[ALLOCA:.*]] = memref.alloca() : memref<i1>
// CHECK-NEXT:    %[[B:.*]] = memref.cast %[[ALLOCA]]
// CHECK-NEXT:    %[[M:.*]] = qref.measure z %[[Q]] : !qcc.qubit_ref -> i1
// CHECK-NEXT:    memref.store %[[M]], %[[B]][] : memref<i1, strided<[], offset: ?>>
// CHECK-NEXT:    return

// -----

// Measuring a register into storage (`c = measure q;`) is one parallel loop that writes each bit to the corresponding memref.

// CHECK-LABEL: func.func @measure_register
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @measure_register() attributes {qcc.entry_point} {
    %size = oq3.constant #oq3.int<2> : !oq3.int
    %q = oq3.qubit_decl "q" [%size : !oq3.int] : !oq3.qreg<2>
    %c = oq3.declare "c" [%size : !oq3.int] : !qcc.ref<!oq3.bits<2>>
    %m = oq3.measure %q : !oq3.qreg<2> -> !oq3.bits<2>
    qcc.ref.store %m, %c : !qcc.ref<!oq3.bits<2>>
    return
  }
}

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

// -----

// Measuring a register for anything but an immediately following store (here: an initializer, `bit[2] c = measure
// q;`) collects the bits into a tensor in an `scf.forall`.

// CHECK-LABEL: func.func @measure_register_initializer
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @measure_register_initializer() attributes {qcc.entry_point} {
    %size = oq3.constant #oq3.int<2> : !oq3.int
    %q = oq3.qubit_decl "q" [%size : !oq3.int] : !oq3.qreg<2>
    %m = oq3.measure %q : !oq3.qreg<2> -> !oq3.bits<2>
    %c = oq3.declare "c" [%size : !oq3.int] = %m : !oq3.bits<2> : !qcc.ref<!oq3.bits<2>>
    return
  }
}

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

// -----

// A bitstring initializer (`bit[2] d = "01";`) is a constant tensor, stored in parallel; bit 0 is the last character.

// CHECK-LABEL: func.func @bitstring_initializer
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @bitstring_initializer() attributes {qcc.entry_point} {
    %size = oq3.constant #oq3.int<2> : !oq3.int
    %bits = oq3.constant #oq3.bitstring<"01"> : !oq3.bits<2>
    %d = oq3.declare "d" [%size : !oq3.int] = %bits : !oq3.bits<2> : !qcc.ref<!oq3.bits<2>>
    return
  }
}

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

// -----

// An `int` casts to a `bit` by comparing with 0.

// CHECK-LABEL: func.func @int_to_bit
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @int_to_bit() attributes {qcc.entry_point} {
    %one = oq3.constant #oq3.int<1> : !oq3.int
    %bit = oq3.cast %one implicit : !oq3.int -> !oq3.bit
    return
  }
}

// CHECK:         %[[ONE:.*]] = arith.constant 1 : i64
// CHECK-NEXT:    %[[ZERO:.*]] = arith.constant 0 : i64
// CHECK-NEXT:    %{{.*}} = arith.cmpi ne, %[[ONE]], %[[ZERO]] : i64
// CHECK-NEXT:    return

// -----

// Without a `dlti.dl_spec`, the unsized `int` is `i64` and `float` is `f64`.

// CHECK-LABEL: func.func @default_word_size
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @default_word_size() attributes {qcc.entry_point} {
    %int = oq3.constant #oq3.int<2> : !oq3.int
    %float = oq3.constant #oq3.float<"0.5"> : !oq3.float
    return
  }
}

// CHECK:         arith.constant 2 : i64
// CHECK-NEXT:    arith.constant 5.000000e-01 : f64

// -----

// The unsized `int` and `float` have the target's word size (32 in this case).
// An angle stays `f64`, the type of gate parameters.

// CHECK-LABEL: func.func @data_layout_word_size
module attributes {dlti.dl_spec = #dlti.dl_spec<index = 32>} {
  func.func @data_layout_word_size() attributes {qcc.entry_point} {
    %int = oq3.constant #oq3.int<2> : !oq3.int
    %float = oq3.constant #oq3.float<"0.5"> : !oq3.float
    %angle = oq3.cast %float implicit : !oq3.float -> !qcc.angle
    return
  }
}

// CHECK:         arith.constant 2 : i32
// CHECK-NEXT:    %[[F:.*]] = arith.constant 5.000000e-01 : f32
// CHECK-NEXT:    arith.extf %[[F]] : f32 to f64

// -----

// CHECK-LABEL: func.func @int_arith
func.func @int_arith() {
  %a = oq3.constant #oq3.int<2> : !oq3.int
  %b = oq3.constant #oq3.int<3> : !oq3.int
  %sum = oq3.binary add %a, %b : !oq3.int
  %diff = oq3.binary sub %a, %b : !oq3.int
  %prod = oq3.binary mul %a, %b : !oq3.int
  %quot = oq3.binary div %a, %b : !oq3.int
  %neg = oq3.unary neg %a : !oq3.int
  return
}

// CHECK:         %[[A:.*]] = arith.constant 2 : i64
// CHECK-NEXT:    %[[B:.*]] = arith.constant 3 : i64
// CHECK-NEXT:    arith.addi %[[A]], %[[B]] : i64
// CHECK-NEXT:    arith.subi %[[A]], %[[B]] : i64
// CHECK-NEXT:    arith.muli %[[A]], %[[B]] : i64
// CHECK-NEXT:    arith.divsi %[[A]], %[[B]] : i64
// CHECK-NEXT:    %[[ZERO:.*]] = arith.constant 0 : i64
// CHECK-NEXT:    arith.subi %[[ZERO]], %[[A]] : i64

// -----

// CHECK-LABEL: func.func @float_arith
func.func @float_arith() {
  %a = oq3.constant #oq3.float<"1.5e3"> : !oq3.float
  %b = oq3.constant #oq3.float<"0.5"> : !oq3.float
  %sum = oq3.binary add %a, %b : !oq3.float
  %diff = oq3.binary sub %a, %b : !oq3.float
  %prod = oq3.binary mul %a, %b : !oq3.float
  %quot = oq3.binary div %a, %b : !oq3.float
  %neg = oq3.unary neg %a : !oq3.float
  return
}

// CHECK:         %[[A:.*]] = arith.constant 1.500000e+03 : f64
// CHECK-NEXT:    %[[B:.*]] = arith.constant 5.000000e-01 : f64
// CHECK-NEXT:    arith.addf %[[A]], %[[B]] : f64
// CHECK-NEXT:    arith.subf %[[A]], %[[B]] : f64
// CHECK-NEXT:    arith.mulf %[[A]], %[[B]] : f64
// CHECK-NEXT:    arith.divf %[[A]], %[[B]] : f64
// CHECK-NEXT:    arith.negf %[[A]] : f64

// -----

// CHECK-LABEL: func.func @math_constants
func.func @math_constants() {
  %pi = oq3.math_constant pi : !oq3.float
  %tau = oq3.math_constant tau : !oq3.float
  %e = oq3.math_constant euler : !oq3.float
  return
}

// CHECK-NEXT:    arith.constant 3.1415926535897931 : f64
// CHECK-NEXT:    arith.constant 6.2831853071795862 : f64
// CHECK-NEXT:    arith.constant 2.7182818284590451 : f64

// -----

// CHECK-LABEL: func.func @casts
func.func @casts() {
  %i = oq3.constant #oq3.int<2> : !oq3.int
  %float = oq3.cast %i implicit : !oq3.int -> !oq3.float
  %f = oq3.constant #oq3.float<"-0.5"> : !oq3.float
  %angle = oq3.cast %f implicit : !oq3.float -> !qcc.angle
  return
}

// CHECK:         %[[I:.*]] = arith.constant 2 : i64
// CHECK-NEXT:    arith.sitofp %[[I]] : i64 to f64
// CHECK-NEXT:    %[[F:.*]] = arith.constant -5.000000e-01 : f64
// An angle is reduced to [0, 2π).
// CHECK-NEXT:    %[[TWO_PI:.*]] = arith.constant 6.2831853071795862 : f64
// CHECK-NEXT:    %[[REM:.*]] = arith.remf %[[F]], %[[TWO_PI]] : f64
// CHECK-NEXT:    %[[ZERO:.*]] = arith.constant 0.000000e+00 : f64
// CHECK-NEXT:    %[[IS_NEG:.*]] = arith.cmpf olt, %[[REM]], %[[ZERO]] : f64
// CHECK-NEXT:    %[[SHIFTED:.*]] = arith.addf %[[REM]], %[[TWO_PI]] : f64
// CHECK-NEXT:    arith.select %[[IS_NEG]], %[[SHIFTED]], %[[REM]] : f64
