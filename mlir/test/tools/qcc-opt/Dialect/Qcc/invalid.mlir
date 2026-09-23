// RUN: qcc-opt %s --split-input-file --verify-diagnostics

#trap = #magic.trap<capacity = 1, couplings = [dense<0.0> : tensor<1x1xf64>]>
// expected-error @+1 {{'func.func' op attribute 'qcc.device' is only valid on a module}}
func.func @not_a_module() attributes {qcc.device = #magic.device<name = "d", time_unit_ns = 1000, initial_occupancies = [1], traps = [#trap]>} {
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
