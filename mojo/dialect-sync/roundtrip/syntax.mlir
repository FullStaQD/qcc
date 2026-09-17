// Round-trip corpus for the shared PrelimHLEP syntax: every construct with a
// hand-written parser or printer, plus the types and attributes the exchange
// format carries. Run through qcc-opt and the fork's kgen-opt by
// 'mojo/dialect-sync/roundtrip.py'; the two generic-form prints must be
// byte-identical.
//
// Deliberately no enclosing function: the fork does not register the 'func'
// dialect, and verification is off on both sides, so the ops sit at module
// scope and only the syntax is under test. 'test.*' stands in for whatever
// classical op produced a value.

// 'lin' with no shape keyword, one binding, one delinearized result.
%q0 = "test.qubit"() : () -> !prelimhlep.lin<i1>
%r0 = prelimhlep.lin (%b0 : i1 from %q0 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
  prelimhlep.output (%b0 : i1)
}

// Every shape keyword, so the enum's stringify/symbolize pair is covered.
%r1 = prelimhlep.lin alloc (%b1 : i1 from %q0 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
  prelimhlep.output (%b1 : i1)
}
%r2 = prelimhlep.lin split (%b2 : i1 from %q0 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
  prelimhlep.output (%b2 : i1)
}
%r3 = prelimhlep.lin join (%b3 : i1 from %q0 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
  prelimhlep.output (%b3 : i1)
}
%r4 = prelimhlep.lin x (%b4 : i1 from %q0 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
  prelimhlep.output (%b4 : i1)
}
%r5 = prelimhlep.lin measure (%b5 : i1 from %q0 : !prelimhlep.lin<i1>) -> (i1) {
  prelimhlep.output () carrying (%b5 : i1)
}
%r6 = prelimhlep.lin measure_drop (%b6 : i1 from %q0 : !prelimhlep.lin<i1>) -> (i1) {
  prelimhlep.output () carrying (%b6 : i1)
}
%r7 = prelimhlep.lin hadamard (%b7 : i1 from %q0 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
  prelimhlep.output (%b7 : i1)
}
%r8 = prelimhlep.lin phase (%b8 : i1 from %q0 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
  prelimhlep.output (%b8 : i1)
}
%r9 = prelimhlep.lin ctrl (%b9 : i1 from %q0 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
  prelimhlep.output (%b9 : i1)
}

// Several bindings, and both operand groups of 'output' at once: this is the
// shape a two-qubit gate elaborates to.
%q1 = "test.qubit"() : () -> !prelimhlep.lin<i1>
%r10:2 = prelimhlep.lin (%c0 : i1 from %q0 : !prelimhlep.lin<i1>, %c1 : i1 from %q1 : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, i1) {
  prelimhlep.output (%c0 : i1) carrying (%c1 : i1)
}

// Wider bases, and the non-integer basis types.
%q2 = "test.reg"() : () -> !prelimhlep.lin<i8>
%r11 = prelimhlep.base_change %q2 : !prelimhlep.lin<i8> -> !prelimhlep.lin<!prelimhlep.x<8>>
%r12 = prelimhlep.base_change %q2 : !prelimhlep.lin<i8> -> !prelimhlep.lin<!prelimhlep.y<8>>
%c1 = prelimhlep.constant "+-+-+-+-" : !prelimhlep.lin<!prelimhlep.x<8>>
%c2 = prelimhlep.constant "-><--><-" : !prelimhlep.lin<!prelimhlep.y<4>>

// The unit type and its producer.
%u = prelimhlep.unit_value : !prelimhlep.unit

// Hamiltonians: the one attribute with a hand-written parser and printer.
// A bare single factor, an explicit coefficient, a negative coefficient, a
// product of factors, and a sum of terms.
%theta = "test.angle"() : () -> f64
%e0 = prelimhlep.exp %theta hamiltonian<1, Z[0]> %q0 : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
%e1 = prelimhlep.exp %theta hamiltonian<1, 5.000000e-01 * X[0]> %q0 : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
%e2 = prelimhlep.exp %theta hamiltonian<1, -2.500000e-01 * Y[0]> %q0 : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
%e3 = prelimhlep.exp %theta hamiltonian<8, X[0] * Y[1] * Z[2]> %q2 : (f64, !prelimhlep.lin<i8>) -> !prelimhlep.lin<i8>
%e4 = prelimhlep.exp %theta hamiltonian<8, Z[0] + 2.500000e+00 * X[1] * Z[3] + -1.000000e+00 * Y[7]> %q2 : (f64, !prelimhlep.lin<i8>) -> !prelimhlep.lin<i8>

// Scale and add_phase carry no custom syntax but do carry the types.
%f = "test.factor"() : () -> complex<f64>
%s0 = prelimhlep.scale %f, %q0 : (complex<f64>, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
%p0 = prelimhlep.add_phase %theta, %q0 : (f64, !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>

// The halo attribute, on an op that is not a function: verification is off,
// and what is under test is that both sides print the attribute alike.
"test.haloed"() { prelimhlep.halo = #prelimhlep.halo } : () -> ()
