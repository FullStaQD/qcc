// A two-trap device with capacity 5 per trap and a time unit of 1 us.
#trap = #magic.trap<capacity = 5, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1.0],
         [1.0, 0.0]]> : tensor<2x2xf64>,
  dense<[[0.0, 1.0, 0.5],
         [1.0, 0.0, 1.0],
         [0.5, 1.0, 0.0]]> : tensor<3x3xf64>,
  dense<[[0.0, 1.0, 0.5, 0.25],
         [1.0, 0.0, 1.0, 0.5],
         [0.5, 1.0, 0.0, 1.0],
         [0.25, 0.5, 1.0, 0.0]]> : tensor<4x4xf64>,
  dense<[[0.0, 1.0, 0.5, 0.25, 0.125],
         [1.0, 0.0, 1.0, 0.5, 0.25],
         [0.5, 1.0, 0.0, 1.0, 0.5],
         [0.25, 0.5, 1.0, 0.0, 1.0],
         [0.125, 0.25, 0.5, 1.0, 0.0]]> : tensor<5x5xf64>]>

module attributes {qcc.device = #magic.device<name = "two-trap-2x5", time_unit_ns = 1000, traps = [#trap, #trap]>} {}
