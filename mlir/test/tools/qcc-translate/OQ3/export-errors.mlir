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

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    // expected-error @below {{'oq3.measure' op must be used exactly once, by the next statement, to be exported to OpenQASM}}
    %m = oq3.measure %q : !qcc.qubit_ref -> !oq3.bit
    %c = oq3.declare "c" = %m : !oq3.bit : !qcc.ref<!oq3.bit>
    %d = oq3.declare "d" = %m : !oq3.bit : !qcc.ref<!oq3.bit>
    return
  }
}

// -----

// The load would be printed after the store, and read the stored value.
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    %c = oq3.declare "c" : !qcc.ref<!oq3.bit>
    // expected-error @below {{'qcc.ref.load' op must be used exactly once, by the next statement, to be exported to OpenQASM}}
    %v = qcc.ref.load %c : !qcc.ref<!oq3.bit>
    %m = oq3.measure %q : !qcc.qubit_ref -> !oq3.bit
    qcc.ref.store %m, %c : !qcc.ref<!oq3.bit>
    %d = oq3.declare "d" = %v : !oq3.bit : !qcc.ref<!oq3.bit>
    return
  }
}
