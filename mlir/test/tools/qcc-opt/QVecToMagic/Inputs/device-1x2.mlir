// A single trap holding two ions, capacity 2, a coupling of 1.0 and a time unit of 1 us.
#trap = #magic.trap<capacity = 2, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1.0], [1.0, 0.0]]> : tensor<2x2xf64>]>

module attributes {qcc.device = #magic.device<name = "one-trap-1x2", time_unit_ns = 1000, initial_occupancies = [2], traps = [#trap]>} {}
