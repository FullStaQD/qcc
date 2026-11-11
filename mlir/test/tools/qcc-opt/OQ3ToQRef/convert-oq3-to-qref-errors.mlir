// RUN: qcc-opt %s --convert-oq3-to-qref --split-input-file --verify-diagnostics

// Without a data layout, an `int` is lowered to `i64`.
func.func @main() attributes {qcc.entry_point} {
  %q = oq3.qubit_decl "q" : !qcc.qubit_ref
  // expected-error @+1 {{the integer literal does not fit into the 64 bits of 'int'}}
  %big = oq3.constant #oq3.int<9223372036854775808> : !oq3.int
  %f = oq3.cast %big implicit : !oq3.int -> !oq3.float
  %angle = oq3.cast %f implicit : !oq3.float -> !qcc.angle
  oq3.gate_call @U(%angle, %angle, %angle : !qcc.angle, !qcc.angle, !qcc.angle) [%q : !qcc.qubit_ref]
  return
}

// -----

// Without a data layout, a `float` is lowered to `f64`.
func.func @main() attributes {qcc.entry_point} {
  %q = oq3.qubit_decl "q" : !qcc.qubit_ref
  // expected-error @+1 {{the floating-point literal does not fit into the 64 bits of 'float'}}
  %huge = oq3.constant #oq3.float<"1e400"> : !oq3.float
  %angle = oq3.cast %huge implicit : !oq3.float -> !qcc.angle
  oq3.gate_call @U(%angle, %angle, %angle : !qcc.angle, !qcc.angle, !qcc.angle) [%q : !qcc.qubit_ref]
  return
}

// -----

// The target's word size defines the width of `int`.
module attributes {dlti.dl_spec = #dlti.dl_spec<index = 32>} {
  func.func @main() attributes {qcc.entry_point} {
    %r = oq3.declare "r" : !qcc.ref<!oq3.bit>
    // expected-error @+1 {{the integer literal does not fit into the 32 bits of 'int'}}
    %big = oq3.constant #oq3.int<2147483648> : !oq3.int
    %b = oq3.cast %big implicit : !oq3.int -> !oq3.bit
    qcc.ref.store %b, %r : !qcc.ref<!oq3.bit>
    return
  }
}

// -----

// ... and of `float`.
module attributes {dlti.dl_spec = #dlti.dl_spec<index = 32>} {
  func.func @main() attributes {qcc.entry_point} {
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    // expected-error @+1 {{the floating-point literal does not fit into the 32 bits of 'float'}}
    %huge = oq3.constant #oq3.float<"1e39"> : !oq3.float
    %angle = oq3.cast %huge implicit : !oq3.float -> !qcc.angle
    oq3.gate_call @rx(%angle : !qcc.angle) [%q : !qcc.qubit_ref]
    return
  }
}

// -----

// expected-error @+1 {{there is no 24-bit 'float' for the target's word size}}
module attributes {dlti.dl_spec = #dlti.dl_spec<index = 24>} {
  func.func @main() attributes {qcc.entry_point} {
    return
  }
}

// -----

// Unsupported features for now.

func.func @f(%reg: !oq3.qreg<2>, %index: !oq3.int) {
  // expected-error @+1 {{an index that is not a constant expression cannot be converted to 'qref'}}
  %q = oq3.qubit_index %reg[%index] : !oq3.qreg<2>, !oq3.int
  return
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func private @f()
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @+1 {{global definitions cannot be converted to 'qref'}}
    oq3.defined @f
    return
  }
}

// -----

// Unsupported gates. TODO: Add decomposition.
func.func @main() attributes {qcc.entry_point} {
  %a = oq3.qubit_decl "a" : !qcc.qubit_ref
  %b = oq3.qubit_decl "b" : !qcc.qubit_ref
  %c = oq3.qubit_decl "c" : !qcc.qubit_ref
  %pi = oq3.math_constant pi : !oq3.float
  %theta = oq3.cast %pi implicit : !oq3.float -> !qcc.angle
  // expected-error @below {{the gate 'ch' cannot be converted to 'qref'}}
  oq3.gate_call @ch [%a, %b : !qcc.qubit_ref, !qcc.qubit_ref]
  // expected-error @below {{the gate 'crx' cannot be converted to 'qref'}}
  oq3.gate_call @crx(%theta : !qcc.angle) [%a, %b : !qcc.qubit_ref, !qcc.qubit_ref]
  // expected-error @below {{the gate 'cry' cannot be converted to 'qref'}}
  oq3.gate_call @cry(%theta : !qcc.angle) [%a, %b : !qcc.qubit_ref, !qcc.qubit_ref]
  // expected-error @below {{the gate 'crz' cannot be converted to 'qref'}}
  oq3.gate_call @crz(%theta : !qcc.angle) [%a, %b : !qcc.qubit_ref, !qcc.qubit_ref]
  // expected-error @below {{the gate 'cu' cannot be converted to 'qref'}}
  oq3.gate_call @cu(%theta, %theta, %theta, %theta : !qcc.angle, !qcc.angle, !qcc.angle, !qcc.angle) [%a, %b : !qcc.qubit_ref, !qcc.qubit_ref]
  // expected-error @below {{the gate 'ccx' cannot be converted to 'qref'}}
  oq3.gate_call @ccx [%a, %b, %c : !qcc.qubit_ref, !qcc.qubit_ref, !qcc.qubit_ref]
  // expected-error @below {{the gate 'cswap' cannot be converted to 'qref'}}
  oq3.gate_call @cswap [%a, %b, %c : !qcc.qubit_ref, !qcc.qubit_ref, !qcc.qubit_ref]
  return
}
