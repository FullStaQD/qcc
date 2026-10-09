// RUN: qcc-opt %s --split-input-file --verify-diagnostics

#trap = #magic.trap<capacity = 1, couplings = [dense<0.0> : tensor<1x1xf64>]>
// expected-error @+1 {{'func.func' op attribute 'qcc.device' is only valid on a module}}
func.func @not_a_module() attributes {qcc.device = #magic.device<name = "d", time_unit_ns = 1000, traps = [#trap]>} {
  return
}

// -----

// expected-error @+1 {{'builtin.module' op attribute 'qcc.device' must be a device description, got 42 : i64}}
module attributes {qcc.device = 42} {}

// -----

// expected-error @+1 {{'builtin.module' op attribute 'qcc.entry_point' is only valid on a function}}
module attributes {qcc.entry_point} {}

// -----

// expected-error @+1 {{'func.func' op attribute 'qcc.entry_point' must be a unit attribute, got true}}
func.func @not_a_unit() attributes {qcc.entry_point = true} {
  return
}

// -----

// A qubit has value semantics, so it is no memref element.
// expected-error @+1 {{invalid memref element type}}
func.func @qubit_memref(%m: memref<2x!qcc.qubit>) {
  return
}

// -----

func.func @static_wrong_type() {
  // expected-error @+1 {{'qcc.static' op result #0 must be variadic of qubit value, but got 'i1'}}
  %q = qcc.static [0] : i1
  return
}

// -----

func.func @static_result_count() {
  // expected-error @+1 {{'qcc.static' op expected one qubit per index, got 1 qubit(s) for 2 indices}}
  %q = "qcc.static"() {indices = array<i64: 0, 1>} : () -> (!qcc.qubit)
  return
}

// -----

func.func @static_negative_index() {
  // expected-error @+1 {{'qcc.static' op index must be non-negative, got -1}}
  %q = qcc.static [-1] : !qcc.qubit
  return
}

// -----

func.func @static_duplicate_index() {
  // expected-error @+1 {{'qcc.static' op index 2 appears more than once}}
  %q0, %q1 = qcc.static [2, 2] : !qcc.qubit
  return
}

// -----

llvm.func @static_outside_func() {
  // expected-error @+1 {{'qcc.static' op must be directly inside a 'func.func'}}
  %q = qcc.static [0] : !qcc.qubit
  llvm.return
}

// -----

func.func @static_twice() {
  // expected-note @+1 {{the earlier 'qcc.static' is here}}
  %q0 = qcc.static [0] : !qcc.qubit
  %c = arith.constant 1 : i32
  // expected-error @+1 {{'qcc.static' op a function has at most one 'qcc.static': one op creates all of its qubits}}
  %q1 = qcc.static [1] : !qcc.qubit
  return
}
