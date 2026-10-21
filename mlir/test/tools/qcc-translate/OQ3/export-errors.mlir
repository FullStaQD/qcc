// RUN: qcc-translate --export-openqasm --split-input-file --verify-diagnostics %s

// Modules that cannot be exported to OpenQASM.

// expected-error @below {{is not an OpenQASM program: expected a module with the 'oq3.version' attribute}}
module {}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'qcc.static' op cannot be exported to OpenQASM}}
    %q = qcc.static [0] : !qcc.qubit
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
