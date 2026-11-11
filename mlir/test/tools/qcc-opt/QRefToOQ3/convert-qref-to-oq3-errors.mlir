// RUN: qcc-opt %s --convert-qref-to-oq3 --split-input-file --verify-diagnostics

// expected-error @below {{expected exactly one entry function ('qcc.entry_point') to convert to OpenQASM}}
module {
  func.func @not_an_entry_function() {
    return
  }
}

// -----

// expected-error @below {{an entry function with arguments or results cannot be converted to OpenQASM}}
func.func @main_with_argument(%theta: f64) attributes {qcc.entry_point} {
  return
}

// -----

// expected-error @below {{only the entry function can be converted to OpenQASM}}
func.func private @helper()

func.func @main() attributes {qcc.entry_point} {
  return
}

// -----

func.func @dynamically_sized_array() attributes {qcc.entry_point} {
  %c3 = arith.constant 3 : index
  // expected-error @below {{an array of qubits of dynamic size cannot be converted to OpenQASM}}
  %r = qcc.alloc %c3 : tensor<?x!qcc.qubit_ref>
  return
}

// -----

func.func @if_unsupported() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  %bit = qref.measure z %q : !qcc.qubit_ref -> i1
  // expected-error @below {{'scf.if' cannot be converted to OpenQASM}}
  scf.if %bit {
    qref.single x %q : !qcc.qubit_ref
  }
  return
}

// -----

// The target's `float` has its word size, 64 bits without a `dlti.dl_spec`.
func.func @f32() attributes {qcc.entry_point} {
  // expected-error @below {{a constant 1.500000e+00 : f32 cannot be converted to OpenQASM}}
  %c = arith.constant 1.5 : f32
  return
}

// -----

module attributes {dlti.dl_spec = #dlti.dl_spec<index = 32>} {
  func.func @f64_with_32_bit_word_size() attributes {qcc.entry_point} {
    // expected-error @below {{a constant 1.500000e+00 : f64 cannot be converted to OpenQASM}}
    %c = arith.constant 1.5 : f64
    return
  }
}

// -----

module attributes {dlti.dl_spec = #dlti.dl_spec<index = 32>} {
  func.func @sitofp_to_f64_with_32_bit_word_size() attributes {qcc.entry_point} {
    %c = arith.constant 2 : i32
    // expected-error @below {{only conversions to the target's 'float', 'f32', can be converted to OpenQASM}}
    %f = arith.sitofp %c : i32 to f64
    return
  }
}

// -----

// expected-error @below {{there is no 24-bit 'float' for the target's word size}}
module attributes {dlti.dl_spec = #dlti.dl_spec<index = 24>} {
  func.func @no_float_for_word_size() attributes {qcc.entry_point} {
    return
  }
}

// -----

func.func @infinity() attributes {qcc.entry_point} {
  // expected-error @below {{non-finite constant cannot be converted to OpenQASM}}
  %c = arith.constant 0x7FF0000000000000 : f64 // +inf
  return
}

// -----

func.func @only_single_memref_allowed() attributes {qcc.entry_point} {
  // expected-error @below {{only the storage of a 'bit' or 'bit[n]', 'memref<i1>' or 'memref<nxi1>', can be converted to OpenQASM, got 'memref<2xi32>'}}
  %c = memref.alloca() : memref<2xi32>
  return
}

// -----

func.func @memref_load() attributes {qcc.entry_point} {
  %c = memref.alloca() : memref<2xi1>
  %c0 = arith.constant 0 : index
  // expected-error @below {{reading a bit of a register cannot be converted to OpenQASM}}
  %bit = memref.load %c[%c0] : memref<2xi1>
  return
}

// -----

func.func @extui_unsupported() attributes {qcc.entry_point} {
  %q = qcc.alloc : !qcc.qubit_ref
  %bit = qref.measure z %q : !qcc.qubit_ref -> i1
  // expected-error @below {{'arith.extui' cannot be converted to OpenQASM}}
  %int = arith.extui %bit : i1 to i64
  return
}

// -----

// expected-error @below {{an entry function with more than one block cannot be converted to OpenQASM}}
func.func @multiple_blocks() attributes {qcc.entry_point} {
  cf.br ^next
^next:
  return
}

// -----

// Gates that would need a decomposition into several standard gates.
func.func @unsupported_gates() attributes {qcc.entry_point} {
  %a = qcc.alloc : !qcc.qubit_ref
  %b = qcc.alloc : !qcc.qubit_ref
  %theta = arith.constant 0.5 : f64
  // expected-error @below {{the gate 'u_zxz' cannot be converted to OpenQASM}}
  qref.single u_zxz(%theta, %theta, %theta) %a : f64, !qcc.qubit_ref
  return
}

// -----

func.func @rzz_unsupported() attributes {qcc.entry_point} {
  %a = qcc.alloc : !qcc.qubit_ref
  %b = qcc.alloc : !qcc.qubit_ref
  %theta = arith.constant 0.5 : f64
  // expected-error @below {{the gate 'rzz' cannot be converted to OpenQASM}}
  qref.pair rzz(%theta) %a, %b : f64, !qcc.qubit_ref
  return
}

// -----

func.func @rxx_unsupported() attributes {qcc.entry_point} {
  %a = qcc.alloc : !qcc.qubit_ref
  %b = qcc.alloc : !qcc.qubit_ref
  %theta = arith.constant 0.5 : f64
  // expected-error @below {{the gate 'rxx' cannot be converted to OpenQASM}}
  qref.pair rxx(%theta) %a, %b : f64, !qcc.qubit_ref
  return
}

// -----

func.func @ryy_unsupported() attributes {qcc.entry_point} {
  %a = qcc.alloc : !qcc.qubit_ref
  %b = qcc.alloc : !qcc.qubit_ref
  %theta = arith.constant 0.5 : f64
  // expected-error @below {{the gate 'ryy' cannot be converted to OpenQASM}}
  qref.pair ryy(%theta) %a, %b : f64, !qcc.qubit_ref
  return
}

// -----

func.func @iswap_unsupported() attributes {qcc.entry_point} {
  %a = qcc.alloc : !qcc.qubit_ref
  %b = qcc.alloc : !qcc.qubit_ref
  // expected-error @below {{the gate 'iswap' cannot be converted to OpenQASM}}
  qref.pair iswap %a, %b : !qcc.qubit_ref
  return
}

// -----

// TODO: `crz` is not supported: OpenQASM reduces gate angles modulo 2π, but `crz` is 4π-periodic.
func.func @crz_unsupported() attributes {qcc.entry_point} {
  %a = qcc.alloc : !qcc.qubit_ref
  %b = qcc.alloc : !qcc.qubit_ref
  %theta = arith.constant 0.5 : f64
  // expected-error @below {{the gate 'crz' cannot be converted to OpenQASM}}
  qref.pair crz(%theta) %a, %b : f64, !qcc.qubit_ref
  return
}
