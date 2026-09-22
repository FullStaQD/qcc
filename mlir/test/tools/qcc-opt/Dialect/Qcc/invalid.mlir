// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// expected-error @+1 {{capacity must be at least 1, got 0}}
#trap = #qcc.magic_trap<capacity = 0, couplings = []>

// -----

// expected-error @+1 {{expected one coupling matrix per occupancy 1..2, got 1}}
#trap = #qcc.magic_trap<capacity = 2, couplings = [dense<0.0> : tensor<1x1xf64>]>

// -----

// expected-error @+1 {{coupling matrix for 2 ions must have type tensor<2x2xf64>, got 'tensor<2x3xf64>'}}
#trap = #qcc.magic_trap<capacity = 2, couplings = [dense<0.0> : tensor<1x1xf64>, dense<0.0> : tensor<2x3xf64>]>

// -----

// expected-error @+1 {{coupling matrix for 1 ions must have type tensor<1x1xf64>, got 'tensor<1x1xf32>'}}
#trap = #qcc.magic_trap<capacity = 1, couplings = [dense<0.0> : tensor<1x1xf32>]>

// -----

// expected-error @+1 {{coupling matrix for 2 ions must be symmetric}}
#trap = #qcc.magic_trap<capacity = 2, couplings = [dense<0.0> : tensor<1x1xf64>, dense<[[0.0, 1.0], [2.0, 0.0]]> : tensor<2x2xf64>]>

// -----

// expected-error @+1 {{coupling matrix for 1 ions must have a zero diagonal}}
#trap = #qcc.magic_trap<capacity = 1, couplings = [dense<1.0> : tensor<1x1xf64>]>

// -----

#trap = #qcc.magic_trap<capacity = 1, couplings = [dense<0.0> : tensor<1x1xf64>]>
// expected-error @+1 {{name must not be empty}}
#device = #qcc.magic_device<name = "", time_unit_ns = 1000, initial_occupancies = [1], traps = [#trap]>

// -----

#trap = #qcc.magic_trap<capacity = 1, couplings = [dense<0.0> : tensor<1x1xf64>]>
// expected-error @+1 {{time_unit_ns must be positive, got 0}}
#device = #qcc.magic_device<name = "d", time_unit_ns = 0, initial_occupancies = [1], traps = [#trap]>

// -----

// expected-error @+1 {{expected at least one trap}}
#device = #qcc.magic_device<name = "d", time_unit_ns = 1000, initial_occupancies = [1], traps = []>

// -----

#trap = #qcc.magic_trap<capacity = 1, couplings = [dense<0.0> : tensor<1x1xf64>]>
// expected-error @+1 {{expected one initial occupancy per trap, got 1 occupancies for 2 traps}}
#device = #qcc.magic_device<name = "d", time_unit_ns = 1000, initial_occupancies = [1], traps = [#trap, #trap]>

// -----

#trap = #qcc.magic_trap<capacity = 1, couplings = [dense<0.0> : tensor<1x1xf64>]>
// expected-error @+1 {{initial occupancy of trap 1 must be in 0..1, got 2}}
#device = #qcc.magic_device<name = "d", time_unit_ns = 1000, initial_occupancies = [1, 2], traps = [#trap, #trap]>

// -----

#trap = #qcc.magic_trap<capacity = 1, couplings = [dense<0.0> : tensor<1x1xf64>]>
// expected-error @+1 {{'func.func' op attribute 'qcc.device' is only valid on a module}}
func.func @not_a_module() attributes {qcc.device = #qcc.magic_device<name = "d", time_unit_ns = 1000, initial_occupancies = [1], traps = [#trap]>} {
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
