// RUN: qcc-opt %s --split-input-file --prelim-hlep-merge-lin | FileCheck %s
// RUN: qcc-opt %s --split-input-file --prelim-hlep-merge-lin=promote-captures=false | FileCheck %s --check-prefix=NOPROMOTE

// Merging chains of `prelimhlep.lin` ops, followed by classical
// simplification of the merged bodies.

// X X cancels: the merged body is `xori(xori(%b, 1), 1)`, which folds to `%b`,
// leaving a passthrough wire that is peeled off.

func.func @x_x(%q : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %q1 = prelimhlep.lin (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant 1 : i1
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    %q2 = prelimhlep.lin (%b : i1 from %q1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant 1 : i1
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    return %q2 : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @x_x(
// CHECK-SAME:      [[Q:%.+]]: !prelimhlep.lin<i1>
// CHECK-NOT:     prelimhlep.lin{{ }}
// CHECK:         return [[Q]]

// -----

// X X X leaves a single X.

func.func @x_x_x(%q : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %q1 = prelimhlep.lin (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant true
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    %q2 = prelimhlep.lin (%b : i1 from %q1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant true
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    %q3 = prelimhlep.lin (%b : i1 from %q2 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant true
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    return %q3 : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @x_x_x(
// CHECK-SAME:      [[Q:%.+]]: !prelimhlep.lin<i1>
// CHECK:         [[ONE:%.+]] = arith.constant true
// CHECK:         [[R:%.+]] = prelimhlep.lin ([[B:%.+]] : i1 from [[Q]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
// CHECK-NEXT:      [[NB:%.+]] = arith.xori [[B]], [[ONE]] : i1
// CHECK-NEXT:      prelimhlep.output ([[NB]] : i1)
// CHECK-NEXT:    }
// CHECK-NEXT:    return [[R]]

// -----

// CX CX cancels, with CX written as a controlled sub-circuit: the target is
// captured, and X is applied to it in an `scf.if` branch.

func.func private @cx(%c : !prelimhlep.lin<i1>, %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %c1, %t1 = prelimhlep.lin (%cb : i1 from %c : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %r = scf.if %cb -> (!prelimhlep.lin<i1>) {
            %x = prelimhlep.lin (%tb : i1 from %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
                %one = arith.constant true
                %ntb = arith.xori %tb, %one : i1
                prelimhlep.output (%ntb : i1)
            }
            scf.yield %x : !prelimhlep.lin<i1>
        } else {
            scf.yield %t : !prelimhlep.lin<i1>
        }
        prelimhlep.output (%cb : i1) carrying (%r : !prelimhlep.lin<i1>)
    }
    return %c1, %t1 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

func.func @cx_cx(%c : !prelimhlep.lin<i1>, %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %c1, %t1 = prelimhlep.lin (%cb : i1 from %c : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %r = scf.if %cb -> (!prelimhlep.lin<i1>) {
            %x = prelimhlep.lin (%tb : i1 from %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
                %one = arith.constant true
                %ntb = arith.xori %tb, %one : i1
                prelimhlep.output (%ntb : i1)
            }
            scf.yield %x : !prelimhlep.lin<i1>
        } else {
            scf.yield %t : !prelimhlep.lin<i1>
        }
        prelimhlep.output (%cb : i1) carrying (%r : !prelimhlep.lin<i1>)
    }
    %c2, %t2 = prelimhlep.lin (%cb : i1 from %c1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %r = scf.if %cb -> (!prelimhlep.lin<i1>) {
            %x = prelimhlep.lin (%tb : i1 from %t1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
                %one = arith.constant true
                %ntb = arith.xori %tb, %one : i1
                prelimhlep.output (%ntb : i1)
            }
            scf.yield %x : !prelimhlep.lin<i1>
        } else {
            scf.yield %t1 : !prelimhlep.lin<i1>
        }
        prelimhlep.output (%cb : i1) carrying (%r : !prelimhlep.lin<i1>)
    }
    return %c2, %t2 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// A single CX has its target promoted to a delinearized operand: the nested
// X is inlined, which turns the body into a classical function.

// CHECK-LABEL: func.func private @cx(
// CHECK-SAME:      [[C:%.+]]: !prelimhlep.lin<i1>, [[T:%.+]]: !prelimhlep.lin<i1>
// CHECK:         [[ONE:%.+]] = arith.constant true
// CHECK:         [[R:%.+]]:2 = prelimhlep.lin ([[CB:%.+]] : i1 from [[C]] : !prelimhlep.lin<i1>, [[TB:%.+]] : i1 from [[T]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
// CHECK-NEXT:      [[NT:%.+]] = scf.if [[CB]] -> (i1) {
// CHECK-NEXT:        [[X:%.+]] = arith.xori [[TB]], [[ONE]] : i1
// CHECK-NEXT:        scf.yield [[X]] : i1
// CHECK-NEXT:      } else {
// CHECK-NEXT:        scf.yield [[TB]] : i1
// CHECK-NEXT:      }
// CHECK-NEXT:      prelimhlep.output ([[CB]] : i1, [[NT]] : i1)
// CHECK-NEXT:    }
// CHECK-NEXT:    return [[R]]#0, [[R]]#1

// NOPROMOTE-LABEL: func.func private @cx(
// NOPROMOTE:         prelimhlep.lin ({{.*}}) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
// NOPROMOTE-NEXT:      scf.if {{.*}} -> (!prelimhlep.lin<i1>) {
// NOPROMOTE-NEXT:        prelimhlep.lin

// CHECK-LABEL: func.func @cx_cx(
// CHECK-SAME:      [[C:%.+]]: !prelimhlep.lin<i1>, [[T:%.+]]: !prelimhlep.lin<i1>
// CHECK-NOT:     prelimhlep.lin{{ }}
// CHECK:         return [[C]], [[T]]

// Without promotion, the ifs are combined and the nested X X cancel.

// NOPROMOTE-LABEL: func.func @cx_cx(
// NOPROMOTE-SAME:      [[C:%.+]]: !prelimhlep.lin<i1>, [[T:%.+]]: !prelimhlep.lin<i1>
// NOPROMOTE-NOT:     prelimhlep.lin{{ }}
// NOPROMOTE:         return [[C]], [[T]]

// -----

// CX CX cancels, with CX written as a classical function of both bits.

func.func @cx_cx_classical(%c : !prelimhlep.lin<i1>, %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %c1, %t1 = prelimhlep.lin (%cb : i1 from %c : !prelimhlep.lin<i1>, %tb : i1 from %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %ntb = arith.xori %tb, %cb : i1
        prelimhlep.output (%cb : i1, %ntb : i1)
    }
    %c2, %t2 = prelimhlep.lin (%cb : i1 from %c1 : !prelimhlep.lin<i1>, %tb : i1 from %t1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %ntb = arith.xori %tb, %cb : i1
        prelimhlep.output (%cb : i1, %ntb : i1)
    }
    return %c2, %t2 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @cx_cx_classical(
// CHECK-SAME:      [[C:%.+]]: !prelimhlep.lin<i1>, [[T:%.+]]: !prelimhlep.lin<i1>
// CHECK-NOT:     prelimhlep.lin{{ }}
// CHECK:         return [[C]], [[T]]

// -----

// CX X_target CX = X_target. The merged body is an `xori` chain in which the
// control cancels.

func.func @cx_x_cx(%c : !prelimhlep.lin<i1>, %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %c1, %t1 = prelimhlep.lin (%cb : i1 from %c : !prelimhlep.lin<i1>, %tb : i1 from %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %ntb = arith.xori %tb, %cb : i1
        prelimhlep.output (%cb : i1, %ntb : i1)
    }
    %t2 = prelimhlep.lin (%tb : i1 from %t1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant true
        %ntb = arith.xori %tb, %one : i1
        prelimhlep.output (%ntb : i1)
    }
    %c3, %t3 = prelimhlep.lin (%cb : i1 from %c1 : !prelimhlep.lin<i1>, %tb : i1 from %t2 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %ntb = arith.xori %tb, %cb : i1
        prelimhlep.output (%cb : i1, %ntb : i1)
    }
    return %c3, %t3 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @cx_x_cx(
// CHECK-SAME:      [[C:%.+]]: !prelimhlep.lin<i1>, [[T:%.+]]: !prelimhlep.lin<i1>
// CHECK:         [[ONE:%.+]] = arith.constant true
// CHECK:         [[R:%.+]] = prelimhlep.lin ([[TB:%.+]] : i1 from [[T]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
// CHECK-NEXT:      [[NT:%.+]] = arith.xori [[TB]], [[ONE]] : i1
// CHECK-NEXT:      prelimhlep.output ([[NT]] : i1)
// CHECK-NEXT:    }
// CHECK-NEXT:    return [[C]], [[R]]

// -----

// Gates on unrelated qubits stay separate.

func.func @unrelated(%q0 : !prelimhlep.lin<i1>, %q1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %r0 = prelimhlep.lin (%b : i1 from %q0 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant true
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    %r1 = prelimhlep.lin (%b : i1 from %q1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant true
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    return %r0, %r1 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @unrelated(
// CHECK-SAME:      [[Q0:%.+]]: !prelimhlep.lin<i1>, [[Q1:%.+]]: !prelimhlep.lin<i1>
// CHECK:         [[R0:%.+]] = prelimhlep.lin ({{.*}} from [[Q0]] : !prelimhlep.lin<i1>)
// CHECK:         [[R1:%.+]] = prelimhlep.lin ({{.*}} from [[Q1]] : !prelimhlep.lin<i1>)
// CHECK:         return [[R0]], [[R1]]

// -----

// Measuring a qubit that was flipped from |0> is deterministic: the
// measurement result becomes a constant, and the whole circuit disappears.

func.func @measure_one(%u : !prelimhlep.unit) -> i1 attributes { prelimhlep.halo } {
    %q = prelimhlep.lin () -> (!prelimhlep.lin<i1>) {
        %zero = arith.constant false
        prelimhlep.output (%zero : i1)
    }
    %q1 = prelimhlep.lin (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant true
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    %m = prelimhlep.lin (%b : i1 from %q1 : !prelimhlep.lin<i1>) -> (i1) {
        prelimhlep.output () carrying (%b : i1)
    }
    return %m : i1
}

// CHECK-LABEL: func.func @measure_one(
// CHECK:         [[TRUE:%.+]] = arith.constant true
// CHECK-NOT:     prelimhlep.lin{{ }}
// CHECK:         return [[TRUE]]

// -----

// Measurement results of the first op stay results of the merged op, even if
// the second op uses them. Here a measured qubit is reset via a classically
// controlled X.

func.func @measure_reset(%q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) attributes { prelimhlep.halo } {
    %q1, %m = prelimhlep.lin (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
        prelimhlep.output (%b : i1) carrying (%b : i1)
    }
    %q2 = prelimhlep.lin (%b : i1 from %q1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %nb = arith.xori %b, %m : i1
        prelimhlep.output (%nb : i1)
    }
    return %q2, %m : !prelimhlep.lin<i1>, i1
}

// CHECK-LABEL: func.func @measure_reset(
// CHECK-SAME:      [[Q:%.+]]: !prelimhlep.lin<i1>
// CHECK:         [[FALSE:%.+]] = arith.constant false
// CHECK:         [[R:%.+]]:2 = prelimhlep.lin ([[B:%.+]] : i1 from [[Q]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
// CHECK-NEXT:      prelimhlep.output ([[FALSE]] : i1) carrying ([[B]] : i1)
// CHECK-NEXT:    }
// CHECK-NEXT:    return [[R]]#0, [[R]]#1

// -----

// Deleting a qubit (delinearizing without outputting) is not a no-op; the
// argument is kept.

func.func @flip_and_delete(%q : !prelimhlep.lin<i1>, %u : !prelimhlep.unit) -> !prelimhlep.unit attributes { prelimhlep.halo } {
    %q1 = prelimhlep.lin (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant true
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    prelimhlep.lin (%b : i1 from %q1 : !prelimhlep.lin<i1>) -> () {
        prelimhlep.output ()
    }
    return %u : !prelimhlep.unit
}

// CHECK-LABEL: func.func @flip_and_delete(
// CHECK-SAME:      [[Q:%.+]]: !prelimhlep.lin<i1>
// CHECK:         prelimhlep.lin ({{.*}} : i1 from [[Q]] : !prelimhlep.lin<i1>) -> () {
// CHECK-NEXT:      prelimhlep.output ()
// CHECK-NEXT:    }

// -----

// A measurement nested in a body is not inlined by promotion: it would turn
// into a coherent control. The captured qubit stays captured.

func.func @nested_measurement(%c : !prelimhlep.lin<i1>, %t : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) attributes { prelimhlep.halo } {
    %c1, %m = prelimhlep.lin (%cb : i1 from %c : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
        %mt = prelimhlep.lin (%tb : i1 from %t : !prelimhlep.lin<i1>) -> (i1) {
            prelimhlep.output () carrying (%tb : i1)
        }
        %ncb = arith.xori %cb, %mt : i1
        prelimhlep.output (%ncb : i1) carrying (%mt : i1)
    }
    return %c1, %m : !prelimhlep.lin<i1>, i1
}

// CHECK-LABEL: func.func @nested_measurement(
// CHECK-SAME:      [[C:%.+]]: !prelimhlep.lin<i1>, [[T:%.+]]: !prelimhlep.lin<i1>
// CHECK:         prelimhlep.lin ({{.*}} : i1 from [[C]] : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
// CHECK-NEXT:      prelimhlep.lin ({{.*}} : i1 from [[T]] : !prelimhlep.lin<i1>)

// -----

// The merged op is placed at the producer when a measurement result of the
// producer is used between the two ops.

func.func private @use(%m : i1) -> i1

func.func @place_at_producer(%q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) attributes { prelimhlep.halo } {
    %q1, %m = prelimhlep.lin (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
        prelimhlep.output (%b : i1) carrying (%b : i1)
    }
    %m2 = func.call @use(%m) : (i1) -> i1
    %q2 = prelimhlep.lin (%b : i1 from %q1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant true
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%nb : i1)
    }
    return %q2, %m2 : !prelimhlep.lin<i1>, i1
}

// CHECK-LABEL: func.func @place_at_producer(
// CHECK:         [[R:%.+]]:2 = prelimhlep.lin
// CHECK:         [[M2:%.+]] = call @use([[R]]#1)
// CHECK-NOT:     prelimhlep.lin{{ }}
// CHECK:         return [[R]]#0, [[M2]]

// -----

// Neither placement works: the consumer uses a value computed from the
// producer's measurement result.

func.func private @use(%m : i1) -> i1

func.func @no_placement(%q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    %q1, %m = prelimhlep.lin (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
        prelimhlep.output (%b : i1) carrying (%b : i1)
    }
    %m2 = func.call @use(%m) : (i1) -> i1
    %q2 = prelimhlep.lin (%b : i1 from %q1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %nb = arith.xori %b, %m2 : i1
        prelimhlep.output (%nb : i1)
    }
    return %q2 : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @no_placement(
// CHECK:         prelimhlep.lin
// CHECK:         call @use
// CHECK:         prelimhlep.lin
