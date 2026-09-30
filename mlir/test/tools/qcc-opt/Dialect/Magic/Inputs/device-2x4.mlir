#trap = #magic.trap<capacity = 4, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1.0],
         [1.0, 0.0]]> : tensor<2x2xf64>,
  dense<[[0.0, 1.0, 0.5],
         [1.0, 0.0, 1.0],
         [0.5, 1.0, 0.0]]> : tensor<3x3xf64>,
  dense<[[0.0, 1.0, 0.5, 0.25],
         [1.0, 0.0, 1.0, 0.5],
         [0.5, 1.0, 0.0, 1.0],
         [0.25, 0.5, 1.0, 0.0]]> : tensor<4x4xf64>]>

module attributes {qcc.device = #magic.device<name = "two-trap-2x4", time_unit_ns = 1000, initial_occupancies = [2, 2], traps = [#trap, #trap]>} {}
