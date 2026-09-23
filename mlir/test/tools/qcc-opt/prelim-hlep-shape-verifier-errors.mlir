// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// A shape tag is a claim about the body that the verifier checks (see
// "Normal form of `lin` ops" in the design doc).

func.func @alloc_one(%u : !prelimhlep.unit) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'alloc' but delinearized output #0 does not compute the expected bits}}
    %q = prelimhlep.lin alloc () -> (!prelimhlep.lin<i1>) {
        %one = arith.constant true
        prelimhlep.output (%one : i1)
    }
    return %q : !prelimhlep.lin<i1>
}

// -----

func.func @x_identity(%q : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'x' but delinearized output #0 does not compute the expected bits}}
    %out = prelimhlep.lin x (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        prelimhlep.output (%b : i1)
    }
    return %out : !prelimhlep.lin<i1>
}

// -----

func.func @x_wide(%q : !prelimhlep.lin<i2>) -> !prelimhlep.lin<i2> attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'x' but has a delinearized operand of type '!prelimhlep.lin<i2>', expected '!prelimhlep.lin<i1>'}}
    %out = prelimhlep.lin x (%b : i2 from %q : !prelimhlep.lin<i2>) -> (!prelimhlep.lin<i2>) {
        %c = arith.constant 3 : i2
        %nb = arith.xori %b, %c : i2
        prelimhlep.output (%nb : i2)
    }
    return %out : !prelimhlep.lin<i2>
}

// -----

func.func @x_foreign_op(%q : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %out = prelimhlep.lin x (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %one = arith.constant true
        // expected-error @below {{'arith.select' op is not allowed in the body of a 'x'-shaped 'prelimhlep.lin'}}
        %nb = arith.select %b, %one, %one : i1
        prelimhlep.output (%nb : i1)
    }
    return %out : !prelimhlep.lin<i1>
}

// -----

func.func @split_swapped(%qs : !prelimhlep.lin<i2>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'split' but delinearized output #0 does not compute the expected bits}}
    %q0, %q1 = prelimhlep.lin split (%bs : i2 from %qs : !prelimhlep.lin<i2>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %c1 = arith.constant 1 : i2
        %b0 = arith.trunci %bs : i2 to i1
        %hs = arith.shrui %bs, %c1 : i2
        %b1 = arith.trunci %hs : i2 to i1
        prelimhlep.output (%b1 : i1, %b0 : i1)
    }
    return %q0, %q1 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// -----

func.func @join_short(%q0 : !prelimhlep.lin<i1>, %q1 : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i3> attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'join' but has result types ('!prelimhlep.lin<i3>'), expected ('!prelimhlep.lin<i2>')}}
    %qs = prelimhlep.lin join (%b0 : i1 from %q0 : !prelimhlep.lin<i1>, %b1 : i1 from %q1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i3>) {
        %c1 = arith.constant 1 : i3
        %e0 = arith.extui %b0 : i1 to i3
        %e1 = arith.extui %b1 : i1 to i3
        %s1 = arith.shli %e1, %c1 : i3
        %or = arith.ori %e0, %s1 : i3
        prelimhlep.output (%or : i3)
    }
    return %qs : !prelimhlep.lin<i3>
}

// -----

func.func @measure_negated(%q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'measure' but the body is not empty}}
    %out, %bit = prelimhlep.lin measure (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
        %one = arith.constant true
        %nb = arith.xori %b, %one : i1
        prelimhlep.output (%b : i1) carrying (%nb : i1)
    }
    return %out, %bit : !prelimhlep.lin<i1>, i1
}

// -----

func.func @measure_drop_keeps(%q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'measure_drop' but has result types ('!prelimhlep.lin<i1>', 'i1'), expected ('i1')}}
    %out, %bit = prelimhlep.lin measure_drop (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
        prelimhlep.output (%b : i1) carrying (%b : i1)
    }
    return %out, %bit : !prelimhlep.lin<i1>, i1
}

// -----

func.func @hadamard_swapped(%in : !prelimhlep.lin<i1>) -> !prelimhlep.lin<!prelimhlep.x<1>> attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'hadamard' but a branch yields the wrong basis symbol}}
    %x_out = prelimhlep.lin hadamard (%b: i1 from %in: !prelimhlep.lin<i1>) -> (!prelimhlep.lin<!prelimhlep.x<1>>) {
        %r = scf.if %b -> !prelimhlep.lin<!prelimhlep.x<1>> {
            %p = prelimhlep.constant "+" : !prelimhlep.lin<!prelimhlep.x<1>>
            scf.yield %p : !prelimhlep.lin<!prelimhlep.x<1>>
        } else {
            %m = prelimhlep.constant "-" : !prelimhlep.lin<!prelimhlep.x<1>>
            scf.yield %m : !prelimhlep.lin<!prelimhlep.x<1>>
        }
        prelimhlep.output () carrying (%r : !prelimhlep.lin<!prelimhlep.x<1>>)
    }
    return %x_out : !prelimhlep.lin<!prelimhlep.x<1>>
}

// -----

func.func @hadamard_z_basis(%in : !prelimhlep.lin<i1>, %other : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'hadamard' but the result is not a single-symbol X- or Y-basis 'lin' type}}
    %out = prelimhlep.lin hadamard (%b: i1 from %in: !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %r = scf.if %b -> !prelimhlep.lin<i1> {
            scf.yield %other : !prelimhlep.lin<i1>
        } else {
            scf.yield %other : !prelimhlep.lin<i1>
        }
        prelimhlep.output () carrying (%r : !prelimhlep.lin<i1>)
    }
    return %out : !prelimhlep.lin<i1>
}

// -----

func.func @phase_non_unit(%q : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'phase' but the scale factor does not have unit modulus}}
    %out = prelimhlep.lin phase (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %r = scf.if %b -> i1 {
            %two = complex.constant [2.0, 0.0] : complex<f64>
            %s = prelimhlep.scale %two, %b : (complex<f64>, i1) -> i1
            scf.yield %s : i1
        } else {
            scf.yield %b : i1
        }
        prelimhlep.output (%r : i1)
    }
    return %out : !prelimhlep.lin<i1>
}

// -----

func.func @phase_wrong_branch(%q : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'phase' but the branches are not 'scale by a constant' and 'pass through'}}
    %out = prelimhlep.lin phase (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        %r = scf.if %b -> i1 {
            scf.yield %b : i1
        } else {
            %neg = complex.constant [-1.0, 0.0] : complex<f64>
            %s = prelimhlep.scale %neg, %b : (complex<f64>, i1) -> i1
            scf.yield %s : i1
        }
        prelimhlep.output (%r : i1)
    }
    return %out : !prelimhlep.lin<i1>
}

// -----

func.func @ctrl_untagged_gate(%control : !prelimhlep.lin<i1>, %target : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'ctrl' but the controlled gate is not an 'x'- or 'phase'-shaped 'prelimhlep.lin'}}
    %oc, %ot = prelimhlep.lin ctrl (%cb : i1 from %control : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %new_target = scf.if %cb -> (!prelimhlep.lin<i1>) {
            %flipped = prelimhlep.lin (%tb : i1 from %target : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
                %one = arith.constant true
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

// -----

func.func @ctrl_wrong_conjunction(%a : !prelimhlep.lin<i1>, %b : !prelimhlep.lin<i1>, %target : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>) attributes { prelimhlep.halo } {
    // expected-error @below {{tagged 'ctrl' but the 'scf.if' does not branch on the conjunction of all control bits}}
    %r:3 = prelimhlep.lin ctrl (%ab : i1 from %a : !prelimhlep.lin<i1>, %bb : i1 from %b : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>) {
        %cond = arith.ori %ab, %bb : i1
        %new_target = scf.if %cond -> (!prelimhlep.lin<i1>) {
            %flipped = prelimhlep.lin x (%tb : i1 from %target : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
                %one = arith.constant true
                %ntb = arith.xori %tb, %one : i1
                prelimhlep.output (%ntb : i1)
            }
            scf.yield %flipped : !prelimhlep.lin<i1>
        } else {
            scf.yield %target : !prelimhlep.lin<i1>
        }
        prelimhlep.output (%ab : i1, %bb : i1) carrying (%new_target : !prelimhlep.lin<i1>)
    }
    return %r#0, %r#1, %r#2 : !prelimhlep.lin<i1>, !prelimhlep.lin<i1>, !prelimhlep.lin<i1>
}

// -----

func.func @unknown_shape(%q : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    // expected-error @below {{unknown 'prelimhlep.lin' shape 'toffoli'}}
    %out = prelimhlep.lin toffoli (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
        prelimhlep.output (%b : i1)
    }
    return %out : !prelimhlep.lin<i1>
}
