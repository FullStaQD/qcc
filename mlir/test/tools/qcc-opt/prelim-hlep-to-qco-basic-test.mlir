// RUN: qcc-opt %s --prelim-hlep-to-qco | FileCheck %s

// Constant bits allocate fresh qubits; the unit argument is erased.

func.func @zero_state(%u : !prelimhlep.unit) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %q = prelimhlep.lin () -> (!prelimhlep.lin<i1>) {
        %zero = arith.constant 0 : i1
        prelimhlep.output (%zero : i1)
    }
    return %q : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @zero_state() -> !qco.qubit
// CHECK:         [[Q:%.+]] = qco.alloc
// CHECK-NEXT:    return [[Q]] : !qco.qubit

func.func @one_state(%u : !prelimhlep.unit) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %q = prelimhlep.lin () -> (!prelimhlep.lin<i1>) {
        %one = arith.constant 1 : i1
        prelimhlep.output (%one : i1)
    }
    return %q : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @one_state() -> !qco.qubit
// CHECK:         [[Q:%.+]] = qco.alloc
// CHECK-NEXT:    [[X:%.+]] = qco.x [[Q]]
// CHECK-NEXT:    return [[X]] : !qco.qubit

// A negated input bit becomes an X gate.

func.func @x_gate(%qubit: !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %out = prelimhlep.lin (%b : i1 from %qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant 1 : i1
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    return %out : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @x_gate(
// CHECK-SAME:      [[ARG:%.+]]: !qco.qubit) -> !qco.qubit
// CHECK:         [[X:%.+]] = qco.x [[ARG]]
// CHECK-NEXT:    return [[X]] : !qco.qubit

// Bit fiddling that only re-bundles qubits emits no gates at all; the
// multi-qubit register is threaded through as individual qubit values,
// least-significant bit first.

func.func @combine_2(%q0 : !prelimhlep.lin<i1>, %q1 : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i2> attributes { prelimhlep.halo } {
    %qs = prelimhlep.lin (
        %b0 : i1 from %q0 : !prelimhlep.lin<i1>,
        %b1 : i1 from %q1 : !prelimhlep.lin<i1>
    ) -> (!prelimhlep.lin<i2>) {
        %c1 = arith.constant 1 : i2
        %e0 = arith.extui %b0 : i1 to i2
        %e1 = arith.extui %b1 : i1 to i2
        %s1 = arith.shli %e1, %c1 : i2
        %or = arith.ori %e0, %s1 : i2
        prelimhlep.output (%or : i2)
    }
    return %qs : !prelimhlep.lin<i2>
}

// CHECK-LABEL: func.func @combine_2(
// CHECK-SAME:      [[Q0:%.+]]: !qco.qubit, [[Q1:%.+]]: !qco.qubit) -> (!qco.qubit, !qco.qubit)
// CHECK-NEXT:    return [[Q0]], [[Q1]] : !qco.qubit, !qco.qubit

func.func @split_2(%qs : !prelimhlep.lin<i2>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %q0, %q1 = prelimhlep.lin (%bs : i2 from %qs : !prelimhlep.lin<i2>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %c1 = arith.constant 1 : i2
        %b0 = arith.trunci %bs : i2 to i1
        %hs = arith.shrui %bs, %c1 : i2
        %b1 = arith.trunci %hs : i2 to i1
        prelimhlep.output (%b0 : i1, %b1 : i1)
    }
    return %q0, %q1 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @split_2(
// CHECK-SAME:      [[Q0:%.+]]: !qco.qubit, [[Q1:%.+]]: !qco.qubit) -> (!qco.qubit, !qco.qubit)
// CHECK-NEXT:    return [[Q0]], [[Q1]] : !qco.qubit, !qco.qubit

// A conditional unitary on a captured linear value becomes qco.ctrl. This
// is the shape `@cnot` from the advanced test takes after inlining.

func.func @cnot(%control : !prelimhlep.lin<i1>, %target : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %oc, %ot = prelimhlep.lin (%cb : i1 from %control : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %new_target = scf.if %cb -> (!prelimhlep.lin<i1>) {
            %flipped = prelimhlep.lin (%tb : i1 from %target : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
                %one = arith.constant 1 : i1
                %ntb = arith.xori %tb, %one : i1
                prelimhlep.output (%ntb : i1)
            }
            scf.yield %flipped : !prelimhlep.lin<i1>
        } else {
            scf.yield %target : !prelimhlep.lin<i1>
        }
        prelimhlep.output (%cb : i1) carrying (%new_target : !prelimhlep.lin<i1>)
    }
    return %oc, %ot : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @cnot(
// CHECK-SAME:      [[C:%.+]]: !qco.qubit, [[T:%.+]]: !qco.qubit)
// CHECK:         [[COUT:%.+]], [[TOUT:%.+]] = qco.ctrl([[C]]) targets ([[BODYARG:%.+]] = [[T]]) {
// CHECK-NEXT:      [[BX:%.+]] = qco.x [[BODYARG]]
// CHECK-NEXT:      qco.yield [[BX]]
// CHECK-NEXT:    }
// CHECK:         return [[COUT]], [[TOUT]] : !qco.qubit, !qco.qubit

// A basis-conditional constant transforms the input qubit in place. This
// mapping ({0 -> "+", 1 -> "-"}) is a plain Hadamard.

func.func @hadamard(%in : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
  %x_out = prelimhlep.lin (%b: i1 from %in: !prelimhlep.lin<i1>) -> (!prelimhlep.lin<!prelimhlep.x<1>>) {
    %r = scf.if %b -> !prelimhlep.lin<!prelimhlep.x<1>> {
      %m = prelimhlep.constant "-" : !prelimhlep.lin<!prelimhlep.x<1>>
      scf.yield %m : !prelimhlep.lin<!prelimhlep.x<1>>
    } else {
      %p = prelimhlep.constant "+" : !prelimhlep.lin<!prelimhlep.x<1>>
      scf.yield %p : !prelimhlep.lin<!prelimhlep.x<1>>
    }
    prelimhlep.output () carrying (%r : !prelimhlep.lin<!prelimhlep.x<1>>)
  }
  %out = prelimhlep.base_change %x_out : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<i1>
  return %out : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @hadamard(
// CHECK-SAME:      [[ARG:%.+]]: !qco.qubit) -> !qco.qubit
// CHECK:         [[H:%.+]] = qco.h [[ARG]]
// CHECK-NEXT:    return [[H]] : !qco.qubit

// The swapped mapping ({0 -> "-", 1 -> "+"}) is X followed by Hadamard.

func.func @hadamard_flipped(%in : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
  %x_out = prelimhlep.lin (%b: i1 from %in: !prelimhlep.lin<i1>) -> (!prelimhlep.lin<!prelimhlep.x<1>>) {
    %r = scf.if %b -> !prelimhlep.lin<!prelimhlep.x<1>> {
      %p = prelimhlep.constant "+" : !prelimhlep.lin<!prelimhlep.x<1>>
      scf.yield %p : !prelimhlep.lin<!prelimhlep.x<1>>
    } else {
      %m = prelimhlep.constant "-" : !prelimhlep.lin<!prelimhlep.x<1>>
      scf.yield %m : !prelimhlep.lin<!prelimhlep.x<1>>
    }
    prelimhlep.output () carrying (%r : !prelimhlep.lin<!prelimhlep.x<1>>)
  }
  %out = prelimhlep.base_change %x_out : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<i1>
  return %out : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @hadamard_flipped(
// CHECK-SAME:      [[ARG:%.+]]: !qco.qubit) -> !qco.qubit
// CHECK:         [[X:%.+]] = qco.x [[ARG]]
// CHECK-NEXT:    [[H:%.+]] = qco.h [[X]]
// CHECK-NEXT:    return [[H]] : !qco.qubit

// A conditional phase flip becomes a controlled Z, with X-conjugation on
// the controls whose required value is 0 (here bit 0, since the marked
// basis state is 2 = 0b10).

func.func @phase_tag_2(%state : !prelimhlep.lin<i2>) -> !prelimhlep.lin<i2> attributes { prelimhlep.halo } {
    %tagged = prelimhlep.lin (%bits: i2 from %state : !prelimhlep.lin<i2>) -> (!prelimhlep.lin<i2>) {
        %two = arith.constant 2 : i2
        %hit = arith.cmpi eq, %bits, %two : i2
        %r = scf.if %hit -> i2 {
            %neg = complex.constant [-1.0, 0.0] : complex<f64>
            %s = prelimhlep.scale %neg, %bits : (complex<f64>, i2) -> i2
            scf.yield %s : i2
        } else {
            scf.yield %bits : i2
        }
        prelimhlep.output (%r : i2)
    }
    return %tagged : !prelimhlep.lin<i2>
}

// CHECK-LABEL: func.func @phase_tag_2(
// CHECK-SAME:      [[Q0:%.+]]: !qco.qubit, [[Q1:%.+]]: !qco.qubit)
// CHECK:         [[X0:%.+]] = qco.x [[Q0]]
// CHECK-NEXT:    [[COUT:%.+]], [[TOUT:%.+]] = qco.ctrl([[X0]]) targets ([[BODYARG:%.+]] = [[Q1]]) {
// CHECK-NEXT:      [[Z:%.+]] = qco.z [[BODYARG]]
// CHECK-NEXT:      qco.yield [[Z]]
// CHECK-NEXT:    }
// CHECK:         [[UNDO:%.+]] = qco.x [[COUT]]
// CHECK-NEXT:    return [[UNDO]], [[TOUT]] : !qco.qubit, !qco.qubit

// Purely classical auxiliary results become measurements; qubits that are
// not re-output are sunk, and the classical register is rebuilt from the
// individual measurement bits.

func.func @measure_2(%state : !prelimhlep.lin<i2>) -> i2 attributes { prelimhlep.halo } {
    %result = prelimhlep.lin (%bits : i2 from %state : !prelimhlep.lin<i2>) -> (i2) {
        prelimhlep.output () carrying (%bits : i2)
    }
    return %result : i2
}

// CHECK-LABEL: func.func @measure_2(
// CHECK-SAME:      [[Q0:%.+]]: !qco.qubit, [[Q1:%.+]]: !qco.qubit) -> i2
// CHECK:         [[M0:%.+]], [[B0:%.+]] = qco.measure [[Q0]]
// CHECK-NEXT:    [[M1:%.+]], [[B1:%.+]] = qco.measure [[Q1]]
// CHECK-DAG:     [[E0:%.+]] = arith.extui [[B0]] : i1 to i2
// CHECK-DAG:     [[E1:%.+]] = arith.extui [[B1]] : i1 to i2
// CHECK:         arith.shli [[E1]],
// CHECK:         [[RES:%.+]] = arith.ori
// CHECK-DAG:     qco.sink [[M0]]
// CHECK-DAG:     qco.sink [[M1]]
// CHECK:         return [[RES]] : i2

func.func @measure_and_keep(%qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) attributes { prelimhlep.halo } {
    %q, %bit = prelimhlep.lin (%b : i1 from %qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
        prelimhlep.output (%b : i1) carrying (%b : i1)
    }
    return %q, %bit : !prelimhlep.lin<i1>, i1
}

// CHECK-LABEL: func.func @measure_and_keep(
// CHECK-SAME:      [[Q:%.+]]: !qco.qubit) -> (!qco.qubit, i1)
// CHECK:         [[MQ:%.+]], [[B:%.+]] = qco.measure [[Q]]
// CHECK-NOT:     qco.sink
// CHECK:         return [[MQ]], [[B]] : !qco.qubit, i1

// Global phases.

func.func @global_phase(%qubit : !prelimhlep.lin<i1>, %alpha : f64) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %out = prelimhlep.add_phase %alpha, %qubit : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %out : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @global_phase(
// CHECK-SAME:      [[Q:%.+]]: !qco.qubit, [[ALPHA:%.+]]: f64)
// CHECK:         qco.gphase([[ALPHA]])
// CHECK-NEXT:    return [[Q]] : !qco.qubit

func.func @scale_minus_one(%qubit : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %neg = complex.constant [-1.0, 0.0] : complex<f64>
    %out = prelimhlep.scale %neg, %qubit : (complex<f64>, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %out : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @scale_minus_one(
// CHECK-SAME:      [[Q:%.+]]: !qco.qubit)
// CHECK:         [[PI:%.+]] = arith.constant 3.14159265{{.*}} : f64
// CHECK:         qco.gphase([[PI]])
// CHECK:         return [[Q]] : !qco.qubit

// Single-term hamiltonian exponentials map onto rotation gates; the angle
// is 2 * coefficient * angle (exp(-i a c Z) == rz(2 c a)).

func.func @exp_rz(%theta : f64, %qubit : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %out = prelimhlep.exp %theta hamiltonian<1, 5.000000e-01 * Z[0]> %qubit : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    return %out : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @exp_rz(
// CHECK-SAME:      [[THETA:%.+]]: f64, [[Q:%.+]]: !qco.qubit)
// CHECK:         [[C:%.+]] = arith.constant 1.000000e+00 : f64
// CHECK-NEXT:    [[ANGLE:%.+]] = arith.mulf [[THETA]], [[C]]
// CHECK-NEXT:    [[RZ:%.+]] = qco.rz([[ANGLE]]) [[Q]]
// CHECK-NEXT:    return [[RZ]] : !qco.qubit

func.func @exp_rxx(%theta : f64, %state : !prelimhlep.lin<i2>) -> !prelimhlep.lin<i2> attributes { prelimhlep.halo } {
    %out = prelimhlep.exp %theta hamiltonian<2, X[0] * X[1]> %state : (f64, !prelimhlep.lin<i2>) -> !prelimhlep.lin<i2>
    return %out : !prelimhlep.lin<i2>
}

// CHECK-LABEL: func.func @exp_rxx(
// CHECK-SAME:      [[THETA:%.+]]: f64, [[Q0:%.+]]: !qco.qubit, [[Q1:%.+]]: !qco.qubit)
// CHECK:         [[C:%.+]] = arith.constant 2.000000e+00 : f64
// CHECK-NEXT:    [[ANGLE:%.+]] = arith.mulf [[THETA]], [[C]]
// CHECK-NEXT:    [[R0:%.+]], [[R1:%.+]] = qco.rxx([[ANGLE]]) [[Q0]], [[Q1]]
// CHECK-NEXT:    return [[R0]], [[R1]] : !qco.qubit, !qco.qubit

// Y-basis constants: "->" is S H |0>, "<-" is S H |1>.

func.func @constant_y(%u : !prelimhlep.unit) -> !prelimhlep.lin<!prelimhlep.y<2>> attributes { prelimhlep.halo } {
    %c = prelimhlep.constant "-><-" : !prelimhlep.lin<!prelimhlep.y<2>>
    return %c : !prelimhlep.lin<!prelimhlep.y<2>>
}

// CHECK-LABEL: func.func @constant_y() -> (!qco.qubit, !qco.qubit)
// CHECK:         [[A0:%.+]] = qco.alloc
// CHECK-NEXT:    [[H0:%.+]] = qco.h [[A0]]
// CHECK-NEXT:    [[S0:%.+]] = qco.s [[H0]]
// CHECK-NEXT:    [[A1:%.+]] = qco.alloc
// CHECK-NEXT:    [[X1:%.+]] = qco.x [[A1]]
// CHECK-NEXT:    [[H1:%.+]] = qco.h [[X1]]
// CHECK-NEXT:    [[S1:%.+]] = qco.s [[H1]]
// CHECK-NEXT:    return [[S0]], [[S1]] : !qco.qubit, !qco.qubit

// Calls between haloed functions thread the expanded qubit values, and a
// classical function calling into a haloed one drops the erased unit
// value.

func.func @caller(%u : !prelimhlep.unit) -> i1 attributes { prelimhlep.halo } {
    %q = func.call @zero_state(%u) : (!prelimhlep.unit) -> !prelimhlep.lin<i1>
    %h = func.call @hadamard(%q) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
    %m = prelimhlep.lin (%b : i1 from %h : !prelimhlep.lin<i1>) -> (i1) {
        prelimhlep.output () carrying (%b : i1)
    }
    return %m : i1
}

// CHECK-LABEL: func.func @caller() -> i1
// CHECK:         [[Q:%.+]] = call @zero_state() : () -> !qco.qubit
// CHECK-NEXT:    [[H:%.+]] = call @hadamard([[Q]]) : (!qco.qubit) -> !qco.qubit
// CHECK-NEXT:    [[MQ:%.+]], [[B:%.+]] = qco.measure [[H]]
// CHECK-NEXT:    qco.sink [[MQ]]
// CHECK-NEXT:    return [[B]] : i1

func.func @classical_main() -> i1 {
    %u = prelimhlep.unit_value : !prelimhlep.unit
    %r = func.call @caller(%u) : (!prelimhlep.unit) -> i1
    return %r : i1
}

// CHECK-LABEL: func.func @classical_main() -> i1
// CHECK-NEXT:    [[R:%.+]] = call @caller() : () -> i1
// CHECK-NEXT:    return [[R]] : i1

// CHECK-NOT: prelimhlep
