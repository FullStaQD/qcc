// RUN: qcc-opt %s --prelim-hlep-lin-to-gates | FileCheck %s
// RUN: qcc-opt %s --prelim-hlep-lin-to-gates --prelim-hlep-lin-to-gates | FileCheck %s

// Peeling `prelimhlep.lin` bodies into `hlepgate` gates. The second RUN
// line checks that the
// pass leaves its own output alone.

// Constant output bits are allocations (output side); a set bit gets an `x`.

func.func @one_state(%u : !prelimhlep.unit) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %q = prelimhlep.lin () -> (!prelimhlep.lin<i1>) {
        %one = arith.constant 1 : i1
        prelimhlep.output (%one : i1)
    }
    return %q : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @one_state
// CHECK:         [[A:%.+]] = hlepgate.alloc
// CHECK-NEXT:    [[X:%.+]] = hlepgate.single x [[A]]
// CHECK-NEXT:    return [[X]]

// Bits that are only re-bundled become rewiring: the register is joined
// from its qubits after the op, and split from its operand before it.

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
// CHECK-SAME:      [[Q0:%.+]]: !prelimhlep.lin<i1>, [[Q1:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[J:%.+]] = hlepgate.join [[Q0]], [[Q1]] : !prelimhlep.lin<i2>
// CHECK-NEXT:    return [[J]]

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
// CHECK-SAME:      [[QS:%.+]]: !prelimhlep.lin<i2>)
// CHECK-NEXT:    [[S:%.+]]:2 = hlepgate.split [[QS]] : !prelimhlep.lin<i2>
// CHECK-NEXT:    return [[S]]#0, [[S]]#1

// A permutation of whole operands is just renaming: the split/join pair
// of the passed-through register folds away, and no op survives.

func.func @swap(%a : !prelimhlep.lin<i1>, %b : !prelimhlep.lin<i2>) -> (!prelimhlep.lin<i2>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %r0, %r1 = prelimhlep.lin (
        %ab : i1 from %a : !prelimhlep.lin<i1>,
        %bb : i2 from %b : !prelimhlep.lin<i2>
    ) -> (!prelimhlep.lin<i2>, !prelimhlep.lin<i1>) {
        prelimhlep.output (%bb : i2, %ab : i1)
    }
    return %r0, %r1 : !prelimhlep.lin<i2>, !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @swap(
// CHECK-SAME:      [[A:%.+]]: !prelimhlep.lin<i1>, [[B:%.+]]: !prelimhlep.lin<i2>)
// CHECK-NEXT:    return [[B]], [[A]]

// A negated bit inside a register: split, `x` on that bit (input side),
// join.

func.func @flip_bit_1(%qs : !prelimhlep.lin<i2>) -> !prelimhlep.lin<i2> attributes { prelimhlep.halo } {
    %out = prelimhlep.lin (%bs : i2 from %qs : !prelimhlep.lin<i2>) -> (!prelimhlep.lin<i2>) {
        %two = arith.constant 2 : i2
        %flipped = arith.xori %bs, %two : i2
        prelimhlep.output (%flipped : i2)
    }
    return %out : !prelimhlep.lin<i2>
}

// CHECK-LABEL: func.func @flip_bit_1(
// CHECK-SAME:      [[QS:%.+]]: !prelimhlep.lin<i2>)
// CHECK-NEXT:    [[S:%.+]]:2 = hlepgate.split [[QS]] : !prelimhlep.lin<i2>
// CHECK-NEXT:    [[X:%.+]] = hlepgate.single x [[S]]#1
// CHECK-NEXT:    [[J:%.+]] = hlepgate.join [[S]]#0, [[X]] : !prelimhlep.lin<i2>
// CHECK-NEXT:    return [[J]]

// A conditional sub-circuit on a captured value: the nested body is peeled
// first (into `x` inside the branch), then the gate is emitted before the
// enclosing op with the condition's bit as control.

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
// CHECK-SAME:      [[C:%.+]]: !prelimhlep.lin<i1>, [[T:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[COUT:%.+]], [[TOUT:%.+]] = hlepgate.single x [[T]] ctrl([[C]])
// CHECK-NEXT:    return [[COUT]], [[TOUT]]

// A nested conditional: the inner body becomes a controlled `x`, which the
// outer body emits with its own control prepended (a Toffoli gate).

func.func @toffoli(%a : !prelimhlep.lin<i1>, %b : !prelimhlep.lin<i1>, %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %oa, %ob, %ot = prelimhlep.lin (%ab : i1 from %a : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %r:2 = scf.if %ab -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
            %nb, %nt = prelimhlep.lin (%bb : i1 from %b : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
                %new_target = scf.if %bb -> (!prelimhlep.lin<i1>) {
                    %flipped = prelimhlep.lin (%tb : i1 from %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
                        %one = arith.constant 1 : i1
                        %ntb = arith.xori %tb, %one : i1
                        prelimhlep.output (%ntb : i1)
                    }
                    scf.yield %flipped : !prelimhlep.lin<i1>
                } else {
                    scf.yield %t : !prelimhlep.lin<i1>
                }
                prelimhlep.output (%bb : i1) carrying (%new_target : !prelimhlep.lin<i1>)
            }
            scf.yield %nb, %nt : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
        } else {
            scf.yield %b, %t : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
        }
        prelimhlep.output (%ab : i1) carrying (%r#0 : !prelimhlep.lin<i1>, %r#1 : !prelimhlep.lin<i1>)
    }
    return %oa, %ob, %ot : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @toffoli(
// CHECK-SAME:      [[A:%.+]]: !prelimhlep.lin<i1>, [[B:%.+]]: !prelimhlep.lin<i1>, [[T:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[COUT:%.+]]:2, [[TOUT:%.+]] = hlepgate.single x [[T]] ctrl([[A]], [[B]])
// CHECK-NEXT:    return [[COUT]]#0, [[COUT]]#1, [[TOUT]]

// A branch holding a sequence of gates becomes one controlled gate per
// gate, threading the control through.

func.func @controlled_sequence(%control : !prelimhlep.lin<i1>, %target : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %oc, %ot = prelimhlep.lin (%cb : i1 from %control : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %new_target = scf.if %cb -> (!prelimhlep.lin<i1>) {
            %flipped = prelimhlep.lin (%tb : i1 from %target : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
                %one = arith.constant 1 : i1
                %ntb = arith.xori %tb, %one : i1
                prelimhlep.output (%ntb : i1)
            }
            %phased = prelimhlep.lin (%fb : i1 from %flipped : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
                %r = scf.if %fb -> i1 {
                    %i = complex.constant [0.0, 1.0] : complex<f64>
                    %s = prelimhlep.scale %i, %fb : (complex<f64>, i1) -> i1
                    scf.yield %s : i1
                } else {
                    scf.yield %fb : i1
                }
                prelimhlep.output (%r : i1)
            }
            scf.yield %phased : !prelimhlep.lin<i1>
        } else {
            scf.yield %target : !prelimhlep.lin<i1>
        }
        prelimhlep.output (%cb : i1) carrying (%new_target : !prelimhlep.lin<i1>)
    }
    return %oc, %ot : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @controlled_sequence(
// CHECK-SAME:      [[C:%.+]]: !prelimhlep.lin<i1>, [[T:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[C1:%.+]], [[T1:%.+]] = hlepgate.single x [[T]] ctrl([[C]])
// CHECK-NEXT:    [[ANGLE:%.+]] = arith.constant 1.5707963267948966 : f64
// CHECK-NEXT:    [[C2:%.+]], [[T2:%.+]] = hlepgate.single p([[ANGLE]]) [[T1]] ctrl([[C1]])
// CHECK-NEXT:    return [[C2]], [[T2]]

// A condition on a bit being 0 X-conjugates the control.

func.func @negative_control(%control : !prelimhlep.lin<i1>, %target : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
  %oc, %ot = prelimhlep.lin (%cb : i1 from %control : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
    %false = arith.constant false
    %is_zero = arith.cmpi eq, %cb, %false : i1
    %new_target = scf.if %is_zero -> (!prelimhlep.lin<i1>) {
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

// CHECK-LABEL: func.func @negative_control(
// CHECK-SAME:      [[C:%.+]]: !prelimhlep.lin<i1>, [[T:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[X:%.+]] = hlepgate.single x [[C]]
// CHECK-NEXT:    [[COUT:%.+]], [[TOUT:%.+]] = hlepgate.single x [[T]] ctrl([[X]])
// CHECK-NEXT:    [[UNDO:%.+]] = hlepgate.single x [[COUT]]
// CHECK-NEXT:    return [[UNDO]], [[TOUT]]

// A Hadamard inside a conditional branch is a controlled Hadamard; the
// basis changes are rewiring and are emitted as they are.

func.func @controlled_hadamard(%control : !prelimhlep.lin<i1>, %target : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
  %oc, %ot = prelimhlep.lin (%cb : i1 from %control : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
    %new_target = scf.if %cb -> (!prelimhlep.lin<i1>) {
      %x_out = prelimhlep.lin (%tb : i1 from %target : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<!prelimhlep.x<1>>) {
        %r = scf.if %tb -> !prelimhlep.x<1> {
          %m = prelimhlep.constant "-" : !prelimhlep.x<1>
          scf.yield %m : !prelimhlep.x<1>
        } else {
          %p = prelimhlep.constant "+" : !prelimhlep.x<1>
          scf.yield %p : !prelimhlep.x<1>
        }
        prelimhlep.output (%r : !prelimhlep.x<1>)
      }
      %z = prelimhlep.base_change %x_out : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<i1>
      scf.yield %z : !prelimhlep.lin<i1>
    } else {
      scf.yield %target : !prelimhlep.lin<i1>
    }
    prelimhlep.output (%cb : i1) carrying (%new_target : !prelimhlep.lin<i1>)
  }
  return %oc, %ot : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @controlled_hadamard(
// CHECK-SAME:      [[C:%.+]]: !prelimhlep.lin<i1>, [[T:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[COUT:%.+]], [[TOUT:%.+]] = hlepgate.single h [[T]] ctrl([[C]])
// CHECK-NEXT:    [[X:%.+]] = prelimhlep.base_change [[TOUT]] : !prelimhlep.lin<i1> -> !prelimhlep.lin<!prelimhlep.x<1>>
// CHECK-NEXT:    [[Z:%.+]] = prelimhlep.base_change [[X]] : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<i1>
// CHECK-NEXT:    return [[COUT]], [[Z]]

// A basis-conditional constant carries the input qubit out through `h` and
// a basis change; the swapped symbol mapping adds an `x` first, and the Y
// basis an `s` after.

func.func @hadamard(%in : !prelimhlep.lin<i1>) -> !prelimhlep.lin<!prelimhlep.x<1>> attributes { prelimhlep.halo } {
  %x_out = prelimhlep.lin (%b: i1 from %in: !prelimhlep.lin<i1>) -> (!prelimhlep.lin<!prelimhlep.x<1>>) {
    %r = scf.if %b -> !prelimhlep.x<1> {
      %m = prelimhlep.constant "-" : !prelimhlep.x<1>
      scf.yield %m : !prelimhlep.x<1>
    } else {
      %p = prelimhlep.constant "+" : !prelimhlep.x<1>
      scf.yield %p : !prelimhlep.x<1>
    }
    prelimhlep.output (%r : !prelimhlep.x<1>)
  }
  return %x_out : !prelimhlep.lin<!prelimhlep.x<1>>
}

// CHECK-LABEL: func.func @hadamard(
// CHECK-SAME:      [[IN:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[H:%.+]] = hlepgate.single h [[IN]]
// CHECK-NEXT:    [[B:%.+]] = prelimhlep.base_change [[H]] : !prelimhlep.lin<i1> -> !prelimhlep.lin<!prelimhlep.x<1>>
// CHECK-NEXT:    return [[B]]

func.func @hadamard_y_flipped(%in : !prelimhlep.lin<i1>) -> !prelimhlep.lin<!prelimhlep.y<1>> attributes { prelimhlep.halo } {
  %y_out = prelimhlep.lin (%b: i1 from %in: !prelimhlep.lin<i1>) -> (!prelimhlep.lin<!prelimhlep.y<1>>) {
    %r = scf.if %b -> !prelimhlep.y<1> {
      %p = prelimhlep.constant "->" : !prelimhlep.y<1>
      scf.yield %p : !prelimhlep.y<1>
    } else {
      %m = prelimhlep.constant "<-" : !prelimhlep.y<1>
      scf.yield %m : !prelimhlep.y<1>
    }
    prelimhlep.output (%r : !prelimhlep.y<1>)
  }
  return %y_out : !prelimhlep.lin<!prelimhlep.y<1>>
}

// CHECK-LABEL: func.func @hadamard_y_flipped(
// CHECK-SAME:      [[IN:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[X:%.+]] = hlepgate.single x [[IN]]
// CHECK-NEXT:    [[H:%.+]] = hlepgate.single h [[X]]
// CHECK-NEXT:    [[S:%.+]] = hlepgate.single s [[H]]
// CHECK-NEXT:    [[B:%.+]] = prelimhlep.base_change [[S]] : !prelimhlep.lin<i1> -> !prelimhlep.lin<!prelimhlep.y<1>>
// CHECK-NEXT:    return [[B]]

// A conditional phase on a single bit becomes `p` (or `z` for -1).

func.func @s_gate(%q : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %out = prelimhlep.lin (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %r = scf.if %b -> i1 {
            %i = complex.constant [0.0, 1.0] : complex<f64>
            %s = prelimhlep.scale %i, %b : (complex<f64>, i1) -> i1
            scf.yield %s : i1
        } else {
            scf.yield %b : i1
        }
        prelimhlep.output (%r : i1)
    }
    return %out : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @s_gate(
// CHECK-SAME:      [[Q:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[ANGLE:%.+]] = arith.constant 1.5707963267948966 : f64
// CHECK-NEXT:    [[P:%.+]] = hlepgate.single p([[ANGLE]]) [[Q]]
// CHECK-NEXT:    return [[P]]

// A multi-bit conditional phase: the last predicate bit gets the phase,
// controlled by the others, and bits whose required value is 0 are
// X-conjugated (here bit 0, since the marked state is 0b10).

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
// CHECK-SAME:      [[QS:%.+]]: !prelimhlep.lin<i2>)
// CHECK-NEXT:    [[S:%.+]]:2 = hlepgate.split [[QS]] : !prelimhlep.lin<i2>
// CHECK-NEXT:    [[X0:%.+]] = hlepgate.single x [[S]]#0
// CHECK-NEXT:    [[COUT:%.+]], [[TOUT:%.+]] = hlepgate.single z [[S]]#1 ctrl([[X0]])
// CHECK-NEXT:    [[UNDO:%.+]] = hlepgate.single x [[COUT]]
// CHECK-NEXT:    [[J:%.+]] = hlepgate.join [[UNDO]], [[TOUT]] : !prelimhlep.lin<i2>
// CHECK-NEXT:    return [[J]]

// Classical carried results measure the bits they depend on (input side,
// keeping the qubit); the classical value is rebuilt from the outcomes.
// Measured qubits nothing uses anymore are sunk right after measurement.

func.func @measure_2(%state : !prelimhlep.lin<i2>) -> i2 attributes { prelimhlep.halo } {
    %result = prelimhlep.lin (%bits : i2 from %state : !prelimhlep.lin<i2>) -> (i2) {
        prelimhlep.output () carrying (%bits : i2)
    }
    return %result : i2
}

// CHECK-LABEL: func.func @measure_2(
// CHECK-SAME:      [[QS:%.+]]: !prelimhlep.lin<i2>)
// CHECK-NEXT:    [[S:%.+]]:2 = hlepgate.split [[QS]] : !prelimhlep.lin<i2>
// CHECK-NEXT:    [[Q0:%.+]], [[B0:%.+]] = hlepgate.measure [[S]]#0
// CHECK-NEXT:    hlepgate.sink [[Q0]]
// CHECK-NEXT:    [[Q1:%.+]], [[B1:%.+]] = hlepgate.measure [[S]]#1
// CHECK-NEXT:    hlepgate.sink [[Q1]]
// CHECK-DAG:     arith.extui [[B0]] : i1 to i2
// CHECK-DAG:     [[E1:%.+]] = arith.extui [[B1]] : i1 to i2
// CHECK:         arith.shli [[E1]],
// CHECK:         [[R:%.+]] = arith.ori
// CHECK-NEXT:    return [[R]]

func.func @measure_and_keep(%qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) attributes { prelimhlep.halo } {
    %q, %bit = prelimhlep.lin (%b : i1 from %qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
        prelimhlep.output (%b : i1) carrying (%b : i1)
    }
    return %q, %bit : !prelimhlep.lin<i1>, i1
}

// CHECK-LABEL: func.func @measure_and_keep(
// CHECK-SAME:      [[Q:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[MQ:%.+]], [[B:%.+]] = hlepgate.measure [[Q]]
// CHECK-NEXT:    return [[MQ]], [[B]]

// A body that carries a bit and also applies a Hadamard to it measures the
// bit first: measurements are peeled before conditionals.

func.func @measure_then_hadamard(%in : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<!prelimhlep.x<1>>, i1) attributes { prelimhlep.halo } {
  %x_out, %m = prelimhlep.lin (%b: i1 from %in: !prelimhlep.lin<i1>) -> (!prelimhlep.lin<!prelimhlep.x<1>>, i1) {
    %r = scf.if %b -> !prelimhlep.x<1> {
      %minus = prelimhlep.constant "-" : !prelimhlep.x<1>
      scf.yield %minus : !prelimhlep.x<1>
    } else {
      %plus = prelimhlep.constant "+" : !prelimhlep.x<1>
      scf.yield %plus : !prelimhlep.x<1>
    }
    prelimhlep.output (%r : !prelimhlep.x<1>) carrying (%b : i1)
  }
  return %x_out, %m : !prelimhlep.lin<!prelimhlep.x<1>>, i1
}

// CHECK-LABEL: func.func @measure_then_hadamard(
// CHECK-SAME:      [[IN:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[MQ:%.+]], [[M:%.+]] = hlepgate.measure [[IN]]
// CHECK-NEXT:    [[H:%.+]] = hlepgate.single h [[MQ]]
// CHECK-NEXT:    [[B:%.+]] = prelimhlep.base_change [[H]]
// CHECK-NEXT:    return [[B]], [[M]]

// A measured qubit that went through diagonal gates is still in a basis
// state and may be discarded: it is measured again (with a known outcome)
// and sunk.

func.func @measure_phase_forget(%in : !prelimhlep.lin<i1>) -> i1 attributes { prelimhlep.halo } {
  %m = prelimhlep.lin (%b : i1 from %in : !prelimhlep.lin<i1>) -> (i1) {
    %r = scf.if %b -> i1 {
      %i = complex.constant [0.0, 1.0] : complex<f64>
      %s = prelimhlep.scale %i, %b : (complex<f64>, i1) -> i1
      scf.yield %s : i1
    } else {
      scf.yield %b : i1
    }
    prelimhlep.output () carrying (%r : i1)
  }
  return %m : i1
}

// CHECK-LABEL: func.func @measure_phase_forget(
// CHECK-SAME:      [[IN:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[MQ:%.+]], [[M:%.+]] = hlepgate.measure [[IN]]
// CHECK-NEXT:    [[ANGLE:%.+]] = arith.constant
// CHECK-NEXT:    [[P:%.+]] = hlepgate.single p([[ANGLE]]) [[MQ]]
// CHECK-NEXT:    [[MQ2:%.+]], {{%.+}} = hlepgate.measure [[P]]
// CHECK-NEXT:    hlepgate.sink [[MQ2]]
// CHECK-NEXT:    return [[M]]

// A `lin` op nested at body level acts on the captured factor only: its
// gates are hoisted out of the enclosing op.

func.func @hoist(%control : !prelimhlep.lin<i1>, %other : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %oc, %oo = prelimhlep.lin (%cb : i1 from %control : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %flipped = prelimhlep.lin (%ob : i1 from %other : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
            %one = arith.constant 1 : i1
            %nob = arith.xori %ob, %one : i1
            prelimhlep.output (%nob : i1)
        }
        prelimhlep.output (%cb : i1) carrying (%flipped : !prelimhlep.lin<i1>)
    }
    return %oc, %oo : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @hoist(
// CHECK-SAME:      [[C:%.+]]: !prelimhlep.lin<i1>, [[O:%.+]]: !prelimhlep.lin<i1>)
// CHECK-NEXT:    [[X:%.+]] = hlepgate.single x [[O]]
// CHECK-NEXT:    return [[C]], [[X]]
