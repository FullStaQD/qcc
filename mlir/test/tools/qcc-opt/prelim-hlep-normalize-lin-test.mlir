// RUN: qcc-opt %s --prelim-hlep-normalize-lin | FileCheck %s
// RUN: qcc-opt %s --prelim-hlep-normalize-lin --prelim-hlep-normalize-lin | FileCheck %s

// Decomposition of general `prelimhlep.lin` bodies into the tagged
// normal-form shapes (see "Normal form of `lin` ops" in the design doc).
// The second RUN line checks that the pass is idempotent: tagged ops are
// left alone.

// Constant bits become allocations; |1> is an allocation followed by `x`.

func.func @one_state(%u : !prelimhlep.unit) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %q = prelimhlep.lin () -> (!prelimhlep.lin<i1>) {
        %one = arith.constant 1 : i1
        prelimhlep.output (%one : i1)
    }
    return %q : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @one_state
// CHECK:         [[A:%.+]] = prelimhlep.lin alloc () -> (!prelimhlep.lin<i1>) {
// CHECK-NEXT:      [[ZERO:%.+]] = arith.constant false
// CHECK-NEXT:      prelimhlep.output ([[ZERO]] : i1)
// CHECK-NEXT:    }
// CHECK-NEXT:    [[X:%.+]] = prelimhlep.lin x ([[B:%.+]] : i1 from [[A]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
// CHECK-NEXT:      [[ONE:%.+]] = arith.constant true
// CHECK-NEXT:      [[NB:%.+]] = arith.xori [[B]], [[ONE]] : i1
// CHECK-NEXT:      prelimhlep.output ([[NB]] : i1)
// CHECK-NEXT:    }
// CHECK-NEXT:    return [[X]]

// A body that only re-bundles bits becomes `join`; the inverse becomes
// `split`. Both are least-significant bit first.

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
// CHECK:         [[J:%.+]] = prelimhlep.lin join ([[B0:%.+]] : i1 from [[Q0]] : !prelimhlep.lin<i1>, [[B1:%.+]] : i1 from [[Q1]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i2>) {
// CHECK-NEXT:      [[E0:%.+]] = arith.extui [[B0]] : i1 to i2
// CHECK-NEXT:      [[E1:%.+]] = arith.extui [[B1]] : i1 to i2
// CHECK-NEXT:      [[C1:%.+]] = arith.constant 1 : i2
// CHECK-NEXT:      [[S1:%.+]] = arith.shli [[E1]], [[C1]] : i2
// CHECK-NEXT:      [[OR:%.+]] = arith.ori [[E0]], [[S1]] : i2
// CHECK-NEXT:      prelimhlep.output ([[OR]] : i2)
// CHECK-NEXT:    }
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
// CHECK:         [[S:%.+]]:2 = prelimhlep.lin split ([[BS:%.+]] : i2 from [[QS]] : !prelimhlep.lin<i2>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
// CHECK-NEXT:      [[B0:%.+]] = arith.trunci [[BS]] : i2 to i1
// CHECK-NEXT:      [[C1:%.+]] = arith.constant 1 : i2
// CHECK-NEXT:      [[HS:%.+]] = arith.shrui [[BS]], [[C1]] : i2
// CHECK-NEXT:      [[B1:%.+]] = arith.trunci [[HS]] : i2 to i1
// CHECK-NEXT:      prelimhlep.output ([[B0]] : i1, [[B1]] : i1)
// CHECK-NEXT:    }
// CHECK-NEXT:    return [[S]]#0, [[S]]#1

// A pure permutation of whole operands is just renaming: no op survives.

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

// A negated bit inside a register: split, `x` on that bit, join.

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
// CHECK:         [[S:%.+]]:2 = prelimhlep.lin split ({{.*}} from [[QS]]
// CHECK:         [[X:%.+]] = prelimhlep.lin x ({{.*}} from [[S]]#1
// CHECK:         [[J:%.+]] = prelimhlep.lin join ({{.*}} from [[S]]#0 : !prelimhlep.lin<i1>, {{.*}} from [[X]] : !prelimhlep.lin<i1>)
// CHECK:         return [[J]]

// A conditional negation of a captured value: the nested body is
// normalized first (into `x`), then the enclosing body re-emits it under
// `ctrl`.

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
// CHECK:         [[R:%.+]]:2 = prelimhlep.lin ctrl ([[CB:%.+]] : i1 from [[C]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
// CHECK-NEXT:      [[NT:%.+]] = scf.if [[CB]] -> (!prelimhlep.lin<i1>) {
// CHECK-NEXT:        [[G:%.+]] = prelimhlep.lin x ({{.*}} : i1 from [[T]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
// CHECK:             scf.yield [[G]]
// CHECK-NEXT:      } else {
// CHECK-NEXT:        scf.yield [[T]]
// CHECK-NEXT:      }
// CHECK-NEXT:      prelimhlep.output ([[CB]] : i1) carrying ([[NT]] : !prelimhlep.lin<i1>)
// CHECK-NEXT:    }
// CHECK-NEXT:    return [[R]]#0, [[R]]#1

// A nested conditional: the inner body becomes a `ctrl`, which the outer
// body re-emits with its own control prepended (a Toffoli gate).

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
// CHECK:         [[R:%.+]]:3 = prelimhlep.lin ctrl ([[AB:%.+]] : i1 from [[A]] : !prelimhlep.lin<i1>, [[BB:%.+]] : i1 from [[B]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
// CHECK-NEXT:      [[COND:%.+]] = arith.andi [[AB]], [[BB]] : i1
// CHECK-NEXT:      [[NT:%.+]] = scf.if [[COND]] -> (!prelimhlep.lin<i1>) {
// CHECK-NEXT:        prelimhlep.lin x ({{.*}} : i1 from [[T]] : !prelimhlep.lin<i1>)
// CHECK:           } else {
// CHECK-NEXT:        scf.yield [[T]]
// CHECK-NEXT:      }
// CHECK-NEXT:      prelimhlep.output ([[AB]] : i1, [[BB]] : i1) carrying ([[NT]] : !prelimhlep.lin<i1>)
// CHECK-NEXT:    }
// CHECK-NEXT:    return [[R]]#0, [[R]]#1, [[R]]#2

// A conditional branch holding a sequence of gates is re-emitted one
// `ctrl` per gate, threading the control through.

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
// CHECK:         [[CX:%.+]]:2 = prelimhlep.lin ctrl ({{.*}} : i1 from [[C]] : !prelimhlep.lin<i1>)
// CHECK:             prelimhlep.lin x ({{.*}} : i1 from [[T]] : !prelimhlep.lin<i1>)
// CHECK:         [[CP:%.+]]:2 = prelimhlep.lin ctrl ({{.*}} : i1 from [[CX]]#0 : !prelimhlep.lin<i1>)
// CHECK:             prelimhlep.lin phase ({{.*}} : i1 from [[CX]]#1 : !prelimhlep.lin<i1>)
// CHECK:         return [[CP]]#0, [[CP]]#1

// A basis-conditional constant becomes `hadamard`; the swapped symbol
// mapping is `x` followed by `hadamard`.

func.func @hadamard(%in : !prelimhlep.lin<i1>) -> !prelimhlep.lin<!prelimhlep.x<1>> attributes { prelimhlep.halo } {
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
  return %x_out : !prelimhlep.lin<!prelimhlep.x<1>>
}

// CHECK-LABEL: func.func @hadamard(
// CHECK-SAME:      [[IN:%.+]]: !prelimhlep.lin<i1>)
// CHECK:         [[H:%.+]] = prelimhlep.lin hadamard ([[B:%.+]] : i1 from [[IN]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<!prelimhlep.x<1>>) {
// CHECK-NEXT:      [[R:%.+]] = scf.if [[B]] -> (!prelimhlep.lin<!prelimhlep.x<1>>) {
// CHECK-NEXT:        [[M:%.+]] = prelimhlep.constant "-"
// CHECK-NEXT:        scf.yield [[M]]
// CHECK-NEXT:      } else {
// CHECK-NEXT:        [[P:%.+]] = prelimhlep.constant "+"
// CHECK-NEXT:        scf.yield [[P]]
// CHECK-NEXT:      }
// CHECK-NEXT:      prelimhlep.output () carrying ([[R]] : !prelimhlep.lin<!prelimhlep.x<1>>)
// CHECK-NEXT:    }
// CHECK-NEXT:    return [[H]]

func.func @hadamard_y_flipped(%in : !prelimhlep.lin<i1>) -> !prelimhlep.lin<!prelimhlep.y<1>> attributes { prelimhlep.halo } {
  %y_out = prelimhlep.lin (%b: i1 from %in: !prelimhlep.lin<i1>) -> (!prelimhlep.lin<!prelimhlep.y<1>>) {
    %r = scf.if %b -> !prelimhlep.lin<!prelimhlep.y<1>> {
      %p = prelimhlep.constant "->" : !prelimhlep.lin<!prelimhlep.y<1>>
      scf.yield %p : !prelimhlep.lin<!prelimhlep.y<1>>
    } else {
      %m = prelimhlep.constant "<-" : !prelimhlep.lin<!prelimhlep.y<1>>
      scf.yield %m : !prelimhlep.lin<!prelimhlep.y<1>>
    }
    prelimhlep.output () carrying (%r : !prelimhlep.lin<!prelimhlep.y<1>>)
  }
  return %y_out : !prelimhlep.lin<!prelimhlep.y<1>>
}

// CHECK-LABEL: func.func @hadamard_y_flipped(
// CHECK-SAME:      [[IN:%.+]]: !prelimhlep.lin<i1>)
// CHECK:         [[X:%.+]] = prelimhlep.lin x ({{.*}} from [[IN]]
// CHECK:         [[H:%.+]] = prelimhlep.lin hadamard ({{.*}} from [[X]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<!prelimhlep.y<1>>) {
// CHECK:             prelimhlep.constant "<-"
// CHECK:           } else {
// CHECK-NEXT:        prelimhlep.constant "->"
// CHECK:         return [[H]]

// A conditional phase on a single bit becomes `phase`.

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
// CHECK:         [[P:%.+]] = prelimhlep.lin phase ([[B:%.+]] : i1 from [[Q]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
// CHECK-NEXT:      [[R:%.+]] = scf.if [[B]] -> (i1) {
// CHECK-NEXT:        [[I:%.+]] = complex.constant [0.000000e+00, 1.000000e+00] : complex<f64>
// CHECK-NEXT:        [[S:%.+]] = prelimhlep.scale [[I]], [[B]] : (complex<f64>, i1) -> i1
// CHECK-NEXT:        scf.yield [[S]]
// CHECK-NEXT:      } else {
// CHECK-NEXT:        scf.yield [[B]]
// CHECK-NEXT:      }
// CHECK-NEXT:      prelimhlep.output ([[R]] : i1)
// CHECK-NEXT:    }
// CHECK-NEXT:    return [[P]]

// A multi-bit conditional phase: the register is split, the last predicate
// bit gets the `phase` under `ctrl` of the others, and bits whose required
// value is 0 are X-conjugated (here bit 0, since the marked state is 0b10).

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
// CHECK-SAME:      [[STATE:%.+]]: !prelimhlep.lin<i2>)
// CHECK:         [[S:%.+]]:2 = prelimhlep.lin split ({{.*}} from [[STATE]]
// CHECK:         [[X0:%.+]] = prelimhlep.lin x ({{.*}} from [[S]]#0
// CHECK:         [[CZ:%.+]]:2 = prelimhlep.lin ctrl ({{.*}} : i1 from [[X0]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
// CHECK:             prelimhlep.lin phase ({{.*}} : i1 from [[S]]#1 : !prelimhlep.lin<i1>)
// CHECK:                 complex.constant [-1.000000e+00, 0.000000e+00]
// CHECK:           scf.yield [[S]]#1
// CHECK:         [[UNDO:%.+]] = prelimhlep.lin x ({{.*}} from [[CZ]]#0
// CHECK:         [[J:%.+]] = prelimhlep.lin join ({{.*}} from [[UNDO]] : !prelimhlep.lin<i1>, {{.*}} from [[CZ]]#1 : !prelimhlep.lin<i1>)
// CHECK:         return [[J]]

// Classical auxiliary results measure the bits they depend on. A bit that
// is not re-output uses `measure_drop`; the classical register is rebuilt
// from the outcomes.

func.func @measure_2(%state : !prelimhlep.lin<i2>) -> i2 attributes { prelimhlep.halo } {
    %result = prelimhlep.lin (%bits : i2 from %state : !prelimhlep.lin<i2>) -> (i2) {
        prelimhlep.output () carrying (%bits : i2)
    }
    return %result : i2
}

// CHECK-LABEL: func.func @measure_2(
// CHECK-SAME:      [[STATE:%.+]]: !prelimhlep.lin<i2>)
// CHECK:         [[S:%.+]]:2 = prelimhlep.lin split ({{.*}} from [[STATE]]
// CHECK:         [[M0:%.+]] = prelimhlep.lin measure_drop ([[B0:%.+]] : i1 from [[S]]#0 : !prelimhlep.lin<i1>) -> (i1) {
// CHECK-NEXT:      prelimhlep.output () carrying ([[B0]] : i1)
// CHECK-NEXT:    }
// CHECK-NEXT:    [[M1:%.+]] = prelimhlep.lin measure_drop ({{.*}} from [[S]]#1
// CHECK:         [[E0:%.+]] = arith.extui [[M0]] : i1 to i2
// CHECK:         [[E1:%.+]] = arith.extui [[M1]] : i1 to i2
// CHECK:         [[RES:%.+]] = arith.ori
// CHECK-NEXT:    return [[RES]] : i2

func.func @measure_and_keep(%qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) attributes { prelimhlep.halo } {
    %q, %bit = prelimhlep.lin (%b : i1 from %qubit : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
        prelimhlep.output (%b : i1) carrying (%b : i1)
    }
    return %q, %bit : !prelimhlep.lin<i1>, i1
}

// CHECK-LABEL: func.func @measure_and_keep(
// CHECK-SAME:      [[Q:%.+]]: !prelimhlep.lin<i1>)
// CHECK:         [[M:%.+]]:2 = prelimhlep.lin measure ([[B:%.+]] : i1 from [[Q]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
// CHECK-NEXT:      prelimhlep.output ([[B]] : i1) carrying ([[B]] : i1)
// CHECK-NEXT:    }
// CHECK-NEXT:    return [[M]]#0, [[M]]#1

// A tagged op nested at body level acts on the captured factor only and
// is hoisted out unchanged.

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
// CHECK-NEXT:    [[X:%.+]] = prelimhlep.lin x ({{.*}} from [[O]]
// CHECK:         return [[C]], [[X]]
