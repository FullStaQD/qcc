// A two-trap device with capacity 3 per trap and a time unit of 1 us.
#trap = #magic.trap<capacity = 3, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1.0], [1.0, 0.0]]> : tensor<2x2xf64>,
  dense<[[0.0, 1.0, 0.5], [1.0, 0.0, 1.0], [0.5, 1.0, 0.0]]> : tensor<3x3xf64>]>

module attributes {qcc.device = #magic.device<name = "two-trap-2x3", time_unit_ns = 1000, traps = [#trap, #trap]>} {}
