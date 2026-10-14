// RUN: qcc-translate --export-openqasm --split-input-file --verify-diagnostics --allow-unregistered-dialect %s

// Modules that cannot be exported to OpenQASM.

// expected-error @below {{is not an OpenQASM program: expected a module with the 'oq3.version' attribute}}
module {}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'test.op' op cannot be exported to OpenQASM}}
    "test.op"() : () -> ()
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func private @f()
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'oq3.defined' op marks a global definition, whose export is not supported yet}}
    oq3.defined @f
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    // expected-error @below {{'test.angle' op cannot be exported to OpenQASM}}
    %x = "test.angle"() : () -> !qcc.angle
    oq3.gate_call @U(%x, %x, %x : !qcc.angle, !qcc.angle, !qcc.angle) [%q : !qcc.qubit_ref]
    return
  }
}
